import Foundation
import Testing

@testable import TwoWay

/// 状态栏下拉的选取逻辑（用户需求：默认最多 5 条，其余靠搜索）
struct MenuBarSelectionTests {

    private func accounts(_ names: [String], issuer: String? = nil) -> [Account] {
        names.map { Account(displayName: $0, issuer: issuer) }
    }

    @Test("无账户：空列表且不提示隐藏数量")
    func empty() {
        let result = MenuBarSelection.entries(from: [], query: "")
        #expect(result.accounts.isEmpty)
        #expect(result.hiddenCount == 0)
    }

    @Test("少于上限：全部列出，hiddenCount = 0")
    func fewerThanLimit() {
        let result = MenuBarSelection.entries(from: accounts(["a", "b", "c"]), query: "")
        #expect(result.accounts.map(\.displayName) == ["a", "b", "c"])
        #expect(result.hiddenCount == 0)
    }

    @Test("超过上限：只列前 5 条，hiddenCount 记录剩余数（用于提示去搜索）")
    func moreThanLimit() {
        let all = accounts(["a", "b", "c", "d", "e", "f", "g"])
        let result = MenuBarSelection.entries(from: all, query: "")
        #expect(result.accounts.count == MenuBarSelection.defaultLimit)
        #expect(result.accounts.map(\.displayName) == ["a", "b", "c", "d", "e"])
        #expect(result.hiddenCount == 2)

        // 顺序沿用传入顺序（= 主列表顺序：最近添加在前）
        #expect(result.accounts.first?.displayName == all.first?.displayName)
    }

    @Test("上限可调（默认 5）")
    func customLimit() {
        let result = MenuBarSelection.entries(from: accounts(["a", "b", "c"]), query: "", limit: 2)
        #expect(result.accounts.count == 2)
        #expect(result.hiddenCount == 1)
    }

    @Test("搜索时不再受条数限制：第 6 条也能被搜到")
    func searchIgnoresLimit() {
        let all = accounts(["a", "b", "c", "d", "e", "f", "github"])
        #expect(all.count == 7)

        let result = MenuBarSelection.entries(from: all, query: "git")
        #expect(result.accounts.map(\.displayName) == ["github"])
        #expect(result.hiddenCount == 0)
    }

    @Test("搜索匹配账户名与发行方、忽略大小写与首尾空白")
    func searchMatching() {
        let all = [
            Account(displayName: "ops", issuer: "Acme 控制台"),
            Account(displayName: "admin@example.com", issuer: "Homelab")
        ]

        #expect(MenuBarSelection.entries(from: all, query: "ACME").accounts.count == 1)
        #expect(MenuBarSelection.entries(from: all, query: "  homelab  ").accounts.count == 1)
        #expect(MenuBarSelection.entries(from: all, query: "admin@example").accounts.count == 1)
        // 纯空白视为未搜索 → 回到「最多 5 条」语义（此处 2 条全列）
        #expect(MenuBarSelection.entries(from: all, query: "   ").accounts.count == 2)
    }

    @Test("搜索无结果：空列表，不误报隐藏数量")
    func searchNoMatch() {
        let result = MenuBarSelection.entries(from: accounts(["a", "b"]), query: "zzz")
        #expect(result.accounts.isEmpty)
        #expect(result.hiddenCount == 0)
    }
}
