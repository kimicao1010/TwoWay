import Foundation

/// 账户的**非密钥**元数据。
///
/// S1：密钥绝不进入本类型、不进 UserDefaults / plist / 日志。
/// 密钥只经 `KeychainStore` 出入，`Account` 只持有它的 `id`。
struct Account: Identifiable, Hashable, Sendable, Codable {
    let id: UUID
    /// 列表主行文案（PRD §7.1 账户行）
    var displayName: String
    /// 发行方（PRD §7.3 搜索匹配「账户名或发行方」）
    var issuer: String?
    var parameters: OTPParameters
    /// 详情页「添加时间」（PRD §7.5 参数卡）
    var addedAt: Date
    /// 列表显示次序（DR-01 拖动排序）
    ///
    /// - `nil` = **从未自定义过顺序** → 列表沿用「按添加时间倒序」（新账户在顶）
    /// - 非 nil = 用户拖动排序过 → 按其**升序**排列（0 在最上）
    ///
    /// 之所以用「可选 + 全 nil 视为未排序」而不是「一律使用数组下标」：
    /// 已存在的老钱包里没有任何顺序信息，若直接改按下标显示，用户升级后列表顺序会突变。
    var sortIndex: Int?

    init(
        id: UUID = UUID(),
        displayName: String,
        issuer: String? = nil,
        parameters: OTPParameters = .standard,
        addedAt: Date = Date(),
        sortIndex: Int? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.issuer = issuer
        self.parameters = parameters
        self.addedAt = addedAt
        self.sortIndex = sortIndex
    }
}

extension Account {
    /// 「发行方：账户名」表述（发行方缺失或与名称相同时只显示名称）
    ///
    /// 列表行（PRD §7.1）、状态栏下拉、导出范围选择器共用同一口径。
    var issuerQualifiedName: String {
        guard let issuer, !issuer.isEmpty, issuer != displayName else { return displayName }
        return "\(issuer)：\(displayName)"
    }

    /// 搜索匹配（PRD FR-03）：账户名或发行方，不区分大小写
    func matches(query rawQuery: String) -> Bool {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        if displayName.localizedCaseInsensitiveContains(query) { return true }
        if let issuer, issuer.localizedCaseInsensitiveContains(query) { return true }
        return false
    }
}

// MARK: - 调试脱敏（S1/S2）

extension Account: CustomDebugStringConvertible {
    /// 显式脱敏：类型本身不含密钥，但 Debug 输出必须稳定且不夹带敏感内容
    var debugDescription: String {
        "Account(id: \(id.uuidString), name: \(displayName), issuer: \(issuer ?? "nil"), " +
        "algorithm: \(parameters.algorithm.rawValue), digits: \(parameters.digits), " +
        "period: \(parameters.period))"
    }
}
