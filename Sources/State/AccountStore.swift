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

    enum StoreError: Error, Equatable {
        case accountNotFound
    }

    // MARK: - 依赖

    private let secrets: any SecretStoring
    private let now: () -> Date
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    // ⚠️ 四个缓存一律 `@ObservationIgnored`（2026-09-17 崩溃修复）：
    //
    // 它们会在**视图 body 求值期间**被写入（`displayCode` → `formattedCode` 命中/回填缓存、
    // `retrySecret` 回填缓存）。若参与 Observation 追踪，写操作会在 SwiftUI 更新事务中途
    // 触发失效 → `AttributeGraph precondition_failure` → SIGABRT。
    // 之前只有一个 scene（主窗口）时侥幸未崩；加上状态栏面板 / 预览窗后立刻复现。
    //
    // 刷新语义不受影响：码文本由 `CodePulse`（换码）驱动，环由 `RingClock` 直驱，
    // 都不依赖这些缓存的观察通知。

    /// 密钥内存缓存：启动时逐条读入
    @ObservationIgnored private var secretCache: [UUID: Data] = [:]
    /// 验证码缓存：同一周期内不重算（P-1，30Hz 刷新时避免每帧做 HMAC）
    @ObservationIgnored private var codeCache: [UUID: (counter: UInt64, code: String)] = [:]
    /// 密钥读取失败的账户（如文件损坏/缺失）—— 列表仍然展示，码显示占位
    @ObservationIgnored private var secretUnavailable: Set<UUID> = []
    /// 失败重试冷却：避免 30Hz 渲染里反复触发读取
    @ObservationIgnored private var lastRetryTime: [UUID: Date] = [:]
    private static let retryCooldown: TimeInterval = 3

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
    ///
    /// 容错语义：单条密钥读取失败（钥匙串 ACL 未授权 / 用户点了拒绝）**不影响
    /// 其余账户，也不影响列表展示** —— 该账户进 `secretUnavailable`，码显示占位，
    /// 之后在 `code(for:)` 里按冷却间隔静默重试（用户点「始终允许」后自动恢复）。
    func load() throws {
        isLoading = true
        defer { isLoading = false }

        var loaded: [Account] = []
        var secretsInMemory: [UUID: Data] = [:]
        var unavailable: Set<UUID> = []

        for metadata in try secrets.readAllMetadata() {
            let account = try decoder.decode(Account.self, from: metadata.metadataJSON)
            loaded.append(account)
            if let secret = try? secrets.read(id: metadata.id).secret {
                secretsInMemory[metadata.id] = secret
            } else {
                unavailable.insert(metadata.id)
            }
        }

        // PRD §7.4「添加后置顶」→ 统一按添加时间倒序
        loaded.sort { $0.addedAt > $1.addedAt }

        accounts = loaded
        secretCache = secretsInMemory
        secretUnavailable = unavailable
        lastRetryTime = [:]
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

    /// 编辑账户（P1 C4-2）：名称 / 发行方 / 密钥 / 高级参数可改
    ///
    /// 密钥重走 E3 清洗 + E4 校验；写回后清空该账户的取码缓存（参数或密钥可能已变）。
    func update(
        id: UUID,
        displayName rawName: String,
        issuer: String?,
        secretBase32: String,
        parameters: OTPParameters
    ) throws {
        guard let index = accounts.firstIndex(where: { $0.id == id }) else {
            throw StoreError.accountNotFound
        }
        let secret = try Base32.decode(secretBase32)   // E3 清洗 + E4 校验
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)

        var account = accounts[index]
        account.displayName = name.isEmpty ? "新账户" : name
        account.issuer = issuer
        account.parameters = parameters

        try secrets.update(id: id, secret: secret, metadataJSON: encoder.encode(account))

        accounts[index] = account
        secretCache[id] = secret
        codeCache[id] = nil
    }

    /// 编辑页预填用：返回该账户密钥的规范 Base32 形态（密钥始终只在内存中流转，S1）
    func secretBase32(for id: UUID) -> String? {
        guard let secret = secretCache[id] ?? (try? secrets.read(id: id).secret) else { return nil }
        return Base32.encode(secret)
    }

    // MARK: - 备份导出 / 导入（C4-3）

    /// 导出用：全部账户 + 密钥（密钥只在内存中流转，S1）
    ///
    /// 密钥不可读的账户会被跳过（正常情况下不应发生）。
    func backupEntries() -> [BackupArchive.Entry] {
        accounts.compactMap { account in
            guard let secret = secretCache[account.id] ?? (try? secrets.read(id: account.id).secret) else {
                return nil
            }
            return BackupArchive.Entry(
                id: account.id,
                displayName: account.displayName,
                issuer: account.issuer,
                parameters: account.parameters,
                addedAt: account.addedAt,
                secret: secret
            )
        }
    }

    /// 导入备份：**同 id 已存在则跳过**（幂等；重复导入不产生副本，也不覆盖本地改动）。
    /// 返回（导入数, 跳过数）供 toast 明示，不静默。
    @discardableResult
    func importBackup(_ entries: [BackupArchive.Entry]) throws -> (imported: Int, skipped: Int) {
        var imported = 0
        var skipped = 0
        var didChange = false

        for entry in entries {
            if accounts.contains(where: { $0.id == entry.id }) {
                skipped += 1
                continue
            }
            let account = Account(
                id: entry.id,
                displayName: entry.displayName,
                issuer: entry.issuer,
                parameters: entry.parameters,
                addedAt: entry.addedAt
            )
            try secrets.save(id: account.id, secret: entry.secret, metadataJSON: encoder.encode(account))
            accounts.append(account)
            secretCache[account.id] = entry.secret
            imported += 1
            didChange = true
        }

        if didChange {
            accounts.sort { $0.addedAt > $1.addedAt }   // 与其他入口一致的倒序
            codeCache = [:]
        }
        return (imported, skipped)
    }

    /// PRD FR-06：删除后列表同步减少；E2 删到 0 个时计数归零
    func delete(id: UUID) throws {
        try secrets.delete(id: id)
        accounts.removeAll { $0.id == id }
        secretCache[id] = nil
        codeCache[id] = nil
        secretUnavailable.remove(id)
        lastRetryTime[id] = nil
        if openedRowID == id { openedRowID = nil }
        if selectedAccountID == id { selectedAccountID = nil }
    }

    // MARK: - 行展开（R9）

    func setOpenedRow(_ id: UUID?) {
        #if DEBUG
        RowTrace.log("setOpenedRow \(id.map { String($0.uuidString.prefix(4)) } ?? "nil")")
        #endif
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
    ///
    /// 密钥缺失时（ACL 未授权等）按冷却间隔静默重试读取 —— 用户在系统弹窗点
    /// 「始终允许」后无需重启即可恢复显示。
    private func formattedCode(for id: UUID, grouped: Bool) -> String? {
        guard let account = accounts.first(where: { $0.id == id }) else { return nil }

        let secret: Data
        if let cached = secretCache[id] {
            secret = cached
        } else {
            guard let fetched = retrySecret(for: id) else { return nil }
            secret = fetched
        }

        let state = TOTPTime.state(at: now(), period: account.parameters.period)
        if let cached = codeCache[id], cached.counter == state.counter {
            return grouped ? TOTPEngine.grouped(cached.code) : cached.code
        }
        let code = TOTPEngine.rawCode(secret: secret, counter: state.counter, parameters: account.parameters)
        codeCache[id] = (state.counter, code)
        return grouped ? TOTPEngine.grouped(code) : code
    }

    /// 按冷却间隔重试单条密钥读取（成功则入缓存并移出失败集合）
    private func retrySecret(for id: UUID) -> Data? {
        let last = lastRetryTime[id] ?? .distantPast
        guard now().timeIntervalSince(last) >= Self.retryCooldown else { return nil }
        lastRetryTime[id] = now()

        guard let secret = try? secrets.read(id: id).secret else { return nil }
        secretCache[id] = secret
        secretUnavailable.remove(id)
        return secret
    }

    /// 当前剩余秒数 / 告警态（供行内倒计环与「N 秒后刷新」）
    func timeState(for id: UUID) -> TOTPTimeState? {
        guard let account = accounts.first(where: { $0.id == id }) else { return nil }
        return TOTPTime.state(at: now(), period: account.parameters.period)
    }
}
