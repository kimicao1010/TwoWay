import AppKit
import Observation
import SwiftUI

/// ⌘Q 的防误触守卫（R13）
///
/// 行为（用户实测决策 2026-09-17）：
/// - **主窗口处于激活态**时按 ⌘Q → **不退出**，在窗体内浮出一条小提示「按住 ⌘Q 键即可退出」；
///   提示可见期间**再按一次 ⌘Q** → 退出。
/// - 主窗口未激活（例如焦点在状态栏面板）→ 直接退出，不拦。
/// - 状态栏面板 / 菜单里的「退出」是显式点击 → 走 `quitImmediately()`，从不确认。
///
/// 提示只在窗体内渲染（不弹系统对话框）；提示消失后 ⌘Q 会重新走一遍上述流程。
@MainActor
@Observable
final class QuitGuard {

    static let shared = QuitGuard()

    /// 小提示是否正在显示（= 正在等待第二次 ⌘Q）
    private(set) var isAwaitingSecondPress = false

    // 依赖注入点（便于单测；生产用下面的默认实现）
    /// 主窗口是否处于激活态
    var isMainWindowActive: () -> Bool = { MainWindowRegistry.window?.isKeyWindow ?? false }
    /// 真正退出
    ///
    /// ⚠️ 必须**延迟一个 runloop**再调 `terminate`：⌘Q 来自 `NSEvent` 本地监听器，
    /// 在监听回调栈里同步终止会被吞掉（实测：日志显示已调用 terminate，进程仍存活）。
    var quit: () -> Void = {
        DispatchQueue.main.async { NSApplication.shared.terminate(nil) }
    }
    /// 等待（提示停留时长），可注入以免测试真的 sleep
    var wait: (TimeInterval) async throws -> Void = {
        try await Task.sleep(nanoseconds: UInt64($0 * 1_000_000_000))
    }

    private var hideTask: Task<Void, Never>?
    private let duration: TimeInterval = Token.Motion.quitHintDuration

    /// ⌘Q 被按下（键盘路径，事件已在 `AppShortcutMonitor` 里被拦下并吞掉）
    func handleCommandQ() {
        switch QuitGuardPolicy.action(
            isMainWindowActive: isMainWindowActive(),
            isAwaitingSecondPress: isAwaitingSecondPress
        ) {
        case .quit:
            dismissHint()
            #if DEBUG
            RowTrace.log("QuitGuard → terminate")
            #endif
            quit()
        case .showHint:
            showHint()
        }
    }

    /// 显式退出入口（状态栏面板 / ⋯ 菜单 / 菜单栏 Quit）：直接退出，不做防误触
    func quitImmediately() {
        dismissHint()
        quit()
    }

    /// 立即收起提示（提示停留期内未被再次按下时由定时器调用）
    func dismissHint() {
        hideTask?.cancel()
        hideTask = nil
        isAwaitingSecondPress = false
    }

    private func showHint() {
        hideTask?.cancel()
        isAwaitingSecondPress = true
        let waited = wait
        let seconds = duration
        hideTask = Task { [weak self] in
            do { try await waited(seconds) } catch { return }
            guard !Task.isCancelled else { return }
            self?.isAwaitingSecondPress = false
        }
    }
}

/// 何时退出、何时只给提示（纯逻辑，可单测）
enum QuitGuardPolicy {

    enum Action: Equatable {
        /// 直接退出
        case quit
        /// 留在应用内，浮出「按住 ⌘Q 键即可退出」小提示
        case showHint
    }

    static func action(isMainWindowActive: Bool, isAwaitingSecondPress: Bool) -> Action {
        guard isMainWindowActive else { return .quit }        // 主窗口未激活 → 不需要二次确认
        return isAwaitingSecondPress ? .quit : .showHint      // 激活态：第一次提示，第二次退出
    }
}

/// ⌘Q 防误触提示（窗体内浮层，不弹系统对话框）
///
/// 规格对齐用户提供的设计图：深色圆角小条 + 白色加粗文字。
struct QuitHintView: View {
    var body: some View {
        Text("按住 ⌘Q 键即可退出")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Token.Palette.t1)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Token.Palette.actionDetail)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.45), radius: 12, y: 4)
            .allowsHitTesting(false)   // 浮层不拦截鼠标
    }
}
