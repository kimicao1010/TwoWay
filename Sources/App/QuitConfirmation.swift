import AppKit

/// 退出二次确认（PRD R13）
///
/// 覆盖**所有**退出路径：⌘Q、菜单栏「2way ▸ Quit 2way」、「⋯ → 退出 2way」、
/// 状态栏面板里的「退出」—— 它们最终都走 `NSApplication.terminate(_:)` → 本回调。
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let isMainWindowVisible = MainWindowRegistry.window?.isVisible ?? false
        #if DEBUG
        RowTrace.log(
            "quit requested mainWindowVisible=\(isMainWindowVisible) "
            + "visibleWindows=\(sender.windows.filter { $0.isVisible && !$0.isSheet }.count)"
        )
        #endif
        guard QuitConfirmationPolicy.shouldConfirm(isMainWindowVisible: isMainWindowVisible) else {
            return .terminateNow
        }
        return confirmQuit() ? .terminateNow : .terminateCancel
    }

    /// 同步模态确认框：默认按钮是**取消**（回车不会误退出），Esc 同样取消
    private func confirmQuit() -> Bool {
        let alert = NSAlert()
        alert.messageText = "确定要退出 2way 吗？"
        alert.informativeText = "退出后菜单栏取码将不可用。账户数据已加密保存，重新打开即可继续使用。"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "退出")
        alert.addButton(withTitle: "取消")
        alert.buttons.last?.keyEquivalent = "\r"   // 安全默认：回车 = 取消
        return alert.runModal() == .alertFirstButtonReturn
    }
}

/// 何时需要二次确认（纯逻辑，可单测）
enum QuitConfirmationPolicy {

    /// 只在该确认时确认：**主窗口开着**说明用户正在应用里操作，⌘Q 多半是误触；
    /// 主窗口已关（只在菜单栏驻留）时的退出是明确意图，不再拦一道。
    static func shouldConfirm(isMainWindowVisible: Bool) -> Bool {
        isMainWindowVisible
    }
}
