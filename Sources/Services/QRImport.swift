import Foundation

/// 二维码内容 → 导入结果的判定（C2-6，PRD §7.4 / §9 E9–E11）
///
/// 纯逻辑、可单测；图片解码在 `QRImageDecoder`（Vision）。
enum QRImport {

    /// 解码成功后交给手动输入页预填的字段（PRD：预填账户名 / 发行方 / 密钥 / 高级参数）
    struct PrefilledAccount: Equatable {
        var displayName: String
        var issuer: String?
        var secretBase32: String
        var parameters: OTPParameters
    }

    enum Outcome: Equatable {
        /// E9：图中没有可识别的二维码
        case noQRCode
        /// 解码成功（含全部预填字段）
        case account(PrefilledAccount)
        /// GA 导出迁移码：多个账户（批量直接导入）
        case migrated([PrefilledAccount], skippedHOTPCount: Int)
        /// 迁移码里没有可导入的 TOTP 账户（全部 HOTP 或为空）
        case migrationWithoutTOTP
        /// E10：二维码有效但不是 otpauth（如普通网址）
        case notOTPAuth
        /// 二维码是 otpauth 但内容无效 / 不受支持（缺密钥、HOTP、非法参数）
        case invalidOTPAuth
    }

    /// 对解码出的字符串（已按面积降序）逐个尝试解析，**取第一个可解析的**（E11）。
    static func resolve(_ decodedStrings: [String]) -> Outcome {
        guard !decodedStrings.isEmpty else { return .noQRCode }

        var sawOTPAuth = false
        for string in decodedStrings {
            let lowered = string.lowercased()

            // GA 导出迁移码：一个码打包多个账户
            if lowered.hasPrefix("otpauth-migration://") {
                if let result = try? OTPMigration.parse(string) {
                    return .migrated(
                        result.entries.map {
                            PrefilledAccount(
                                displayName: $0.displayName,
                                issuer: $0.issuer,
                                secretBase32: Base32.encode($0.secret),
                                parameters: $0.parameters
                            )
                        },
                        skippedHOTPCount: result.skippedHOTPCount
                    )
                }
                return .migrationWithoutTOTP
            }

            guard let parsed = try? OTPAuthURI.parse(string) else {
                if lowered.hasPrefix("otpauth://") {
                    sawOTPAuth = true
                }
                continue
            }
            return .account(
                PrefilledAccount(
                    displayName: parsed.accountLabel,
                    issuer: parsed.issuer,
                    // 密钥以规范化的 Base32 回填（大写、无 padding、无空白）
                    secretBase32: Base32.encode(parsed.secret),
                    parameters: parsed.parameters
                )
            )
        }
        return sawOTPAuth ? .invalidOTPAuth : .notOTPAuth
    }
}
