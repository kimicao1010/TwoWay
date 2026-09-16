import Foundation
import Observation

/// 账户单一数据源（TECH_PLAN §3）
///
/// 持有非密钥元数据 + 内存中的密钥缓存（S1 允许内存持有，禁止落盘/进日志）。
/// 行展开状态 `openedRowID` 用**单值**表达，R9「同时最多一行展开」由类型天然保证。
@MainActor
@Observable
final class AccountStore {

    // MARK: - 状态

    private(set) var accounts: [Account] = []
    /// PRD FR-03：输入即过滤，匹配账户名或发行方，不区分大小写
    var searchQuery = ""
    /// R9：当前展开的行（单值 → 天然互斥）
    var openedRowID: UUID?
    /// 详情页当前账户
    var selectedAccountID: UUID?

    private(set) var isLoading = false

    // MARK: - 依赖

    private let secrets: any SecretStoring
    private let now: () -> Date
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    /// 密钥内存缓存：启动时逐条读入（Keychain 不支持批量倒出密码数据，见 §4.2）
    private var secretCache: [UUID: Data] = [:]
    /// 验证码缓存：同一周期内不重算（P-1，30Hz 刷新时避免每帧做 HMAC）
    private var codeCache: [UUID: (counter: UInt64, code: String)] = [:]

    init(
        secrets: any SecretStoring,
        now: @escaping () -> Date = Date.init,
        encoder: JSONEncoder = JSONEncoder(),
        decoder: JSONDecoder = JSONDecoder()
    ) {
        self.secrets = secrets
        self.now = now
        self.encoder = encoder
        self.decoder = decoder
    }

    // MARK: - 派生

    /// 列表实际展示的账户（搜索过滤后）
    var filteredAccounts: [Account] {
        accounts.filter { $0.matches(query: searchQuery) }
    }

    /// 底部计数（PRD FR-03：无结果时同步为「共 0 个账户」；E7 不清空用户输入）
    var countText: String {
        "共 \(filteredAccounts.count) 个账户"
    }

    var selectedAccount: Account? {
        accounts.first { $0.id == selectedAccountID }
    }

    // MARK: - 加载

    /// 启动路径：批量取元数据 + 逐条取密钥
    func load() throws {
        isLoading = true
        defer { isLoading = false }

        var loaded: [Account] = []
        var secretsInMemory: [UUID: Data] = [:]

        for metadata in try secrets.readAllMetadata() {
            let account = try decoder.decode(Account.self, from: metadata.metadataJSON)
            loaded.append(account)
            secretsInMemory[metadata.id] = try secrets.read(id: metadata.id).secret
        }

        // PRD §7.4「添加后置顶」→ 统一按添加时间倒序
        loaded.sort { $0.addedAt > $1.addedAt }

        accounts = loaded
        secretCache = secretsInMemory
        codeCache = [:]
    }

    // MARK: - 增删

    /// PRD §7.4：名称为空用「新账户」；E4 非法密钥在提交时拦截
    func add(
        displayName rawName: String,
        issuer: String?,
        secretBase32: String,
        parameters: OTPParameters = .standard
    ) throws {
        let secret = try Base32.decode(secretBase32)   // E3 清洗 + E4 校验
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        let account = Account(
            displayName: name.isEmpty ? "新账户" : name,
            issuer: issuer,
            parameters: parameters,
            addedAt: now()
        )
        try secrets.save(id: account.id, secret: secret, metadataJSON: encoder.encode(account))
        accounts.insert(account, at: 0)   // 新账户置顶
        secretCache[account.id] = secret
        codeCache[account.id] = nil
    }

    /// PRD FR-06：删除后列表同步减少；E2 删到 0 个时计数归零
    func delete(id: UUID) throws {
        try secrets.delete(id: id)
        accounts.removeAll { $0.id == id }
        secretCache[id] = nil
        codeCache[id] = nil
        if openedRowID == id { openedRowID = nil }
        if selectedAccountID == id { selectedAccountID = nil }
    }

    // MARK: - 行展开（R9）

    func setOpenedRow(_ id: UUID?) {
        openedRowID = id
    }

    // MARK: - 取码

    /// 复制用原始码（PRD T2：不含空格）
    func code(for id: UUID) -> String? {
        formattedCode(for: id, grouped: false)
    }

    /// 展示用格式化码（PRD T2：`XXX XXX`）
    func displayCode(for id: UUID) -> String? {
        formattedCode(for: id, grouped: true)
    }

    /// 同一周期内命中缓存（P-1：30Hz 刷新不做重复 HMAC）
    private func formattedCode(for id: UUID, grouped: Bool) -> String? {
        guard
            let account = accounts.first(where: { $0.id == id }),
            let secret = secretCache[id]
        else { return nil }

        let state = TOTPTime.state(at: now(), period: account.parameters.period)
        if let cached = codeCache[id], cached.counter == state.counter {
            return grouped ? TOTPEngine.grouped(cached.code) : cached.code
        }
        let code = TOTPEngine.rawCode(secret: secret, counter: state.counter, parameters: account.parameters)
        codeCache[id] = (state.counter, code)
        return grouped ? TOTPEngine.grouped(code) : code
    }

    /// 当前剩余秒数 / 告警态（供行内倒计环与「N 秒后刷新」）
    func timeState(for id: UUID) -> TOTPTimeState? {
        guard let account = accounts.first(where: { $0.id == id }) else { return nil }
        return TOTPTime.state(at: now(), period: account.parameters.period)
    }
}
