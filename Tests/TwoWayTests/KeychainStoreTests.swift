import Foundation
import Security
import Testing
@testable import TwoWay

/// C1-1：KeychainStore 集成测试
///
/// 用 `SecKeychainCreate` 造临时钥匙串注入，**全程不碰登录钥匙串**。
/// 测的是真实 Security 栈，TEHC_PLAN §4.2 的三项待验证行为就在这里被实证：
///   1. `kSecUseKeychain` 只对 SecItemAdd 生效
///   2. `kSecMatchSearchList` 对查询类调用生效
///   3. `kSecMatchLimitAll` + `kSecReturnData` 会被拒（-50）→ 只能批量取属性、逐条取密钥
@Suite("KeychainStore（临时钥匙串）")
struct KeychainStoreTests {

    // MARK: 测试基建

    /// 每个测试用例独立一把临时钥匙串，互不干扰
    private func makeKeychain() throws -> SecKeychain {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("2way-kc-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let path = directory.appendingPathComponent("test.keychain").path
        let password = "test-\(UUID().uuidString)"

        var keychain: SecKeychain?
        let status = SecKeychainCreate(
            path, UInt32(password.utf8.count), password, false, nil, &keychain
        )
        #expect(status == errSecSuccess, "创建临时钥匙串失败 status=\(status)")
        return try #require(keychain)
    }

    private func makeStore(_ keychain: SecKeychain, service: String = "com.kimi.2way.tests") -> KeychainStore {
        KeychainStore(service: service, keychain: keychain)
    }

    private func metadata(_ name: String, issuer: String? = nil) -> Data {
        var payload: [String: String] = ["name": name]
        if let issuer { payload["issuer"] = issuer }
        return try! JSONSerialization.data(withJSONObject: payload)
    }

    // MARK: 写路径

    @Test("写入后可原样读回（含密钥）")
    func saveAndRead() throws {
        let store = makeStore(try makeKeychain())
        let id = UUID()
        let secret = Data([0x48, 0x65, 0x6C, 0x6C, 0x6F, 0x21])

        try store.save(id: id, secret: secret, metadataJSON: metadata("GitHub"))

        let entry = try store.read(id: id)
        #expect(entry.id == id)
        #expect(entry.secret == secret)
        #expect(entry.metadataJSON == metadata("GitHub"))
    }

    @Test("save 幂等：重复写同一 id 不产生第二条、以最后一次为准")
    func saveIsIdempotent() throws {
        let store = makeStore(try makeKeychain())
        let id = UUID()

        try store.save(id: id, secret: Data([0x01]), metadataJSON: metadata("v1"))
        try store.save(id: id, secret: Data([0x02]), metadataJSON: metadata("v2"))

        #expect(try store.readAllMetadata().count == 1)
        #expect(try store.read(id: id).secret == Data([0x02]))
    }

    @Test("update 修改既有条目；不存在的 id 报 itemNotFound")
    func updateBehavior() throws {
        let store = makeStore(try makeKeychain())
        let id = UUID()

        try store.save(id: id, secret: Data([0xAA]), metadataJSON: metadata("before"))
        try store.update(id: id, secret: Data([0xBB]), metadataJSON: metadata("after"))
        #expect(try store.read(id: id).secret == Data([0xBB]))

        #expect(throws: KeychainStore.StoreError.itemNotFound) {
            try store.update(id: UUID(), secret: Data([0xCC]), metadataJSON: metadata("ghost"))
        }
    }

    @Test("delete 幂等：删除不存在的条目不报错")
    func deleteIsIdempotent() throws {
        let store = makeStore(try makeKeychain())
        let id = UUID()

        try store.save(id: id, secret: Data([0x01]), metadataJSON: metadata("x"))
        try store.delete(id: id)
        #expect(throws: KeychainStore.StoreError.itemNotFound) { _ = try store.read(id: id) }
        try store.delete(id: id)   // 第二次删除不应抛错
    }

    // MARK: 读路径

    @Test("readAllMetadata 一次拉全量元数据（D3 启动路径）")
    func readAllMetadataReturnsEverything() throws {
        let store = makeStore(try makeKeychain())

        let ids = (0..<7).map { _ in UUID() }
        for (index, id) in ids.enumerated() {
            try store.save(
                id: id,
                secret: Data([UInt8(index + 1)]),
                metadataJSON: metadata("account-\(index)")
            )
        }

        let all = try store.readAllMetadata()
        #expect(all.count == 7)
        #expect(Set(all.map(\.id)) == Set(ids))
        // 元数据与写入顺序无关，但必须能对上号
        #expect(all.map { String(data: $0.metadataJSON, encoding: .utf8)! }
            .contains { $0.contains("account-3") })
    }

    @Test("隔离性：不同 service 互相不可见")
    func serviceIsolation() throws {
        let keychain = try makeKeychain()
        let id = UUID()
        let secret = Data([0x77])

        try makeStore(keychain, service: "svc.a").save(id: id, secret: secret, metadataJSON: metadata("A"))
        try makeStore(keychain, service: "svc.b").save(id: id, secret: secret, metadataJSON: metadata("B"))

        #expect(try makeStore(keychain, service: "svc.a").readAllMetadata().count == 1)
        #expect(try makeStore(keychain, service: "svc.b").readAllMetadata().count == 1)
        #expect(try makeStore(keychain, service: "svc.c").readAllMetadata().isEmpty)
    }

    @Test("同 service 下允许同名账户 —— 主键是 UUID 而非名称")
    func sameNameDifferentUUID() throws {
        let store = makeStore(try makeKeychain())

        try store.save(id: UUID(), secret: Data([0x01]), metadataJSON: metadata("同名"))
        try store.save(id: UUID(), secret: Data([0x02]), metadataJSON: metadata("同名"))

        #expect(try store.readAllMetadata().count == 2)
    }

    @Test("不同钥匙串互相隔离（kSecUseKeychain / kSecMatchSearchList 注入生效的实证）")
    func keychainIsolation() throws {
        let keychainA = try makeKeychain()
        let keychainB = try makeKeychain()
        let id = UUID()

        try makeStore(keychainA).save(id: id, secret: Data([0x11]), metadataJSON: metadata("in-A"))

        #expect(try makeStore(keychainA).read(id: id).secret == Data([0x11]))
        #expect(try makeStore(keychainA).readAllMetadata().count == 1)
        #expect(try makeStore(keychainB).readAllMetadata().isEmpty)
        #expect(throws: KeychainStore.StoreError.itemNotFound) {
            _ = try makeStore(keychainB).read(id: id)
        }
    }

    // MARK: 真实领域对象全链路

    @Test("元数据批量 → 逐条取密钥 → 算出 RFC 向量值")
    func fullPipeline() throws {
        let store = makeStore(try makeKeychain())

        // 注意：RFC 6238 向量按 30 秒周期推导（T=59 → counter=1），周期必须一致
        let parameters = try OTPParameters(algorithm: .sha256, digits: 8, period: 30)
        let account = Account(displayName: "GitHub", issuer: "GitHub", parameters: parameters)
        let secret = Data("12345678901234567890123456789012".utf8)

        // 用默认日期策略（timeIntervalSinceReferenceDate 的 Double，无损）。
        // 若改用 .iso8601 会截断到秒，Date 相等性断言就会失败 —— 这是有意记录的行为差异。
        let json = try JSONEncoder().encode(account)

        try store.save(id: account.id, secret: secret, metadataJSON: json)

        // 启动路径：先拿元数据（不含密钥）
        let listed = try store.readAllMetadata()
        #expect(listed.count == 1)
        let restored = try JSONDecoder().decode(Account.self, from: listed[0].metadataJSON)
        #expect(restored == account)

        // 取码路径：再按 id 取密钥
        let entry = try store.read(id: account.id)
        #expect(entry.secret == secret)
        let counter = UInt64((59.0 / 30.0).rounded(.down))
        #expect(
            TOTPEngine.rawCode(secret: entry.secret, counter: counter, parameters: parameters)
                == "46119246"   // RFC 6238 SHA256 T=59 · 8 位
        )
    }

    @Test("ISO8601 日期策略会截断亚秒精度（记录这一行为，避免误判为 bug）")
    func iso8601TruncatesSubsecond() throws {
        let original = Account(displayName: "a", addedAt: Date(timeIntervalSince1970: 1_760_000_000.567))
        let data = try JSONEncoder().encode(original)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        let restored = try decoder.decode(Account.self, from: encoder.encode(original))
        #expect(restored.addedAt != original.addedAt)
        #expect(restored.addedAt.timeIntervalSince1970 == 1_760_000_000)
        #expect(restored.id == original.id)   // 其余字段不受影响
    }

    @Test("元数据缺失时报 payloadCorrupted 而不是崩溃")
    func corruptedPayload() throws {
        let keychain = try makeKeychain()
        let store = makeStore(keychain)
        let id = UUID()

        // 绕过 store，直接写一条没有 kSecAttrGeneric 的条目
        let raw: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: "com.kimi.2way.tests",
            kSecAttrAccount: id.uuidString,
            kSecValueData: Data([0x01]),
            kSecUseKeychain: keychain,
        ]
        #expect(SecItemAdd(raw as CFDictionary, nil) == errSecSuccess)

        #expect(throws: KeychainStore.StoreError.payloadCorrupted) {
            _ = try store.read(id: id)
        }
    }
}
