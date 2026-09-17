import AppKit

/// 应用级快捷键监听：**⌘W 关窗 / ⌘Q 退出**（在事件进入菜单系统之前拦下）
///
/// 为什么不走菜单项：本应用把系统窗口按钮隐藏了（D10），此后
/// - `Window ▸ Close`（⌘W）被 SwiftUI 判为 **disabled**，而**禁用项会吞掉自己的快捷键**；
/// - 主窗口关闭后（仅菜单栏驻留）`Quit 2way`（⌘Q）同样被判为不可用，⌘Q **毫无反应**；
/// - 且 `Window` 菜单由 AppKit **懒加载**，启动期补丁会打空（实测 `patched=0`）。
///
/// 这些状态随 SwiftUI 版本/场景类型变动，不可控也不可依赖。因此统一改为本地监听：
/// 事件交给应用后、菜单系统取用之前就拦下并处理，**与菜单项的启用状态彻底解耦**。
///
/// 监听器只在应用自己的事件流里生效（不影响其他 App）；命中即吞掉事件，避免二次触发。
@MainActor
enum AppShortcutMonitor {

    private static var monitor: Any?

    /// 幂等安装
    static func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard flags == .command,
                  let key = event.charactersIgnoringModifiers?.lowercased()
            else { return event }

            switch key {
            case "w":
                MainActor.assumeIsolated { CloseWindowMenu.shared.closeKeyWindow(nil) }
                return nil
            case "q":
                // 走标准退出流程：应用委托里的二次确认（R13）依然生效
                MainActor.assumeIsolated { NSApplication.shared.terminate(nil) }
                return nil
            default:
                return event
            }
        }
    }
}
