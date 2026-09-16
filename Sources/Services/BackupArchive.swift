import CommonCrypto
import CryptoKit
import Foundation

/// 加密备份档案（C4-3 / PRD P1「导入导出/备份」）
///
/// 定位：既是跨设备迁移通道，也是 **D9 的逃生通道** —— `master.key` 丢失时，
/// 备份文件仍可用「用户自己设置的密码」解开（不依赖本机任何密钥文件）。
///
/// 文件格式（自描述、可演进）：
/// ```
/// magic  4B  "2WBA"
/// version 1B  当前 1
/// rounds 4B  PBKDF2 迭代次数（大端）
/// saltLen 1B 盐长度（当前 16）
/// salt   nB  随机盐
/// sealed  …  AES-GCM combined（nonce + 密文 + 认证标签）
/// ```
/// 明文载荷 = `Document` 的 JSON（含全部账户与密钥）。
///
/// 安全语义：
/// - 口令派生用 PBKDF2-HMAC-SHA256 + 随机盐 + 高迭代（抵抗离线爆破）
/// - 加密用 AES-256-GCM（认证加密：口令错误 / 文件被篡改都会明确失败，不会解出脏数据）
/// - 备份文件本身**不含** `master.key` 的任何信息，可安全存放在任意位置
enum BackupArchive {

    // MARK: - 数据模型

    struct Document: Codable, Equatable {
        var format: String
        var version: Int
        var exportedAt: Date
        var accounts: [Entry]

        init(exportedAt: Date = Date(), accounts: [Entry]) {
            self.format = BackupArchive.format
            self.version = BackupArchive.currentVersion
            self.exportedAt = exportedAt
            self.accounts = accounts
        }
    }

    /// 单个账户（含密钥；仅在内存与加密载荷中出现，S1/S2）
    struct Entry: Codable, Equatable {
        var id: UUID
        var displayName: String
        var issuer: String?
        var parameters: OTPParameters
        var addedAt: Date
        var secret: Data
    }

    enum ArchiveError: Error, Equatable {
        /// 不是本应用的备份文件
        case badMagic
        case unsupportedVersion(Int)
        /// 文件损坏或载荷被截断
        case malformed
        /// 口令错误，或文件被篡改（GCM 认证失败 —— 两者不可区分，属预期）
        case wrongPasswordOrCorrupted
        /// 口令过短（导出时拦截）
        case weakPassword(minimumLength: Int)
        /// 派生密钥失败（PBKDF2 内部错误）
        case keyDerivationFailed
    }

    // MARK: - 常量

    static let format = "2way-backup"
    static let currentVersion = 1
    static let magic = Data("2WBA".utf8)
    /// 口令最小长度（导出时强制；导入不校验，兼容历史文件）
    static let minimumPasswordLength = 8
    /// PBKDF2 迭代次数（OWASP 推荐的 SHA-256 量级）
    static let pbkdf2Rounds: UInt32 = 210_000
    static let saltLength = 16
    private static let keyLength = 32

    // MARK: - 导出

    static func encrypt(_ document: Document, password: String) throws -> Data {
        guard password.count >= minimumPasswordLength else {
            throw ArchiveError.weakPassword(minimumLength: minimumPasswordLength)
        }
        let salt = randomSalt()
        let key = try deriveKey(password: password, salt: salt, rounds: pbkdf2Rounds)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let plaintext = try encoder.encode(document)
        let sealed = try AES.GCM.seal(plaintext, using: key)
        guard let combined = sealed.combined else { throw ArchiveError.malformed }

        var data = magic
        data.append(UInt8(currentVersion))
        data.append(contentsOf: withUnsafeBytes(of: pbkdf2Rounds.bigEndian) { Array($0) })
        data.append(UInt8(salt.count))
        data.append(salt)
        data.append(combined)
        return data
    }

    // MARK: - 导入

    static func decrypt(_ data: Data, password: String) throws -> Document {
        guard data.prefix(magic.count) == magic else { throw ArchiveError.badMagic }

        var cursor = data.index(data.startIndex, offsetBy: magic.count)
        func readByte() throws -> UInt8 {
            guard cursor < data.endIndex else { throw ArchiveError.malformed }
            defer { cursor = data.index(after: cursor) }
            return data[cursor]
        }

        let version = Int(try readByte())
        guard version == currentVersion else { throw ArchiveError.unsupportedVersion(version) }

        let rounds = UInt32(try readByte()) << 24
            | UInt32(try readByte()) << 16
            | UInt32(try readByte()) << 8
            | UInt32(try readByte())

        let saltLength = Int(try readByte())
        guard saltLength > 0, saltLength <= 64 else { throw ArchiveError.malformed }
        guard data.distance(from: cursor, to: data.endIndex) > saltLength else {
            throw ArchiveError.malformed
        }
        let salt = Data(data[cursor..<data.index(cursor, offsetBy: saltLength)])
        cursor = data.index(cursor, offsetBy: saltLength)

        let key = try deriveKey(password: password, salt: salt, rounds: rounds)
        let combined = Data(data[cursor...])

        do {
            let box = try AES.GCM.SealedBox(combined: combined)
            let plaintext = try AES.GCM.open(box, using: key)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let document = try decoder.decode(Document.self, from: plaintext)
            guard document.format == format else { throw ArchiveError.malformed }
            return document
        } catch let error as ArchiveError {
            throw error
        } catch {
            // GCM 认证失败 / JSON 解不开：一律归为「口令错误或文件损坏」，不泄露细节
            throw ArchiveError.wrongPasswordOrCorrupted
        }
    }

    // MARK: - 口令派生（PBKDF2-HMAC-SHA256）

    static func deriveKey(password: String, salt: Data, rounds: UInt32) throws -> SymmetricKey {
        let passwordBytes = Array(password.utf8)
        var derived = [UInt8](repeating: 0, count: keyLength)

        let status = derived.withUnsafeMutableBufferPointer { derivedBuffer -> Int32 in
            salt.withUnsafeBytes { saltBuffer -> Int32 in
                passwordBytes.withUnsafeBufferPointer { passwordBuffer -> Int32 in
                    let rebound = passwordBuffer.baseAddress?.withMemoryRebound(
                        to: Int8.self,
                        capacity: max(passwordBuffer.count, 1)
                    ) { $0 }
                    return CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        rebound,
                        passwordBuffer.count,
                        saltBuffer.bindMemory(to: UInt8.self).baseAddress,
                        saltBuffer.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        rounds,
                        derivedBuffer.baseAddress,
                        derivedBuffer.count
                    )
                }
            }
        }
        guard status == kCCSuccess else { throw ArchiveError.keyDerivationFailed }
        return SymmetricKey(data: Data(derived))
    }

    private static func randomSalt() -> Data {
        var bytes = [UInt8](repeating: 0, count: saltLength)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        if status != errSecSuccess {
            // 兜底：系统随机不可用时用 CryptoKit 的 CSPRNG
            return Data((0..<saltLength).map { _ in UInt8.random(in: 0...255) })
        }
        return Data(bytes)
    }
}
