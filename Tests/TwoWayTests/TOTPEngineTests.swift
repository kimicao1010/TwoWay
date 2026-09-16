import Foundation
import Testing
@testable import TwoWay

/// C1-2：TOTP 引擎一致性（PRD T6 —— 与标准实现逐秒一致）
///
/// 全部断言值来自 RFC 6238 附录 B，并已用独立实现（Python `hmac`）逐条核对。
/// 三个算法的 secret 长度不同（RFC 规定）：
///   SHA1 → 20 字节，SHA256 → 32 字节，SHA512 → 64 字节
@Suite("TOTP 引擎（RFC 6238 标准向量）")
struct TOTPEngineTests {

    private static let sha1Secret = Data("12345678901234567890".utf8)
    private static let sha256Secret = Data("12345678901234567890123456789012".utf8)
    private static let sha512Secret = Data(
        "1234567890123456789012345678901234567890123456789012345678901234".utf8
    )

    /// (unix 秒, 8 位值, 6 位值)
    private static let sha1Vectors: [(TimeInterval, String, String)] = [
        (59, "94287082", "287082"),
        (1111111109, "07081804", "081804"),
        (1111111111, "14050471", "050471"),
        (1234567890, "89005924", "005924"),
        (2000000000, "69279037", "279037"),
        (20000000000, "65353130", "353130"),
    ]

    private static let sha256Vectors: [(TimeInterval, String, String)] = [
        (59, "46119246", "119246"),
        (1111111109, "68084774", "084774"),
        (1111111111, "67062674", "062674"),
        (1234567890, "91819424", "819424"),
        (2000000000, "90698825", "698825"),
        (20000000000, "77737706", "737706"),
    ]

    private static let sha512Vectors: [(TimeInterval, String, String)] = [
        (59, "90693936", "693936"),
        (1111111109, "25091201", "091201"),
        (1111111111, "99943326", "943326"),
        (1234567890, "93441116", "441116"),
        (2000000000, "38618901", "618901"),
        (20000000000, "47863826", "863826"),
    ]

    private func parameters(
        _ algorithm: OTPParameters.HashAlgorithm,
        digits: Int
    ) throws -> OTPParameters {
        try OTPParameters(algorithm: algorithm, digits: digits, period: 30)
    }

    // MARK: SHA-1

    @Test("SHA-1 · 8 位 · RFC 向量", arguments: Array(Self.sha1Vectors))
    func sha1Eight(point: (TimeInterval, String, String)) throws {
        let (unixTime, expected8, _) = point
        let counter = UInt64((unixTime / 30).rounded(.down))
        let code = TOTPEngine.rawCode(
            secret: Self.sha1Secret, counter: counter,
            parameters: try parameters(.sha1, digits: 8)
        )
        #expect(code == expected8, "T=\(unixTime)")
    }

    @Test("SHA-1 · 6 位 · RFC 向量（含前导零）", arguments: Array(Self.sha1Vectors))
    func sha1Six(point: (TimeInterval, String, String)) throws {
        let (unixTime, _, expected6) = point
        let counter = UInt64((unixTime / 30).rounded(.down))
        let code = TOTPEngine.rawCode(
            secret: Self.sha1Secret, counter: counter,
            parameters: try parameters(.sha1, digits: 6)
        )
        // 07081804 → 081804、89005924 → 005924：前导零必须保留
        #expect(code == expected6, "T=\(unixTime)")
        #expect(code.count == 6)
    }

    // MARK: SHA-256

    @Test("SHA-256 · 8 位 · RFC 向量", arguments: Array(Self.sha256Vectors))
    func sha256Eight(point: (TimeInterval, String, String)) throws {
        let (unixTime, expected8, _) = point
        let counter = UInt64((unixTime / 30).rounded(.down))
        let code = TOTPEngine.rawCode(
            secret: Self.sha256Secret, counter: counter,
            parameters: try parameters(.sha256, digits: 8)
        )
        #expect(code == expected8, "T=\(unixTime)")
    }

    @Test("SHA-256 · 6 位 · RFC 向量", arguments: Array(Self.sha256Vectors))
    func sha256Six(point: (TimeInterval, String, String)) throws {
        let (unixTime, _, expected6) = point
        let counter = UInt64((unixTime / 30).rounded(.down))
        let code = TOTPEngine.rawCode(
            secret: Self.sha256Secret, counter: counter,
            parameters: try parameters(.sha256, digits: 6)
        )
        #expect(code == expected6, "T=\(unixTime)")
    }

    // MARK: SHA-512

    @Test("SHA-512 · 8 位 · RFC 向量", arguments: Array(Self.sha512Vectors))
    func sha512Eight(point: (TimeInterval, String, String)) throws {
        let (unixTime, expected8, _) = point
        let counter = UInt64((unixTime / 30).rounded(.down))
        let code = TOTPEngine.rawCode(
            secret: Self.sha512Secret, counter: counter,
            parameters: try parameters(.sha512, digits: 8)
        )
        #expect(code == expected8, "T=\(unixTime)")
    }

    @Test("SHA-512 · 6 位 · RFC 向量", arguments: Array(Self.sha512Vectors))
    func sha512Six(point: (TimeInterval, String, String)) throws {
        let (unixTime, _, expected6) = point
        let counter = UInt64((unixTime / 30).rounded(.down))
        let code = TOTPEngine.rawCode(
            secret: Self.sha512Secret, counter: counter,
            parameters: try parameters(.sha512, digits: 6)
        )
        #expect(code == expected6, "T=\(unixTime)")
    }

    // MARK: 走 Base32 的全链路

    @Test("从 Base32 密钥到验证码的完整链路")
    func fullPipelineFromBase32() throws {
        // RFC 6238 secret 的 base32 形式
        let secret = try Base32.decode("GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ")
        let code = TOTPEngine.code(
            secret: secret, counter: UInt64(59 / 30),
            parameters: try parameters(.sha1, digits: 6)
        )
        #expect(code == "287082")
    }

    // MARK: T2 展示 / 复制格式

    @Test("T2：复制值不含空格，展示值三三分组")
    func copyAndDisplayFormats() throws {
        let raw = TOTPEngine.code(
            secret: Self.sha1Secret, counter: 1,
            parameters: try parameters(.sha1, digits: 6)
        )
        let display = TOTPEngine.displayCode(
            secret: Self.sha1Secret, counter: 1,
            parameters: try parameters(.sha1, digits: 6)
        )
        #expect(!raw.contains(" "))
        #expect(display.replacingOccurrences(of: " ", with: "") == raw)
        #expect(display.count == 7)   // 6 位 + 1 空格
        #expect(display == "\(raw.prefix(3)) \(raw.suffix(3))")
    }

    @Test("grouped：8 位四四分组，非常规长度原样返回")
    func groupedGrouping() {
        #expect(TOTPEngine.grouped("123456") == "123 456")
        #expect(TOTPEngine.grouped("12345678") == "1234 5678")
        #expect(TOTPEngine.grouped("123") == "123")
        #expect(TOTPEngine.grouped("") == "")
    }

    // MARK: 防御性

    @Test("空密钥不崩溃、长度正确")
    func emptySecretIsDefensive() throws {
        let code = TOTPEngine.rawCode(
            secret: Data(), counter: 0,
            parameters: try parameters(.sha1, digits: 6)
        )
        #expect(code == "000000")
    }

    @Test("相邻周期产生不同验证码（防常量回归）")
    func adjacentCountersDiffer() throws {
        let a = TOTPEngine.rawCode(secret: Self.sha1Secret, counter: 100, parameters: .standard)
        let b = TOTPEngine.rawCode(secret: Self.sha1Secret, counter: 101, parameters: .standard)
        let c = TOTPEngine.rawCode(secret: Self.sha1Secret, counter: 102, parameters: .standard)
        #expect(a != b || b != c)
    }

    @Test("同密钥同 counter 重复计算结果稳定（无随机性）")
    func deterministic() throws {
        let a = TOTPEngine.rawCode(secret: Self.sha1Secret, counter: 12345, parameters: .standard)
        let b = TOTPEngine.rawCode(secret: Self.sha1Secret, counter: 12345, parameters: .standard)
        #expect(a == b)
    }
}
