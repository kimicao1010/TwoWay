import Foundation
import CryptoKit

/// RFC 6238 TOTP 引擎
///
/// 纯函数、无状态。密钥以原始字节 `Data` 传入（调用方负责 Base32 解码），
/// 引擎内部不做任何字符串转换，避免密钥以 `String` 形态长期驻留堆上（S1/S2）。
enum TOTPEngine {

    /// 计算原始验证码：纯数字字符串，保留前导零
    static func rawCode(
        secret: Data,
        counter: UInt64,
        parameters: OTPParameters
    ) -> String {
        guard !secret.isEmpty else { return String(repeating: "0", count: parameters.digits) }

        // RFC 4226：8 字节大端计数器
        let counterBytes = withUnsafeBytes(of: counter.bigEndian) { Data($0) }
        let key = SymmetricKey(data: secret)

        let digest: Data
        switch parameters.algorithm {
        case .sha1:
            digest = Data(HMAC<Insecure.SHA1>.authenticationCode(for: counterBytes, using: key))
        case .sha256:
            digest = Data(HMAC<SHA256>.authenticationCode(for: counterBytes, using: key))
        case .sha512:
            digest = Data(HMAC<SHA512>.authenticationCode(for: counterBytes, using: key))
        }

        // RFC 4226 §5.3 动态截断
        let offset = Int(digest[digest.count - 1] & 0x0F)
        let truncated =
            (UInt32(digest[offset]) & 0x7F) << 24 |
            UInt32(digest[offset + 1]) << 16 |
            UInt32(digest[offset + 2]) << 8 |
            UInt32(digest[offset + 3])

        let code = UInt64(truncated) % parameters.modulus
        return String(format: "%0\(parameters.digits)d", code)
    }

    /// PRD T2 展示格式：`XXX XXX`（6 位时分两组；8 位时四四分组）
    static func displayCode(
        secret: Data,
        counter: UInt64,
        parameters: OTPParameters
    ) -> String {
        grouped(rawCode(secret: secret, counter: counter, parameters: parameters))
    }

    /// 复制进剪贴板的值（PRD T2：不含空格）
    static func code(
        secret: Data,
        counter: UInt64,
        parameters: OTPParameters
    ) -> String {
        rawCode(secret: secret, counter: counter, parameters: parameters)
    }

    /// `123456` → `123 456`；`12345678` → `1234 5678`
    static func grouped(_ raw: String) -> String {
        guard raw.count == 6 || raw.count == 8 else { return raw }
        let mid = raw.index(raw.startIndex, offsetBy: raw.count / 2)
        return "\(raw[..<mid]) \(raw[mid...])"
    }
}
