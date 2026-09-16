import AppKit
import CoreGraphics
import CoreImage
import Foundation
import Testing
@testable import TwoWay

/// GA 导出格式 `otpauth-migration://` 解析（C2-6b）
@MainActor
@Suite("OTPMigration（GA 导出迁移码）")
struct OTPMigrationTests {

    // MARK: protobuf 编码辅助（测试侧构造载荷）

    private func varint(_ value: Int) -> [UInt8] {
        var v = UInt64(value), bytes: [UInt8] = []
        repeat {
            var byte = v & 0b0111_1111
            v >>= 7
            if v > 0 { byte |= 0b1000_0000 }
            bytes.append(UInt8(byte))
        } while v > 0
        return bytes
    }

    private func tag(_ number: Int, _ wireType: Int) -> [UInt8] {
        varint((number << 3) | wireType)
    }

    private func lengthDelimited(_ number: Int, _ payload: [UInt8]) -> [UInt8] {
        tag(number, 2) + varint(payload.count) + payload
    }

    private func varintField(_ number: Int, _ value: Int) -> [UInt8] {
        tag(number, 0) + varint(value)
    }

    /// 构造一条 OtpParameters
    private func otpParameters(
        secret: [UInt8],
        name: String,
        issuer: String? = nil,
        algorithm: Int = 1,   // SHA1
        digits: Int = 1,      // SIX
        type: Int = 2         // TOTP
    ) -> [UInt8] {
        var bytes = lengthDelimited(1, secret) + lengthDelimited(2, Array(name.utf8))
        if let issuer { bytes += lengthDelimited(3, Array(issuer.utf8)) }
        bytes += varintField(4, algorithm)
        bytes += varintField(5, digits)
        bytes += varintField(6, type)
        return bytes
    }

    private func migrationURI(parameters: [[UInt8]]) -> String {
        var payload: [UInt8] = []
        for p in parameters {
            payload += lengthDelimited(1, p)
        }
        payload += varintField(2, 1)   // version
        let base64 = Data(payload).base64EncodedString()
            .replacingOccurrences(of: "+", with: "%2B")
            .replacingOccurrences(of: "/", with: "%2F")
            .replacingOccurrences(of: "=", with: "%3D")
        return "otpauth-migration://offline?data=\(base64)"
    }

    // MARK: 解析

    @Test("单 TOTP 账户：secret / name 切分 / issuer / 参数全部还原")
    func singleEntry() throws {
        let uri = migrationURI(parameters: [
            otpParameters(
                secret: Array(repeating: 0x01, count: 20),
                name: "GitHub:you@example.com",
                issuer: "GitHub"
            ),
        ])

        let result = try OTPMigration.parse(uri)
        #expect(result.entries.count == 1)
        #expect(result.skippedHOTPCount == 0)

        let entry = try #require(result.entries.first)
        #expect(entry.displayName == "you@example.com")
        #expect(entry.issuer == "GitHub")
        #expect(entry.secret == Data(repeating: 0x01, count: 20))
        #expect(entry.parameters.algorithm == .sha1)
        #expect(entry.parameters.digits == 6)
        #expect(entry.parameters.period == 30)
    }

    @Test("label 无前缀时：issuer 回落到 field 3；SHA-256 / 8 位映射正确")
    func variants() throws {
        let uri = migrationURI(parameters: [
            otpParameters(
                secret: Array(repeating: 0x02, count: 32),
                name: "ops@dev",
                issuer: "ops.dev",
                algorithm: 2,   // SHA256
                digits: 2       // EIGHT
            ),
        ])

        let entry = try #require(try OTPMigration.parse(uri).entries.first)
        #expect(entry.displayName == "ops@dev")
        #expect(entry.issuer == "ops.dev")
        #expect(entry.parameters.algorithm == .sha256)
        #expect(entry.parameters.digits == 8)
    }

    @Test("HOTP（type=1）被跳过且计数知情（PRD 范围外不静默）")
    func hotpSkipped() throws {
        let uri = migrationURI(parameters: [
            otpParameters(secret: Array(repeating: 1, count: 10), name: "totp-one"),
            otpParameters(secret: Array(repeating: 2, count: 10), name: "hotp-one", type: 1),
            otpParameters(secret: Array(repeating: 3, count: 10), name: "totp-two"),
        ])

        let result = try OTPMigration.parse(uri)
        #expect(result.entries.count == 2)
        #expect(result.skippedHOTPCount == 1)
        #expect(result.entries.map(\.displayName) == ["totp-one", "totp-two"])
    }

    @Test("全部 HOTP → noTOTPEntries 错误")
    func allHOTP() {
        let uri = migrationURI(parameters: [
            otpParameters(secret: Array(repeating: 1, count: 10), name: "hotp", type: 1),
        ])
        #expect(throws: OTPMigration.MigrationError.noTOTPEntries) {
            try OTPMigration.parse(uri)
        }
    }

    @Test("非 migration scheme / 缺 data → 明确报错（不静默）")
    func schemeGuard() {
        #expect(throws: OTPMigration.MigrationError.invalidScheme) {
            try OTPMigration.parse("otpauth://totp/x?secret=JBSWY3DPEHPK3PXP")
        }
        #expect(throws: OTPMigration.MigrationError.malformedPayload) {
            try OTPMigration.parse("otpauth-migration://offline?foo=bar")
        }
    }

    // MARK: QRImport 集成

    @Test("resolve：迁移 URI → migrated（多账户）")
    func resolveMigrated() throws {
        let uri = migrationURI(parameters: [
            otpParameters(secret: Array(repeating: 1, count: 10), name: "A:one", issuer: "A"),
            otpParameters(secret: Array(repeating: 2, count: 10), name: "B:two", issuer: "B"),
        ])

        guard case .migrated(let accounts, let skipped) = QRImport.resolve([uri]) else {
            Issue.record("期望 .migrated")
            return
        }
        #expect(accounts.count == 2)
        #expect(skipped == 0)
        #expect(accounts.map(\.displayName) == ["one", "two"])
    }

    // MARK: 编码（C4-4：导出给 GA 扫描）

    @Test("编码 → 解析往返：账户/发行方/密钥/算法/位数全部还原")
    func encodeRoundTrip() throws {
        let entries = [
            OTPMigration.Entry(
                displayName: "you@example.com",
                issuer: "GitHub",
                secret: Data(repeating: 0x01, count: 20),
                parameters: OTPParameters.standard
            ),
            OTPMigration.Entry(
                displayName: "ops@dev",
                issuer: nil,
                secret: Data(repeating: 0x02, count: 32),
                parameters: try OTPParameters(algorithm: .sha256, digits: 8, period: 30)
            ),
        ]

        let uri = OTPMigration.migrationURI(entries: entries)
        #expect(uri.hasPrefix("otpauth-migration://offline?data="))

        let parsed = try OTPMigration.parse(uri)
        #expect(parsed.entries.count == 2)
        #expect(parsed.skippedHOTPCount == 0)

        let first = try #require(parsed.entries.first)
        #expect(first.displayName == "you@example.com")
        #expect(first.issuer == "GitHub")
        #expect(first.secret == Data(repeating: 0x01, count: 20))
        #expect(first.parameters.algorithm == .sha1)
        #expect(first.parameters.digits == 6)

        let second = try #require(parsed.entries.last)
        #expect(second.displayName == "ops@dev")
        #expect(second.issuer == nil)
        #expect(second.parameters.algorithm == .sha256)
        #expect(second.parameters.digits == 8)
    }

    @Test("导出的二维码 PNG 可被 Vision 解回（端到端：生成 → 扫描 → 导入）")
    func generatedQRCodeIsScannable() throws {
        let entries = [
            OTPMigration.Entry(
                displayName: "demo@example.com",
                issuer: "Demo",
                secret: Data(repeating: 0x07, count: 20),
                parameters: OTPParameters.standard
            ),
        ]
        let uri = OTPMigration.migrationURI(entries: entries)
        let png = try QRCodeImage.pngData(for: uri, scale: 8)

        // PNG magic
        #expect(png.prefix(8) == Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]))

        // Vision 解回 → QRImport 判定
        let image = try #require(
            NSImage(data: png)?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        )
        let strings = try QRImageDecoder.decode(in: image)
        guard case .migrated(let accounts, _) = QRImport.resolve(strings) else {
            Issue.record("期望 .migrated，实际 \(QRImport.resolve(strings))")
            return
        }
        #expect(accounts.count == 1)
        #expect(accounts.first?.displayName == "demo@example.com")
        #expect(accounts.first?.issuer == "Demo")
    }

    // MARK: 真实二维码往返（Vision）

    @Test("Vision 往返：迁移码图片 → 解码 → resolve 出账户列表（RK2b 验证）")
    func visionRoundTrip() throws {
        let filter = try #require(CIFilter(name: "CIQRCodeGenerator"))
        let uri = migrationURI(parameters: [
            otpParameters(secret: Array(repeating: 7, count: 20), name: "Demo:demo@example.com", issuer: "Demo"),
        ])
        filter.setValue(Data(uri.utf8), forKey: "inputMessage")
        filter.setValue("L", forKey: "inputCorrectionLevel")   // 低纠错，减小码点密度
        let output = try #require(filter.outputImage)
            .transformed(by: CGAffineTransform(scaleX: 6, y: 6))
        let image = try #require(CIContext().createCGImage(output, from: output.extent))

        let strings = try QRImageDecoder.decode(in: image)
        guard case .migrated(let accounts, _) = QRImport.resolve(strings) else {
            Issue.record("期望 .migrated，实际 \(QRImport.resolve(strings))")
            return
        }
        #expect(accounts.count == 1)
        #expect(accounts.first?.displayName == "demo@example.com")
        #expect(accounts.first?.issuer == "Demo")
    }
}
