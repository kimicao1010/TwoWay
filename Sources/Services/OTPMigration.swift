import Foundation

/// Google Authenticator 导出格式 `otpauth-migration://offline?data=...` 解析（C2-6b）
///
/// GA 的「导出账户」二维码不是标准 `otpauth://`，而是一个 base64 的 protobuf
/// 载荷（多账户打包）。wire 格式是公开的（Google Authenticator 导出规范）：
///
/// ```
/// message MigrationPayload {
///   repeated OtpParameters otp_parameters = 1;
///   int32 version = 2; int32 batch_size = 3; int32 batch_index = 4; int32 batch_id = 5;
/// }
/// message OtpParameters {
///   bytes  secret    = 1;
///   string name      = 2;   // 通常是 "Issuer:account"
///   string issuer    = 3;
///   enum   algorithm = 4;   // 1=SHA1 2=SHA256 3=SHA512
///   enum   digits    = 5;   // 1=SIX 2=EIGHT
///   enum   type      = 6;   // 1=HOTP 2=TOTP
///   int64  counter   = 7;
/// }
/// ```
///
/// 手写最小 protobuf wire 解码（tag-varint / tag-length-value），不引入依赖。
/// HOTP（type=1）按 PRD「范围外」跳过，并让调用方知情。
enum OTPMigration {

    struct Entry: Equatable {
        var displayName: String
        var issuer: String?
        var secret: Data
        var parameters: OTPParameters
    }

    enum MigrationError: Error, Equatable {
        /// 不是 otpauth-migration scheme
        case invalidScheme
        /// 缺 data 参数或 base64 解码失败
        case malformedPayload
        /// 载荷里没有任何 TOTP 账户（全部是 HOTP 或为空）
        case noTOTPEntries
    }

    struct Result: Equatable {
        var entries: [Entry]
        /// 被跳过的 HOTP 条数（PRD 范围外，不静默）
        var skippedHOTPCount: Int
    }

    /// 解析 `otpauth-migration://offline?data=...`
    static func parse(_ raw: String) throws -> Result {
        guard
            let components = URLComponents(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
            components.scheme?.lowercased() == "otpauth-migration"
        else { throw MigrationError.invalidScheme }

        guard
            let dataValue = components.queryItems?
                .first(where: { $0.name.lowercased() == "data" })?.value,
            let payload = base64Data(dataValue)
        else { throw MigrationError.malformedPayload }

        var entries: [Entry] = []
        var skipped = 0

        var reader = ProtoReader(payload)
        while let field = reader.next() {
            if field.number == 1, field.wireType == 2, let bytes = reader.lengthDelimited() {
                if let entry = parseOtpParameters(bytes) {
                    entries.append(entry)
                } else {
                    skipped += 1
                }
            } else {
                reader.skip(field)
            }
        }

        guard !entries.isEmpty else { throw MigrationError.noTOTPEntries }
        return Result(entries: entries, skippedHOTPCount: skipped)
    }

    // MARK: - OtpParameters（嵌套消息）

    private static func parseOtpParameters(_ bytes: Data) -> Entry? {
        var secret: Data?
        var name: String?
        var issuer: String?
        var algorithmRaw: Int?
        var digitsRaw: Int?
        var typeRaw: Int?

        var reader = ProtoReader(bytes)
        while let field = reader.next() {
            switch (field.number, field.wireType) {
            case (1, 2): secret = reader.lengthDelimited()
            case (2, 2): name = reader.lengthDelimited().flatMap { String(data: $0, encoding: .utf8) }
            case (3, 2): issuer = reader.lengthDelimited().flatMap { String(data: $0, encoding: .utf8) }
            case (4, 0): algorithmRaw = Int(reader.varint())
            case (5, 0): digitsRaw = Int(reader.varint())
            case (6, 0): typeRaw = Int(reader.varint())
            default: reader.skip(field)
            }
        }

        // type：1=HOTP（PRD 范围外，跳过）；2=TOTP；缺省按 TOTP 处理
        guard typeRaw ?? 2 == 2 else { return nil }
        guard let secret, !secret.isEmpty else { return nil }

        // name 通常是 "Issuer:account"；无前缀时整个就是账户名
        let label = name ?? ""
        let displayName: String
        var issuerFromLabel: String?
        if let colon = label.firstIndex(of: ":") {
            issuerFromLabel = String(label[..<colon]).trimmingCharacters(in: .whitespaces)
            displayName = String(label[label.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
        } else {
            displayName = label.trimmingCharacters(in: .whitespaces)
        }
        if issuerFromLabel?.isEmpty == true { issuerFromLabel = nil }
        let resolvedIssuer = issuer?.isEmpty == false ? issuer : issuerFromLabel

        let algorithm: OTPParameters.HashAlgorithm
        switch algorithmRaw {
        case 2: algorithm = .sha256
        case 3: algorithm = .sha512
        default: algorithm = .sha1   // 1 与 0/缺省均为 SHA1
        }

        let digits = digitsRaw == 2 ? 8 : 6   // 1=SIX；0/缺省按 6

        guard !displayName.isEmpty else { return nil }
        guard let parameters = try? OTPParameters(algorithm: algorithm, digits: digits, period: 30) else {
            return nil
        }
        return Entry(
            displayName: displayName,
            issuer: resolvedIssuer,
            secret: secret,
            parameters: parameters
        )
    }

    // MARK: - 编码（导出给 Google Authenticator 扫描导入）

    /// 把账户编码为 GA 可导入的迁移码 URI。
    ///
    /// ⚠️ 迁移码载荷是**明文**（只做 base64），即二维码图片本身等价于密钥明文 ——
    /// 调用方必须向用户明示这一点，并提示用完即删。
    static func migrationURI(entries: [Entry]) -> String {
        var payload: [UInt8] = []
        for entry in entries {
            var parameters: [UInt8] = []
            parameters += protoBytes(field: 1, value: entry.secret)

            // GA 约定 label = "Issuer:account"；无发行方时只有 account
            let label: String
            if let issuer = entry.issuer, !issuer.isEmpty {
                label = "\(issuer):\(entry.displayName)"
            } else {
                label = entry.displayName
            }
            parameters += protoBytes(field: 2, value: Data(label.utf8))

            if let issuer = entry.issuer, !issuer.isEmpty {
                parameters += protoBytes(field: 3, value: Data(issuer.utf8))
            }
            parameters += protoVarint(field: 4, value: algorithmCode(for: entry.parameters.algorithm))
            parameters += protoVarint(field: 5, value: entry.parameters.digits == 8 ? 2 : 1)
            parameters += protoVarint(field: 6, value: 2)   // 2 = TOTP

            payload += protoBytes(field: 1, value: Data(parameters))
        }
        payload += protoVarint(field: 2, value: 1)   // version = 1

        let encoded = Data(payload).base64EncodedString()
            .replacingOccurrences(of: "+", with: "%2B")
            .replacingOccurrences(of: "/", with: "%2F")
            .replacingOccurrences(of: "=", with: "%3D")
        return "otpauth-migration://offline?data=\(encoded)"
    }

    private static func algorithmCode(for algorithm: OTPParameters.HashAlgorithm) -> Int {
        switch algorithm {
        case .sha1: 1
        case .sha256: 2
        case .sha512: 3
        }
    }

    private static func protoVarint(field: Int, value: Int) -> [UInt8] {
        var bytes = protoVarintBytes((field << 3) | 0)
        bytes += protoVarintBytes(value)
        return bytes
    }

    private static func protoBytes(field: Int, value: Data) -> [UInt8] {
        var bytes = protoVarintBytes((field << 3) | 2)
        bytes += protoVarintBytes(value.count)
        bytes += [UInt8](value)
        return bytes
    }

    private static func protoVarintBytes(_ value: Int) -> [UInt8] {
        var remaining = UInt64(value)
        var bytes: [UInt8] = []
        repeat {
            var byte = UInt8(remaining & 0b0111_1111)
            remaining >>= 7
            if remaining > 0 { byte |= 0b1000_0000 }
            bytes.append(byte)
        } while remaining > 0
        return bytes
    }

    // MARK: - base64（容忍缺失 padding）

    private static func base64Data(_ string: String) -> Data? {
        var base64 = string.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder > 0 {
            base64.append(String(repeating: "=", count: 4 - remainder))
        }
        return Data(base64Encoded: base64)
    }
}

// MARK: - 最小 protobuf wire 读取器

/// 只覆盖本项目需要的部分：varint（wire 0）与 length-delimited（wire 2），
/// 其余 wire 类型按已知长度跳过。
private struct ProtoReader {
    private let data: Data
    private var offset: Data.Index

    init(_ data: Data) {
        self.data = data
        self.offset = data.startIndex
    }

    struct Field {
        let number: Int
        let wireType: Int
    }

    /// 读下一个字段头；数据耗尽返回 nil
    mutating func next() -> Field? {
        guard offset < data.endIndex else { return nil }
        let tag = varint()
        return Field(number: Int(tag >> 3), wireType: Int(tag & 0b111))
    }

    mutating func varint() -> UInt64 {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        while offset < data.endIndex {
            let byte = data[offset]
            offset = data.index(after: offset)
            result |= UInt64(byte & 0b0111_1111) << shift
            if byte & 0b1000_0000 == 0 { break }
            shift += 7
        }
        return result
    }

    mutating func lengthDelimited() -> Data? {
        let length = Int(varint())
        guard length >= 0, offset < data.endIndex || length == 0 else { return nil }
        guard let end = data.index(offset, offsetBy: length, limitedBy: data.endIndex) else {
            return nil
        }
        let slice = data[offset..<end]
        offset = end
        return Data(slice)
    }

    /// 跳过已知长度的字段；无法确定长度（未支持的 wire 类型）时停止读取
    mutating func skip(_ field: ProtoReader.Field) {
        switch field.wireType {
        case 0: _ = varint()
        case 1: offset = data.index(offset, offsetBy: 8, limitedBy: data.endIndex) ?? data.endIndex
        case 2: _ = lengthDelimited()
        case 5: offset = data.index(offset, offsetBy: 4, limitedBy: data.endIndex) ?? data.endIndex
        default: offset = data.endIndex   // 未知 wire 类型，放弃剩余数据
        }
    }
}
