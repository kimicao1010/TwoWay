import Foundation
import Security

/// 密钥唯一出入口（TECH_PLAN §4.2，D3 方案 A）
///
/// 存储布局：
///   - `kSecClass`            = `kSecClassGenericPassword`
///   - `kSecAttrService`      = 固定 service（分组）
///   - `kSecAttrAccount`      = 账户 UUID（**不是**名称 —— 允许重名账户）
///   - `kSecValueData`        = **已解码**的密钥原始字节（落库前即 Base32 解码，磁盘上无明文 Base32）
///   - `kSecAttrGeneric`      = 元数据 JSON（名称 / 发行方 / 参数 / 添加时间）
///
/// API 硬约束（SDK `SecItem.h` + 本机实测，见 §4.2）：
///   1. `kSecUseKeychain` 只对 **SecItemAdd** 生效 —— 指定写入哪把钥匙串
///   2. `kSecMatchSearchList` 是 match 键，只对查询类调用生效（CopyMatching/Update/Delete）
///   3. **`kSecMatchLimitAll` + `kSecReturnData` 会被拒（errSecParam -50）**：
///      系统不允许一次性批量倒出所有密码数据。
///      因此「列出全部」只取属性（含元数据），密钥必须按 id 逐条取。
///      这反过来是更好的安全形态：列表渲染不碰密钥，取码时才逐条解锁。
///
/// S1/S2/S3 约束：
///   - 密钥全程 `Data`，不转 `String`，不进日志；本类型不实现 `CustomStringConvertible`
///   - 不走 UserDefaults / plist / 命令行参数 / 环境变量
///   - 可访问性交由系统默认 ACL（「创建者应用」），这正是 §9 依赖的 DR 绑定机制
final class KeychainStore {

    enum StoreError: Error, Equatable {
        case unhandledStatus(OSStatus)
        case itemNotFound
        case payloadCorrupted
    }

    /// 列表用：只有元数据，**不含密钥**
    struct MetadataEntry: Equatable {
        let id: UUID
        let metadataJSON: Data
    }

    /// 单条读取：含密钥
    struct Entry: Equatable {
        let id: UUID
        let secret: Data
        let metadataJSON: Data
    }

    private let service: String
    /// `nil` = 用户默认钥匙串（生产路径）；非 nil = 注入的钥匙串（测试路径）
    private let keychain: SecKeychain?

    /// - Parameters:
    ///   - service: 分组标识，生产环境传 Bundle ID
    ///   - keychain: 传 `nil` 使用用户默认钥匙串。测试注入 `SecKeychainCreate` 出来的临时钥匙串，
    ///     单测因此能跑真实 Security 栈而不碰登录钥匙串。
    init(service: String, keychain: SecKeychain? = nil) {
        self.service = service
        self.keychain = keychain
    }

    // MARK: - 查询构造

    private var classAndService: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
    }

    /// 查询类调用的字典（Update/Delete/CopyMatching 均走这里）
    private func query(
        account: UUID? = nil,
        limitAll: Bool = false,
        extra: [String: Any] = [:]
    ) -> [String: Any] {
        var dictionary = classAndService
        if let account { dictionary[kSecAttrAccount as String] = account.uuidString }
        if let keychain { dictionary[kSecMatchSearchList as String] = [keychain] }
        if limitAll { dictionary[kSecMatchLimit as String] = kSecMatchLimitAll }
        dictionary.merge(extra) { _, new in new }
        return dictionary
    }

    /// SecItemAdd 专用（kSecUseKeychain 只允许出现在这里）
    private func addAttributes(
        id: UUID,
        secret: Data,
        metadataJSON: Data
    ) -> [String: Any] {
        var attributes = classAndService
        attributes[kSecAttrAccount as String] = id.uuidString
        attributes[kSecValueData as String] = secret
        attributes[kSecAttrGeneric as String] = metadataJSON
        if let keychain { attributes[kSecUseKeychain as String] = keychain }
        return attributes
    }

    // MARK: - 写

    /// 写入（幂等：先删后写，上层语义为 save）
    func save(id: UUID, secret: Data, metadataJSON: Data) throws {
        SecItemDelete(query(account: id) as CFDictionary)

        let status = SecItemAdd(
            addAttributes(id: id, secret: secret, metadataJSON: metadataJSON) as CFDictionary,
            nil
        )
        guard status == errSecSuccess else { throw StoreError.unhandledStatus(status) }
    }

    func update(id: UUID, secret: Data, metadataJSON: Data) throws {
        let status = SecItemUpdate(
            query(account: id) as CFDictionary,
            [
                kSecValueData as String: secret,
                kSecAttrGeneric as String: metadataJSON,
            ] as CFDictionary
        )
        if status == errSecItemNotFound { throw StoreError.itemNotFound }
        guard status == errSecSuccess else { throw StoreError.unhandledStatus(status) }
    }

    /// 删除；条目不存在不算错（幂等）
    func delete(id: UUID) throws {
        let status = SecItemDelete(query(account: id) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw StoreError.unhandledStatus(status)
        }
    }

    // MARK: - 读

    /// 列出全部账户的元数据 —— **不含密钥**（见类注释第 3 条）
    ///
    /// 这是启动路径：一次拿到整个列表用于渲染，密钥留给取码时逐条取。
    func readAllMetadata() throws -> [MetadataEntry] {
        let dictionary = query(
            limitAll: true,
            extra: [kSecReturnAttributes as String: true]
        )
        var items: CFTypeRef?
        let status = SecItemCopyMatching(dictionary as CFDictionary, &items)
        if status == errSecItemNotFound { return [] }
        guard status == errSecSuccess, let list = items as? [[String: Any]] else {
            throw StoreError.unhandledStatus(status)
        }
        return try list.map { dict in
            guard
                let idString = dict[kSecAttrAccount as String] as? String,
                let id = UUID(uuidString: idString),
                let metadataJSON = dict[kSecAttrGeneric as String] as? Data
            else { throw StoreError.payloadCorrupted }
            return MetadataEntry(id: id, metadataJSON: metadataJSON)
        }
    }

    /// 读取单条（含密钥）。取码前调用。
    func read(id: UUID) throws -> Entry {
        let dictionary = query(
            account: id,
            extra: [
                kSecReturnData as String: true,
                kSecReturnAttributes as String: true,
            ]
        )
        var item: CFTypeRef?
        let status = SecItemCopyMatching(dictionary as CFDictionary, &item)
        guard status == errSecSuccess, let dict = item as? [String: Any] else {
            if status == errSecItemNotFound { throw StoreError.itemNotFound }
            throw StoreError.unhandledStatus(status)
        }
        guard
            let secret = dict[kSecValueData as String] as? Data,
            let metadataJSON = dict[kSecAttrGeneric as String] as? Data
        else { throw StoreError.payloadCorrupted }
        return Entry(id: id, secret: secret, metadataJSON: metadataJSON)
    }
}
