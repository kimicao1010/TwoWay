import Foundation
import Observation

/// 屏幕路由（TECH_PLAN §3 状态层）
///
/// R9/E8：切屏时由调用方把 `store.openedRowID` 复位。
/// `pendingDeleteID` 挂在路由上：R8「删除」**不切屏**，直接在列表上弹确认（PRD v1.8 §7.2）。
@MainActor
@Observable
final class AppRouter {
    enum Screen: Equatable {
        case list
        case addAccount
        case editAccount   // P1 C4-2：编辑选中账户（依赖 store.selectedAccountID）
    }

    var screen: Screen = .list
    /// R8：待在弹窗中确认删除的账户（nil = 无弹窗）
    var pendingDeleteID: UUID?
    /// C4-3：备份导出/导入弹窗
    var backupSheet: BackupSheet?

    enum BackupSheet: Equatable {
        case export
        case importBackup
        case exportGAMigration   // C4-4：GA 兼容的迁移码二维码导出
    }
}

/// 手动输入页的表单状态机（PRD §7.4 手动输入）
///
/// 可测核心：E3 清洗预览、E4 实时校验、参数组装、空名兜底「新账户」。
/// 提交仍走 `AccountStore.add`（那里会再做一次 Base32 校验 —— E4 提交时拦截）。
@MainActor
@Observable
final class ManualEntryModel {

    /// 编辑模式（P1 C4-2）：非 nil 时提交走 `AccountStore.update` 而非 `add`
    private(set) var editingAccountID: UUID?

    var displayName = ""
    /// 发行方（可选）。C2-6 二维码解码成功后预填（PRD：预填发行方）
    var issuer: String?
    /// 用户原始输入，不清洗地保存（展示层显示原样，校验用清洗值）
    var secretRaw = ""
    var algorithm: OTPParameters.HashAlgorithm = .sha1
    var digits = 6
    var period: TimeInterval = 30

    // MARK: 派生

    /// E3 清洗结果（供 UI 展示「将使用」的密钥形态）
    var sanitizedSecret: String {
        Base32.sanitize(secretRaw)
    }

    /// E4：非空且含非法字符时报错；为空不报（空值在提交时拦截）
    var secretError: String? {
        guard !secretRaw.isEmpty else { return nil }
        do {
            _ = try Base32.decode(secretRaw)
            return nil
        } catch let error as Base32.DecodingError {
            return Self.message(for: error)
        } catch {
            return "密钥格式不正确"
        }
    }

    var parameters: OTPParameters? {
        try? OTPParameters(algorithm: algorithm, digits: digits, period: period)
    }

    var resolvedName: String {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "新账户" : trimmed
    }

    // MARK: 提交

    /// 新增或保存编辑，返回用于 toast 的账户名（成功后自清空表单）
    @discardableResult
    func submit(into store: AccountStore) throws -> String {
        let name = resolvedName
        let issuer = self.issuer?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedIssuer = issuer?.isEmpty == true ? nil : issuer
        let params = try OTPParameters(algorithm: algorithm, digits: digits, period: period)

        if let editingAccountID {
            try store.update(
                id: editingAccountID,
                displayName: displayName,
                issuer: normalizedIssuer,
                secretBase32: secretRaw,
                parameters: params
            )
        } else {
            try store.add(
                displayName: displayName,
                issuer: normalizedIssuer,
                secretBase32: secretRaw,
                parameters: params
            )
        }
        reset()
        return name
    }

    /// 编辑页预填（P1 C4-2）：表单内容 = 账户现值，提交走 update
    func prefillForEditing(account: Account, secretBase32: String) {
        displayName = account.displayName
        issuer = account.issuer
        secretRaw = secretBase32
        algorithm = account.parameters.algorithm
        digits = account.parameters.digits
        period = account.parameters.period
        editingAccountID = account.id
    }

    /// C2-6：二维码解码成功后预填全部字段（PRD §7.4：预填账户名 / 发行方 / 密钥 / 高级参数）
    func prefill(from fields: QRImport.PrefilledAccount) {
        displayName = fields.displayName
        issuer = fields.issuer
        secretRaw = fields.secretBase32
        algorithm = fields.parameters.algorithm
        digits = fields.parameters.digits
        period = fields.parameters.period
    }

    /// 取消 / 成功后清空
    func reset() {
        editingAccountID = nil
        displayName = ""
        issuer = nil
        secretRaw = ""
        algorithm = .sha1
        digits = 6
        period = 30
    }

    // MARK: E4 文案

    static func message(for error: Base32.DecodingError) -> String {
        switch error {
        case .invalidCharacter(let character):
            "密钥包含无法识别的字符「\(character)」，请检查是否为完整的 Base32 密钥"
        case .empty:
            "请输入密钥"
        }
    }
}
