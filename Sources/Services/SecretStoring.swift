import Foundation

/// 密钥存储的抽象。
///
/// 注意：协议**不带 Sendable** —— KeychainStore 持有非 Sendable 的 SecKeychain，
/// 强加 Sendable 会连坐报错。AccountStore 是 @MainActor 隔离的，不需要跨线程传递实现。
///
/// 抽出来的目的：`AccountStore` 的业务逻辑（加载 / 增删 / 过滤 / 取码）可以
/// 用内存实现做单元测试，不必每次都开真实钥匙串（C2-1）。
/// 真实实现 `KeychainStore` 的行为另有专门的临时钥匙串集成测试覆盖（C1-1）。
protocol SecretStoring {
    func save(id: UUID, secret: Data, metadataJSON: Data) throws
    func read(id: UUID) throws -> KeychainStore.Entry
    func readAllMetadata() throws -> [KeychainStore.MetadataEntry]
    func update(id: UUID, secret: Data, metadataJSON: Data) throws
    func delete(id: UUID) throws
}

extension KeychainStore: SecretStoring {}

/// 内存实现：单测与 SwiftUI 预览用
final class InMemorySecretStore: SecretStoring {
    private struct Record {
        let secret: Data
        let metadataJSON: Data
    }

    private var records: [UUID: Record] = [:]
    private let lock = NSLock()

    func save(id: UUID, secret: Data, metadataJSON: Data) throws {
        lock.lock(); defer { lock.unlock() }
        records[id] = Record(secret: secret, metadataJSON: metadataJSON)
    }

    func read(id: UUID) throws -> KeychainStore.Entry {
        lock.lock(); defer { lock.unlock() }
        guard let record = records[id] else { throw KeychainStore.StoreError.itemNotFound }
        return KeychainStore.Entry(id: id, secret: record.secret, metadataJSON: record.metadataJSON)
    }

    func readAllMetadata() throws -> [KeychainStore.MetadataEntry] {
        lock.lock(); defer { lock.unlock() }
        return records.map { KeychainStore.MetadataEntry(id: $0.key, metadataJSON: $0.value.metadataJSON) }
    }

    func update(id: UUID, secret: Data, metadataJSON: Data) throws {
        lock.lock(); defer { lock.unlock() }
        guard records[id] != nil else { throw KeychainStore.StoreError.itemNotFound }
        records[id] = Record(secret: secret, metadataJSON: metadataJSON)
    }

    func delete(id: UUID) throws {
        lock.lock(); defer { lock.unlock() }
        records.removeValue(forKey: id)
    }
}
