import Foundation

/// 状态栏下拉的「列哪些账户」纯逻辑（可单测，与视图解耦）
///
/// 规则（用户需求）：
/// - 未搜索时**最多列 `limit` 条**（默认 5），其余靠搜索找；
/// - 一旦输入关键词，**不再受条数限制**（否则搜了也看不到第 6 条）；
/// - 过滤口径与主列表一致（`Account.matches`：账户名或发行方，忽略大小写）。
enum MenuBarSelection {

    struct Result: Equatable {
        /// 面板实际列出的账户（顺序沿用传入顺序 = 主列表顺序：最近添加在前）
        var accounts: [Account]
        /// 因超出上屏上限而未列出的数量（仅在未搜索时可能 > 0，用于提示「输入关键词搜索」）
        var hiddenCount: Int
    }

    static let defaultLimit = 5

    static func entries(
        from accounts: [Account],
        query: String,
        limit: Int = defaultLimit
    ) -> Result {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            return Result(
                accounts: Array(accounts.prefix(limit)),
                hiddenCount: max(0, accounts.count - limit)
            )
        }

        return Result(
            accounts: accounts.filter { $0.matches(query: trimmed) },
            hiddenCount: 0
        )
    }
}
