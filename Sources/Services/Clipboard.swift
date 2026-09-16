import AppKit

/// 剪贴板底层封装（PRD R1 / E1）
enum Clipboard {

    /// 写入纯文本。返回是否成功 —— E1 要求失败时给出提示，**不静默失败**。
    @discardableResult
    static func copyString(_ string: String) -> Bool {
        SystemPasteboard().write(string)
    }
}

// MARK: - 抽象（供 S4 单测模拟「其他应用写入」）

/// 剪贴板的最小能力面。抽出协议是为了单测能模拟 changeCount 变化，
/// 验证「不误清用户后来复制的内容」（PRD §4.7 / S4 的关键约束）。
protocol Pasteboard {
    /// 系统剪贴板的变更计数：每次写入（含其他应用）都会变化
    var changeCount: Int { get }
    /// 清空并写入；返回是否成功
    @discardableResult
    func write(_ string: String) -> Bool
    /// 仅清空（NSPasteboard 语义下同样会推进 changeCount）
    func clearContents()
}

struct SystemPasteboard: Pasteboard {
    var changeCount: Int { NSPasteboard.general.changeCount }

    @discardableResult
    func write(_ string: String) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.setString(string, forType: .string)
    }

    func clearContents() {
        NSPasteboard.general.clearContents()
    }
}

// MARK: - S4：复制后自动清除

/// 验证码复制后的自动清除（PRD §10.1 S4 / TECH_PLAN §4.7）
///
/// 安全语义（**关键**）：只在「剪贴板内容仍是本 App 刚写入的那一次」时才清除。
/// 判断依据是写入时的 `changeCount` —— 一旦期间有其他应用（或用户自己）写入，
/// changeCount 就会变化，此时**绝不触碰剪贴板**，避免误清用户的新内容。
///
/// 默认 30 秒（PRD S4）；开关留给后续设置页，当前默认开启。
@MainActor
final class ClipboardGuard {

    /// 生产单例（App 全局共用一份，保证计时与 changeCount 记录一致）
    static let shared = ClipboardGuard()

    /// PRD S4 默认值
    static let defaultDelay: TimeInterval = 30

    /// 是否启用自动清除（当前默认开；设置页落地后由用户控制）
    var isEnabled = true

    private let pasteboard: Pasteboard
    private let delay: TimeInterval

    /// 待清除记录：写入时的 changeCount（用于比对是否仍归我们所有）
    private(set) var pendingChangeCount: Int?

    private var clearTask: Task<Void, Never>?

    init(
        pasteboard: Pasteboard = SystemPasteboard(),
        delay: TimeInterval = ClipboardGuard.defaultDelay
    ) {
        self.pasteboard = pasteboard
        self.delay = delay
    }

    /// 复制验证码：成功则安排 N 秒后自动清除
    @discardableResult
    func copy(_ code: String) -> Bool {
        clearTask?.cancel()
        pendingChangeCount = nil

        guard pasteboard.write(code) else { return false }   // E1：失败交给调用方提示

        guard isEnabled else { return true }

        let token = pasteboard.changeCount
        pendingChangeCount = token
        scheduleClear(after: delay, expecting: token)
        return true
    }

    /// 到期回调 / 手动触发：仅当剪贴板仍是我们写入的那一次才清除。
    /// 返回是否真的清除了（测试与调试可用）。
    @discardableResult
    func clearIfStillOwned() -> Bool {
        guard let token = pendingChangeCount, token == pasteboard.changeCount else {
            pendingChangeCount = nil   // 已易主：放弃清除，不触碰剪贴板
            return false
        }
        pasteboard.clearContents()
        pendingChangeCount = nil
        return true
    }

    private func scheduleClear(after interval: TimeInterval, expecting token: Int) {
        clearTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(max(0, interval) * 1_000_000_000))
            guard !Task.isCancelled else { return }
            guard let self, self.pendingChangeCount == token else { return }
            self.clearIfStillOwned()
        }
    }
}
