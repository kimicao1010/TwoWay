import CoreGraphics
import CoreImage
import Foundation
import Testing
@testable import TwoWay

/// C2-6：二维码图片导入 —— Vision 解码往返 + E9/E10/E11 异常路径 + 预填
@MainActor
@Suite("QRImport（图片导入）")
struct QRImportTests {

    // MARK: 测试素材：用 CoreImage 的 CIQRCodeGenerator 生成真实二维码

    private func makeQR(_ string: String) throws -> CGImage {
        let filter = try #require(CIFilter(name: "CIQRCodeGenerator"))
        filter.setValue(Data(string.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        let output = try #require(filter.outputImage)
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 4, y: 4))
        let context = CIContext()
        return try #require(context.createCGImage(scaled, from: scaled.extent))
    }

    /// 把多张二维码合成到一张图上（E11 场景）
    private func composite(_ images: [(image: CGImage, rect: CGRect)], size: CGSize) throws -> CGImage {
        let width = Int(size.width), height = Int(size.height)
        let context = try #require(
            CGContext(
                data: nil, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            )
        )
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(origin: .zero, size: size))
        for item in images {
            context.draw(item.image, in: item.rect)
        }
        return try #require(context.makeImage())
    }

    private let otpauthURI =
        "otpauth://totp/GitHub:kimi%40example.com?secret=JBSWY3DPEHPK3PXP&issuer=GitHub&algorithm=SHA1&digits=6&period=30"

    // MARK: Vision 解码往返

    @Test("真实二维码图片 → Vision 解码还原内容（RK2b 唯一路径的往返验证）")
    func decodeRoundTrip() throws {
        let image = try makeQR(otpauthURI)
        let strings = try QRImageDecoder.decode(in: image)
        #expect(strings == [otpauthURI])
    }

    @Test("E9：无二维码的图片 → 返回空数组")
    func decodeNoQR() throws {
        // 纯色 100×100 白图
        let context = try #require(
            CGContext(
                data: nil, width: 100, height: 100,
                bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            )
        )
        context.setFillColor(CGColor(gray: 0.5, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
        let image = try #require(context.makeImage())

        #expect(try QRImageDecoder.decode(in: image).isEmpty)
    }

    @Test("E11：一图双码 → 按面积降序返回（大码在前）")
    func decodeMultipleSortedByArea() throws {
        let big = try makeQR(otpauthURI)
        let small = try makeQR("https://example.com/small")

        let composite = try composite(
            [
                (big, CGRect(x: 205, y: 5, width: 190, height: 190)),
                (small, CGRect(x: 5, y: 55, width: 90, height: 90)),
            ],
            size: CGSize(width: 400, height: 200)
        )

        let strings = try QRImageDecoder.decode(in: composite)
        #expect(strings.count == 2)
        #expect(strings.first == otpauthURI)   // 面积最大的先返回
    }

    // MARK: 内容判定

    @Test("otpauth URI → 解析出预填字段（含发行方与参数）")
    func resolveAccount() throws {
        let outcome = QRImport.resolve([otpauthURI])
        guard case .account(let fields) = outcome else {
            Issue.record("期望 .account，实际 \(outcome)")
            return
        }
        #expect(fields.displayName == "you@example.com")
        #expect(fields.issuer == "GitHub")
        #expect(fields.secretBase32 == "JBSWY3DPEHPK3PXP")
        #expect(fields.parameters.algorithm == .sha1)
        #expect(fields.parameters.digits == 6)
        #expect(fields.parameters.period == 30)
    }

    @Test("E10：非 otpauth 二维码（普通网址）→ notOTPAuth")
    func resolveNotOTPAuth() {
        let outcome = QRImport.resolve(["https://example.com/login"])
        #expect(outcome == .notOTPAuth)
    }

    @Test("otpauth 但内容无效（HOTP / 缺密钥）→ invalidOTPAuth")
    func resolveInvalidOTPAuth() {
        #expect(
            QRImport.resolve(["otpauth://hotp/GitHub:kimi?counter=1&secret=JBSWY3DPEHPK3PXP"])
                == .invalidOTPAuth
        )
        #expect(QRImport.resolve(["otpauth://totp/kimi"]) == .invalidOTPAuth)
    }

    @Test("E9：空解码结果 → noQRCode")
    func resolveEmpty() {
        #expect(QRImport.resolve([]) == .noQRCode)
    }

    // MARK: 预填

    @Test("prefill 填充名称/发行方/密钥/高级参数（PRD：预填后交由用户确认）")
    func prefill() {
        let model = ManualEntryModel()
        model.displayName = "旧名字"
        model.secretRaw = "OLDSECRET"

        model.prefill(
            from: QRImport.PrefilledAccount(
                displayName: "AWS:prod",
                issuer: "Amazon Web Services",
                secretBase32: "JBSWY3DPEHPK3PXP",
                parameters: (try? OTPParameters(algorithm: .sha256, digits: 8, period: 60))!
            )
        )

        #expect(model.displayName == "AWS:prod")
        #expect(model.issuer == "Amazon Web Services")
        #expect(model.secretRaw == "JBSWY3DPEHPK3PXP")
        #expect(model.algorithm == .sha256)
        #expect(model.digits == 8)
        #expect(model.period == 60)
        #expect(model.secretError == nil)
    }
}
