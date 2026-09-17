import Foundation
import Testing

@testable import TwoWay

/// DR-01 拖动排序：store 层的重排与落盘（跨实例重载仍保持顺序）
@MainActor
struct AccountStoreReorderTests {

    /// 建一个 3 个账户的 store（添加顺序 A → B → C，列表顺序应为 C、B、A）
    private func makeStore() throws -> (AccountStore, InMemorySecretStore) {
        let secrets = InMemorySecretStore()
        let store = AccountStore(secrets: secrets)
        try store.add(displayName: "A", issuer: nil, secretBase32: "JBSWY3DPEHPK3PXP")
        try store.add(displayName: "B", issuer: nil, secretBase32: "GEZDGNBVGY3TQOJQ")
        try store.add(displayName: "C", issuer: nil, secretBase32: "KRSXG5CTMVRXEZLU")
        return (store, secrets)
    }

    private func names(_ store: AccountStore) -> [String] {
        store.accounts.map(\.displayName)
    }

    @Test("初始（未自定义顺序）为添加时间倒序；新账户置顶")
    func defaultOrder() throws {
        let (store, _) = try makeStore()
        #expect(names(store) == ["C", "B", "A"])
        #expect(store.hasCustomOrder == false)
        #expect(store.accounts.allSatisfy { $0.sortIndex == nil })
    }

    @Test("把最后一条拖到最前 → 顺序变化且标记为已自定义")
    func moveFirstToBottom() throws {
        let (store, _) = try makeStore()
        let a = try #require(store.accounts.first { $0.displayName == "A" })
        let c = try #require(store.accounts.first { $0.displayName == "C" })

        let changed = try store.move(id: a.id, relativeTo: c.id, position: .before)

        #expect(changed)
        #expect(names(store) == ["A", "C", "B"])
        #expect(store.hasCustomOrder)
        #expect(store.accounts.map(\.sortIndex) == [0, 1, 2])
    }

    @Test("放到某条之后（.after）")
    func moveAfter() throws {
        let (store, _) = try makeStore()
        let c = try #require(store.accounts.first { $0.displayName == "C" })
        let a = try #require(store.accounts.first { $0.displayName == "A" })

        let changed = try store.move(id: c.id, relativeTo: a.id, position: .after)

        #expect(changed)
        #expect(names(store) == ["B", "A", "C"])
    }

    @Test("原位放下 / 自己拖自己 → 不产生变化（供调用方判断是否需要提示）")
    func noOpMoves() throws {
        let (store, _) = try makeStore()
        let b = try #require(store.accounts.first { $0.displayName == "B" })
        let c = try #require(store.accounts.first { $0.displayName == "C" })

        #expect(try store.move(id: b.id, relativeTo: b.id, position: .before) == false)
        // 本来就紧跟在 C 之后 → 再放到 C 之后等于没动
        #expect(try store.move(id: b.id, relativeTo: c.id, position: .after) == false)
        #expect(names(store) == ["C", "B", "A"])
    }

    @Test("顺序落盘：换一个 store 实例重新 load 仍保持")
    func orderPersistsAcrossReload() throws {
        let (store, secrets) = try makeStore()
        let a = try #require(store.accounts.first { $0.displayName == "A" })
        let c = try #require(store.accounts.first { $0.displayName == "C" })
        try store.move(id: a.id, relativeTo: c.id, position: .before)

        // 模拟重启：同一份存储、新实例
        let reloaded = AccountStore(secrets: secrets)
        try reloaded.load()

        #expect(names(reloaded) == ["A", "C", "B"])
        #expect(reloaded.accounts.map(\.sortIndex) == [0, 1, 2])
    }

    @Test("已有自定义顺序时，新添加的账户仍置顶（不会掉到末尾）")
    func newAccountGoesToTopAfterReorder() throws {
        let (store, secrets) = try makeStore()
        let a = try #require(store.accounts.first { $0.displayName == "A" })
        let c = try #require(store.accounts.first { $0.displayName == "C" })
        try store.move(id: a.id, relativeTo: c.id, position: .before)
        #expect(names(store) == ["A", "C", "B"])

        try store.add(displayName: "D", issuer: nil, secretBase32: "MFRGGZDFMZTWQ2LK")
        #expect(names(store) == ["D", "A", "C", "B"])

        let reloaded = AccountStore(secrets: secrets)
        try reloaded.load()
        #expect(names(reloaded) == ["D", "A", "C", "B"])   // 重启后仍置顶
    }

    @Test("删除后顺序保持稠密（序号不留空洞）")
    func denseIndicesAfterDelete() throws {
        let (store, secrets) = try makeStore()
        let a = try #require(store.accounts.first { $0.displayName == "A" })
        let c = try #require(store.accounts.first { $0.displayName == "C" })
        try store.move(id: a.id, relativeTo: c.id, position: .before)

        let b = try #require(store.accounts.first { $0.displayName == "B" })
        try store.delete(id: b.id)

        let reloaded = AccountStore(secrets: secrets)
        try reloaded.load()
        #expect(names(reloaded) == ["A", "C"])
        // 序号允许暂留空洞（下次拖动会重排），但显示顺序必须正确
        #expect(reloaded.accounts.map(\.displayName) == ["A", "C"])
    }

    @Test("排序只改元数据，不碰密钥（取码结果不变）")
    func reorderKeepsSecret() throws {
        let (store, _) = try makeStore()
        let a = try #require(store.accounts.first { $0.displayName == "A" })
        let before = try #require(store.code(for: a.id))

        let c = try #require(store.accounts.first { $0.displayName == "C" })
        try store.move(id: a.id, relativeTo: c.id, position: .before)

        #expect(store.code(for: a.id) == before)
    }
}
