import Foundation
import Observation

/// C2-5 屏幕路由（TECH_PLAN §3 状态层）
///
/// 目前只有列表 ↔ 添加账户；C2-7 / C2-8 将扩展 detail / deleteConfirm。
/// R9/E8：切屏时由调用方把 `store.openedRowID` 复位。
@MainActor
@Observable
final class AppRouter {
    enum Screen: Equatable {
        case list
        case addAccount
    }

    var screen: Screen = .list
}

/// 手动输入页的表单状态机（PRD §7.4 手动输入）
///
/// 可测核心：E3 清洗预览、E4 实时校验、参数组装、空名兜底「新账户」。
/// 提交仍走 `AccountStore.add`（那里会再做一次 Base32 校验 —— E4 提交时拦截）。
@MainActor
@Observable
final class ManualEntryModel {

    var displayName = ""
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

    /// 写入账户，返回用于 toast 的账户名（成功后自清空表单）
    @discardableResult
    func submit(into store: AccountStore) throws -> String {
        let name = resolvedName
        let params = try OTPParameters(algorithm: algorithm, digits: digits, period: period)
        try store.add(displayName: displayName, issuer: nil, secretBase32: secretRaw, parameters: params)
        reset()
        return name
    }

    /// 取消 / 成功后清空
    func reset() {
        displayName = ""
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
