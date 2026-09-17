import AppKit

/// 应用委托：只做一件事 —— 确保退出请求真的走到系统回调（便于取证与兜底）
///
/// 存在的理由：⌘Q 由 `AppShortcutMonitor` 在事件监听层拦截后调用 `terminate`，
/// 我们需要一个明确的观测点确认「退出请求是否抵达 AppKit」，否则只能看到「进程还活着」而不知卡在哪。
/// 行为本身不做二次确认（防误触由 `QuitGuard` 的窗体内提示承担，R13）。
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        #if DEBUG
        RowTrace.log("applicationShouldTerminate 抵达（返回 terminateNow）")
        #endif
        return .terminateNow
    }
}
