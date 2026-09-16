import Foundation
import Testing
@testable import TwoWay

/// D9：加密文件存储 —— 读写往返 / 持久化（跨实例）/ 删除语义 / 损坏检测 / 权限
@Suite("EncryptedStore（加密文件存储）")
struct EncryptedStoreTests {

    private func makeStore() throws -> (EncryptedStore, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("2way-test-\(UUID().uuidString)", isDirectory: true)
        let store = EncryptedStore(directory: directory)
        return (store, directory)
    }

    private let secret = Data([0x01, 0x02, 0x03, 0x04, 0x05])
    private let metadata = Data("{\"displayName\":\"GitHub\"}".utf8)

    @Test("save / read / readAllMetadata 往返")
    func roundTrip() throws {
        let (store, _) = try makeStore()
        let id = UUID()

        try store.save(id: id, secret: secret, metadataJSON: metadata)

        let entry = try store.read(id: id)
        #expect(entry.secret == secret)
        #expect(entry.metadataJSON == metadata)

        let all = try store.readAllMetadata()
        #expect(all.count == 1)
        #expect(all.first?.id == id)
        #expect(all.first?.metadataJSON == metadata)
    }

    @Test("跨实例持久化（模拟 App 重启）—— 密钥文件加密落盘后可读")
    func persistenceAcrossInstances() throws {
        let (first, directory) = try makeStore()
        let id = UUID()
        try first.save(id: id, secret: secret, metadataJSON: metadata)

        // 新实例（新对象、同一目录）≈ 重启后的 App
        let second = EncryptedStore(directory: directory)
        let entry = try second.read(id: id)
        #expect(entry.secret == secret)

        // 磁盘上没有明文：文件内容不应包含原始密钥字节
        let rawFile = try Data(contentsOf: directory.appendingPathComponent("wallet.bin"))
        #expect(rawFile.range(of: secret) == nil)   // S1：密文落盘，非明文
    }

    @Test("save 幂等（同 id 覆盖）、update / delete 语义与 KeychainStore 一致")
    func crudSemantics() throws {
        let (store, _) = try makeStore()
        let id = UUID()
        try store.save(id: id, secret: secret, metadataJSON: metadata)

        // save 幂等覆盖
        let replaced = Data([0x09])
        try store.save(id: id, secret: replaced, metadataJSON: metadata)
        #expect(try store.read(id: id).secret == replaced)
        #expect(try store.readAllMetadata().count == 1)

        // update 不存在的条目 → itemNotFound
        #expect(throws: EncryptedStore.StoreError.itemNotFound) {
            try store.update(id: UUID(), secret: replaced, metadataJSON: metadata)
        }

        // delete 幂等性：存在 → 成功；再删 → itemNotFound
        try store.delete(id: id)
        #expect(throws: EncryptedStore.StoreError.itemNotFound) { try store.read(id: id) }
        #expect(throws: EncryptedStore.StoreError.itemNotFound) { try store.delete(id: id) }
        #expect(try store.readAllMetadata().isEmpty)
    }

    @Test("钱包损坏（篡改密文）→ 明确报错，不静默返回脏数据（GCM 认证）")
    func corruptedWalletDetected() throws {
        let (store, directory) = try makeStore()
        try store.save(id: UUID(), secret: secret, metadataJSON: metadata)

        let walletURL = directory.appendingPathComponent("wallet.bin")
        var raw = try Data(contentsOf: walletURL)
        // 翻转密文末尾一个字节（GCM tag 应检测到篡改）
        raw[raw.count - 1] ^= 0xFF
        try raw.write(to: walletURL)

        #expect(throws: EncryptedStore.StoreError.malformedWallet) {
            try store.readAllMetadata()
        }
    }

    @Test("主密钥文件丢失 → 旧钱包不可解密（明确报错而非崩溃）")
    func missingMasterKey() throws {
        let (store, directory) = try makeStore()
        try store.save(id: UUID(), secret: secret, metadataJSON: metadata)

        try FileManager.default.removeItem(at: directory.appendingPathComponent("master.key"))

        // 新实例会生成新主密钥 → 解不开旧钱包 → 报错（不静默、不崩溃）
        let second = EncryptedStore(directory: directory)
        #expect(throws: EncryptedStore.StoreError.malformedWallet) {
            try second.readAllMetadata()
        }
    }

    @Test("文件权限：master.key 0600，目录 0700（最小权限）")
    func filePermissions() throws {
        let (store, directory) = try makeStore()
        try store.save(id: UUID(), secret: secret, metadataJSON: metadata)

        let keyAttributes = try FileManager.default.attributesOfItem(
            atPath: directory.appendingPathComponent("master.key").path
        )
        #expect(keyAttributes[.posixPermissions] as? Int == 0o600)

        let dirAttributes = try FileManager.default.attributesOfItem(atPath: directory.path)
        #expect(dirAttributes[.posixPermissions] as? Int == 0o700)
    }
}
