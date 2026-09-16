import Foundation
import Testing
@testable import TwoWay

/// C2-1：列表页的可测核心 —— AccountStore（加载 / 搜索 / 计数 / 空态 / 置顶 / 取码）
@MainActor
@Suite("AccountStore（列表逻辑）")
struct AccountStoreTests {

    /// 可变时钟，用于驱动取码与周期切换
    private final class Clock {
        var unixTime: TimeInterval
        init(_ t: TimeInterval) { unixTime = t }
        func now() -> Date { Date(timeIntervalSince1970: unixTime) }
    }

    private func makeStore(clock: Clock, accounts: [(String, String?, String)] = []) throws -> (AccountStore, InMemorySecretStore) {
        let backing = InMemorySecretStore()
        let store = AccountStore(secrets: backing, now: clock.now)
        for (name, issuer, secret) in accounts {
            try store.add(displayName: name, issuer: issuer, secretBase32: secret)
        }
        return (store, backing)
    }

    private let seed: [(String, String?, String)] = [
        ("GitHub", "GitHub", "JBSWY3DPEHPK3PXP"),
        ("AWS 控制台", nil, "GEZDGNBVGY3TQOJQ"),
        ("腾讯云", "Tencent Cloud", "KRSXG5CTMVRXEZLU"),
    ]

    // MARK: 加载与排序

    @Test("load 按添加时间倒序 —— 「新账户置顶」")
    func loadSortsNewestFirst() throws {
        let clock = Clock(1_760_000_000)
        let backing = InMemorySecretStore()
        let store = AccountStore(secrets: backing, now: clock.now)

        // 直接往底层写三条不同时间的数据，再走 load()
        let encoder = JSONEncoder()
        for (offset, name) in ["最早", "中间", "最新"].enumerated() {
            let account = Account(
                displayName: name,
                addedAt: Date(timeIntervalSince1970: 1_760_000_000 + Double(offset) * 100)
            )
            try backing.save(
                id: account.id,
                secret: Data([UInt8(offset + 1)]),
                metadataJSON: encoder.encode(account)
            )
        }
        try store.load()

        #expect(store.accounts.map(\.displayName) == ["最新", "中间", "最早"])
    }

    @Test("空库 load 不报错，计数为 0（E2 删到 0 个的场景）")
    func loadEmpty() throws {
        let (store, _) = try makeStore(clock: Clock(0), accounts: [])
        try store.load()
        #expect(store.accounts.isEmpty)
        #expect(store.countText == "共 0 个账户")
    }

    // MARK: FR-03 搜索

    @Test("FR-03：输入即过滤，匹配账户名或发行方，不区分大小写")
    func searchFiltering() throws {
        let (store, _) = try makeStore(clock: Clock(0), accounts: seed)

        store.searchQuery = "github"
        #expect(store.filteredAccounts.map(\.displayName) == ["GitHub"])

        store.searchQuery = "tencent"
        #expect(store.filteredAccounts.map(\.displayName) == ["腾讯云"])

        store.searchQuery = "控制台"
        #expect(store.filteredAccounts.map(\.displayName) == ["AWS 控制台"])

        store.searchQuery = ""
        #expect(store.filteredAccounts.count == 3)
    }

    @Test("FR-03 / E7：无结果时列表为空、计数同步为 0，但不清空用户输入")
    func searchNoResults() throws {
        let (store, _) = try makeStore(clock: Clock(0), accounts: seed)

        store.searchQuery = "不存在的关键字"
        #expect(store.filteredAccounts.isEmpty)
        #expect(store.countText == "共 0 个账户")
        #expect(store.searchQuery == "不存在的关键字")   // E7：不清空输入

        store.searchQuery = ""
        #expect(store.countText == "共 3 个账户")
    }

    // MARK: 增

    @Test("add 置顶 + 持久化到底层存储")
    func addInsertsAtTopAndPersists() throws {
        let (store, backing) = try makeStore(clock: Clock(0), accounts: seed)
        try store.add(displayName: "Notion", issuer: nil, secretBase32: "KRSXG5CTMVRXEZLU")

        #expect(store.accounts.first?.displayName == "Notion")
        #expect(store.accounts.count == 4)
        #expect(try backing.readAllMetadata().count == 4)   // 已落库
    }

    @Test("PRD §7.4：名称为空时用「新账户」，密钥自动清洗")
    func addWithBlankNameAndDirtySecret() throws {
        let (store, _) = try makeStore(clock: Clock(0), accounts: [])
        try store.add(displayName: "   ", issuer: nil, secretBase32: " jbsw-y3dp ehpk 3pxp ")

        #expect(store.accounts.first?.displayName == "新账户")
        #expect(store.code(for: store.accounts[0].id) != nil)   // 清洗后能算码
    }

    @Test("E4：非法密钥在提交时拦截，不产生错误账户")
    func addWithInvalidSecret() throws {
        let (store, _) = try makeStore(clock: Clock(0), accounts: [])

        #expect(throws: Base32.DecodingError.invalidCharacter("1")) {
            try store.add(displayName: "x", issuer: nil, secretBase32: "JBSWY3DPEHPK3PX1")
        }
        #expect(store.accounts.isEmpty)   // 不产生半成品账户
    }

    // MARK: 删

    @Test("FR-06：删除后列表同步减少；E2 删到 0 计数归零")
    func deleteRemoves() throws {
        let (store, _) = try makeStore(clock: Clock(0), accounts: seed)
        let target = store.accounts[1]

        try store.delete(id: target.id)

        #expect(store.accounts.count == 2)
        #expect(!store.accounts.contains { $0.id == target.id })

        for account in store.accounts { try store.delete(id: account.id) }
        #expect(store.accounts.isEmpty)
        #expect(store.countText == "共 0 个账户")
    }

    @Test("删除当前展开 / 选中的账户时，相关状态一并清理")
    func deleteClearsRowAndSelection() throws {
        let (store, _) = try makeStore(clock: Clock(0), accounts: seed)
        let target = store.accounts[0]

        store.setOpenedRow(target.id)
        store.selectedAccountID = target.id
        try store.delete(id: target.id)

        #expect(store.openedRowID == nil)
        #expect(store.selectedAccountID == nil)
    }

    // MARK: R9 行展开互斥

    @Test("R9：openedRowID 是单值，天然同时只有一行展开")
    func rowExpansionIsMutuallyExclusive() throws {
        let (store, _) = try makeStore(clock: Clock(0), accounts: seed)
        let a = store.accounts[0].id
        let b = store.accounts[1].id

        store.setOpenedRow(a)
        #expect(store.openedRowID == a)
        store.setOpenedRow(b)
        #expect(store.openedRowID == b)

        store.setOpenedRow(nil)
        #expect(store.openedRowID == nil)
    }

    // MARK: 取码（T2 / T6 / P-1 缓存）

    @Test("T6：从 Store 取码与 RFC 6238 向量一致")
    func codeMatchesRFCVector() throws {
        let clock = Clock(59)   // RFC 6238 T=59
        let (store, _) = try makeStore(clock: clock, accounts: [])
        try store.add(
            displayName: "RFC",
            issuer: nil,
            secretBase32: "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ"   // "12345678901234567890"
        )
        let id = try #require(store.accounts.first?.id)
        #expect(store.code(for: id) == "287082")
        #expect(store.displayCode(for: id) == "287 082")   // T2 展示格式
    }

    @Test("P-1：同一周期内命中缓存，跨周期重算")
    func codeCaching() throws {
        let clock = Clock(59)
        let (store, _) = try makeStore(clock: clock, accounts: [])
        try store.add(displayName: "RFC", issuer: nil, secretBase32: "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ")
        let id = try #require(store.accounts.first?.id)

        #expect(store.code(for: id) == "287082")

        clock.unixTime = 60   // 跨入下一周期（counter 1 → 2）
        #expect(store.code(for: id) == "359152")

        clock.unixTime = 75   // 同一周期内（counter 仍为 2）
        #expect(store.code(for: id) == "359152")
    }

    @Test("取不存在的账户返回 nil，不崩溃")
    func codeForUnknownID() throws {
        let (store, _) = try makeStore(clock: Clock(0), accounts: seed)
        #expect(store.code(for: UUID()) == nil)
        #expect(store.displayCode(for: UUID()) == nil)
        #expect(store.timeState(for: UUID()) == nil)
    }

    @Test("timeState 提供倒计环所需状态（T3/T4）")
    func timeState() throws {
        let clock = Clock(25)
        let (store, _) = try makeStore(clock: clock, accounts: [])
        try store.add(displayName: "a", issuer: nil, secretBase32: "JBSWY3DPEHPK3PXP")
        let id = try #require(store.accounts.first?.id)

        let state = try #require(store.timeState(for: id))
        #expect(state.secondsRemaining == 5)
        #expect(state.isWarning)   // T4：剩余 ≤5s
    }
}
