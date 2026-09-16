import CryptoKit
import Foundation

/// 加密文件存储（D9：替代 Keychain，用户决策 2026-09-16）
///
/// 决策背景：本机环境下 login 钥匙串条目的 ACL 不自动信任创建者，
/// 每条密钥首次读取都要一次系统授权弹窗（逐条弹、无法批量放行），
/// 用户体验不可接受 → 用户拍板弃用 Keychain，改用 App 自管的加密文件。
///
/// 存储布局：
///   - `master.key`   首次启动随机生成 32 字节主密钥（0600）
///   - `wallet.bin`   `magic(4) + version(1) + AES-GCM.combined`
///                    明文 = 全部账户的 `{id, secret, metadataJSON}` JSON
///
/// 安全边界（对 PRD S1 的显式降级，已获用户确认）：
///   - ✅ 磁盘上无明文密钥（AES-256-GCM，认证加密）
///   - ✅ 文件权限 0600 / 目录 0700，其他用户账户不可读
///   - ⚠️ 不抗「以同一用户身份运行的本地攻击者」——主密钥与本进程同权限可读。
///     Keychain 的 ACL 保护在此方案中不存在，这是弃用 Keychain 的固有代价。
///
/// 一致性：所有读写经内部串行队列；写用原子替换（临时文件 + rename）。
final class EncryptedStore: SecretStoring {

    enum StoreError: Error, Equatable {
        case malformedWallet
        case itemNotFound
    }

    private struct Wallet: Codable {
        struct Item: Codable {
            let id: UUID
            let secret: Data
            let metadataJSON: Data
        }
        var items: [Item]
    }

    private static let magic = Data("2WLT".utf8)
    private static let version: UInt8 = 1

    private let directory: URL
    private var masterKeyURL: URL { directory.appendingPathComponent("master.key") }
    private var walletURL: URL { directory.appendingPathComponent("wallet.bin") }

    private let queue = DispatchQueue(label: "com.kimi.2way.encryptedstore")

    /// - Parameter directory: 存储目录；默认 `~/Library/Application Support/2way`
    init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            self.directory = support.appendingPathComponent("2way", isDirectory: true)
        }
    }

    // MARK: - SecretStoring

    func save(id: UUID, secret: Data, metadataJSON: Data) throws {
        try queue.sync {
            var wallet = try readWallet()
            wallet.items.removeAll { $0.id == id }
            wallet.items.append(Wallet.Item(id: id, secret: secret, metadataJSON: metadataJSON))
            try writeWallet(wallet)
        }
    }

    func update(id: UUID, secret: Data, metadataJSON: Data) throws {
        try queue.sync {
            var wallet = try readWallet()
            guard let index = wallet.items.firstIndex(where: { $0.id == id }) else {
                throw StoreError.itemNotFound
            }
            wallet.items[index] = Wallet.Item(id: id, secret: secret, metadataJSON: metadataJSON)
            try writeWallet(wallet)
        }
    }

    func delete(id: UUID) throws {
        try queue.sync {
            var wallet = try readWallet()
            let before = wallet.items.count
            wallet.items.removeAll { $0.id == id }
            guard wallet.items.count != before else { throw StoreError.itemNotFound }
            try writeWallet(wallet)
        }
    }

    func read(id: UUID) throws -> KeychainStore.Entry {
        try queue.sync {
            let wallet = try readWallet()
            guard let item = wallet.items.first(where: { $0.id == id }) else {
                throw StoreError.itemNotFound
            }
            return KeychainStore.Entry(id: item.id, secret: item.secret, metadataJSON: item.metadataJSON)
        }
    }

    func readAllMetadata() throws -> [KeychainStore.MetadataEntry] {
        try queue.sync {
            try readWallet().items.map {
                KeychainStore.MetadataEntry(id: $0.id, metadataJSON: $0.metadataJSON)
            }
        }
    }

    // MARK: - 钱包编解码

    private func readWallet() throws -> Wallet {
        let key = try loadOrCreateMasterKey()

        guard FileManager.default.fileExists(atPath: walletURL.path) else {
            return Wallet(items: [])   // 首次启动：空钱包
        }

        let fileData = try Data(contentsOf: walletURL)
        guard fileData.prefix(Self.magic.count) == Self.magic else {
            throw StoreError.malformedWallet
        }
        guard let version = fileData.dropFirst(Self.magic.count).first else {
            throw StoreError.malformedWallet
        }
        guard version == Self.version else {
            throw StoreError.malformedWallet   // 未知版本：宁可不读，也不误解码
        }

        let combined = fileData.dropFirst(Self.magic.count + 1)
        do {
            let box = try AES.GCM.SealedBox(combined: Data(combined))
            let plain = try AES.GCM.open(box, using: key)
            return try JSONDecoder().decode(Wallet.self, from: plain)
        } catch {
            // 主密钥不匹配 / 密文损坏 / 被篡改（GCM 认证失败）
            throw StoreError.malformedWallet
        }
    }

    private func writeWallet(_ wallet: Wallet) throws {
        let key = try loadOrCreateMasterKey()
        let plain = try JSONEncoder().encode(wallet)
        let box = try AES.GCM.seal(plain, using: key)
        guard let combined = box.combined else {
            throw StoreError.malformedWallet
        }
        var fileData = Self.magic
        fileData.append(Self.version)
        fileData.append(combined)

        // 原子替换：临时文件（0600）→ rename（replaceItemAt 会沿用临时文件权限）
        let temporaryURL = directory.appendingPathComponent(".wallet.tmp")
        try fileData.write(to: temporaryURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporaryURL.path)
        _ = try replaceItem(at: temporaryURL, with: walletURL)
    }

    private func replaceItem(at source: URL, with target: URL) throws -> Bool {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: target.path) {
            _ = try fileManager.replaceItemAt(target, withItemAt: source)
        } else {
            try fileManager.moveItem(at: source, to: target)
        }
        return true
    }

    // MARK: - 主密钥（首次启动随机生成，0600）

    private func loadOrCreateMasterKey() throws -> SymmetricKey {
        let fileManager = FileManager.default
        try createDirectoryIfNeeded()

        if fileManager.fileExists(atPath: masterKeyURL.path) {
            let data = try Data(contentsOf: masterKeyURL)
            guard data.count == 32 else { throw StoreError.malformedWallet }
            return SymmetricKey(data: data)
        }

        let key = SymmetricKey(size: .bits256)
        let raw = key.withUnsafeBytes { Data($0) }
        try raw.write(to: masterKeyURL, options: [.atomic, .completeFileProtection])
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: masterKeyURL.path)
        return key
    }

    private func createDirectoryIfNeeded() throws {
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
    }
}
