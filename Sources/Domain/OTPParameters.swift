import Foundation

/// TOTP 参数 —— PRD §7.7 T1、§7.4 高级选项
///
/// 值类型，不含任何 UI / 平台依赖，可被单测完整覆盖。
struct OTPParameters: Hashable, Sendable, Codable {

    enum HashAlgorithm: String, CaseIterable, Sendable, Codable {
        case sha1 = "SHA1"
        case sha256 = "SHA256"
        case sha512 = "SHA512"
    }

    enum ValidationError: Error, Equatable {
        case invalidDigits(Int)
        case invalidPeriod(TimeInterval)
    }

    let algorithm: HashAlgorithm
    /// 6 或 8 位（PRD §7.4 高级选项）
    let digits: Int
    /// 刷新周期，秒。默认 30（T1）
    let period: TimeInterval

    /// PRD T1 默认值：SHA-1 / 6 位 / 30 秒
    static let standard = try! OTPParameters()

    init(
        algorithm: HashAlgorithm = .sha1,
        digits: Int = 6,
        period: TimeInterval = 30
    ) throws {
        guard digits == 6 || digits == 8 else {
            throw ValidationError.invalidDigits(digits)
        }
        guard period > 0, period.isFinite else {
            throw ValidationError.invalidPeriod(period)
        }
        self.algorithm = algorithm
        self.digits = digits
        self.period = period
    }

    /// 复制时使用的取模值（HOTP 截断值为 31 位，直接取模避免浮点）
    var modulus: UInt64 { digits == 6 ? 1_000_000 : 100_000_000 }
}
