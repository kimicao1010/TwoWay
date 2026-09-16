import Foundation

/// `otpauth://` URI 解析（C1-3）
///
/// 规格：https://github.com/google/google-authenticator/wiki/Key-Uri-Format
/// 承担 PRD E10（非 otpauth 二维码）与「范围外 HOTP」的拦截。
enum OTPAuthURI {

    enum ParseError: Error, Equatable {
        /// 字符串不是合法 URL
        case malformed
        /// 不是 otpauth scheme（PRD E10：明确提示，不静默失败）
        case invalidScheme(String)
        /// otpauth://hotp 等（PRD 范围外：HOTP）
        case unsupportedType(String)
        /// 缺 secret
        case missingSecret
        /// secret 解码失败（E4）
        case invalidSecret(Base32.DecodingError)
        /// label 为空
        case emptyLabel
        /// 参数取值非法
        case invalidParameter(String)
    }

    struct ParsedAccount: Equatable {
        /// label 中冒号前的发行方；label 无前缀时回落到 query 的 issuer
        var issuer: String?
        /// label 中冒号后的账户标识；无前缀时为整个 label
        var accountLabel: String
        var secret: Data
        var parameters: OTPParameters
    }

    static func parse(_ raw: String) throws -> ParsedAccount {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmed) else {
            throw ParseError.malformed
        }
        // 连 scheme 都没有说明根本不是 URI（"random text"、空串）→ malformed；
        // 有 scheme 但不对 → invalidScheme（E10：明确提示，不静默失败）
        guard let scheme = components.scheme, !scheme.isEmpty else {
            throw ParseError.malformed
        }
        guard scheme.lowercased() == "otpauth" else {
            throw ParseError.invalidScheme(scheme)
        }
        // otpauth 的类型在 host 位置：otpauth://totp/Label?...
        let type = (components.host ?? "").lowercased()
        guard type == "totp" else { throw ParseError.unsupportedType(components.host ?? "") }

        let label = parseLabel(from: components.path)
        guard !label.accountLabel.isEmpty else { throw ParseError.emptyLabel }

        let items = components.queryItems ?? []
        func value(_ name: String) -> String? {
            items.first { $0.name.lowercased() == name }?.value
        }

        guard let rawSecret = value("secret"), !rawSecret.isEmpty else {
            throw ParseError.missingSecret
        }
        let secret: Data
        do {
            secret = try Base32.decode(rawSecret)
        } catch let error as Base32.DecodingError {
            throw ParseError.invalidSecret(error)
        }

        let parameters = try parameters(from: value, original: .standard)

        return ParsedAccount(
            issuer: label.issuer ?? value("issuer"),
            accountLabel: label.accountLabel,
            secret: secret,
            parameters: parameters
        )
    }

    // MARK: - label

    /// `otpauth://totp/Issuer:account` → (Issuer, account)；无冒号 → (nil, account)
    ///
    /// 规格约定 label 里若带发行方前缀，必须是「Issuer:account」；
    /// account 本身允许含冒号，因此**只按第一个冒号切分**。
    private static func parseLabel(from path: String) -> (issuer: String?, accountLabel: String) {
        let decoded = path
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .removingPercentEncoding ?? path
        guard !decoded.isEmpty else { return (nil, "") }

        if let colon = decoded.firstIndex(of: ":") {
            let issuer = String(decoded[..<colon]).trimmingCharacters(in: .whitespaces)
            let account = String(decoded[decoded.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            return (issuer.isEmpty ? nil : issuer, account)
        }
        return (nil, decoded)
    }

    // MARK: - 参数

    private static func parameters(
        from lookup: (String) -> String?,
        original fallback: OTPParameters
    ) throws -> OTPParameters {
        var algorithm = fallback.algorithm
        var digits = fallback.digits
        var period = fallback.period

        if let raw = lookup("algorithm") {
            let normalized = raw
                .replacingOccurrences(of: "-", with: "")
                .uppercased()
            guard let parsed = OTPParameters.HashAlgorithm(rawValue: normalized) else {
                throw ParseError.invalidParameter("algorithm: \(raw)")
            }
            algorithm = parsed
        }

        if let raw = lookup("digits") {
            guard let parsed = Int(raw), parsed == 6 || parsed == 8 else {
                throw ParseError.invalidParameter("digits: \(raw)")
            }
            digits = parsed
        }

        if let raw = lookup("period") {
            guard let parsed = TimeInterval(raw), parsed > 0 else {
                throw ParseError.invalidParameter("period: \(raw)")
            }
            period = parsed
        }

        return try OTPParameters(algorithm: algorithm, digits: digits, period: period)
    }
}
