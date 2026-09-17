import AppKit
import Foundation

/// 让 **⌘W 真正关闭窗口**（D10 的连带问题修复，2026-09-17）
///
/// 问题链（全部由探针实测确认，不是推测）：
/// 1. D10 为了「彻底去掉系统 chrome」，把窗口的关闭按钮做成不可见；
/// 2. **AppKit 会把不可见的标准按钮同时置为 disabled**（`isHidden = true` 与
///    `alphaValue = 0` 两种做法都会；我们再显式 `isEnabled = true` 也压不住 ——
///    探针读数恒为 `closeBtnHidden=false closeBtnEnabled=false`）；
/// 3. 而系统 File ▸ Close（⌘W）的 action 是 `NSWindow.performClose(_:)`，语义是
///    **「模拟点击关闭按钮」** —— 按钮 disabled 时它是**空操作**，于是 ⌘W 毫无反应。
///
/// 因此不再依赖按钮，而是把菜单项接管为 `close()`：该 action 不查按钮状态，
/// 窗口正常关闭（App 继续驻留菜单栏，可再从状态栏下拉或 Dock 唤出主窗口）。
///
/// ## v1.0.1 → v1.0.2 的再次失效与最终方案（探针实测）
///
/// 主窗口 scene 从 `WindowGroup` 改成单实例 `Window` 后，⌘W 又一次失效，两个原因叠加：
/// 1. Close 项从 **File 菜单搬到了 `Window` 菜单**，而 **`Window` 菜单由 AppKit 懒加载**
///    （启动期实测 `menus=5` 但一个 ⌘W 项都没有）→ 启动期补丁静默打空（`patched=0`）；
/// 2. 该项被 SwiftUI 判为 **disabled**，而**禁用项会吞掉自己的快捷键**。
///
/// 结论：**不再把 ⌘W 的正确性挂在菜单项状态上**（菜单何时建、SwiftUI 如何校验都不可控），
/// 改为在事件进入菜单系统**之前**用本地监听器拦下 ⌘W 并吞掉 —— 菜单展开时的补丁保留为
/// best-effort（让鼠标路径尽量可用），但键盘路径由监听器独立保证。
@MainActor
final class CloseWindowMenu: NSObject, NSMenuItemValidation {

    /// 菜单项的 target 是弱引用，必须由我们持有强引用
    static let shared = CloseWindowMenu()

    /// 菜单展开监听器（见 `installMenuTrackingObserver`）
    private var menuObserver: NSObjectProtocol?

    /// 关闭当前窗口（`close()` 不等价于 `performClose` —— 后者会被按钮状态拦住）
    @objc func closeKeyWindow(_ sender: Any?) {
        let application = NSApplication.shared
        // 有模态弹窗（如退出确认）时不越权关窗
        guard application.modalWindow == nil else { return }
        let target = application.keyWindow
            ?? application.mainWindow
            ?? application.windows.first { $0.isVisible && !$0.isSheet }
        target?.close()
    }

    /// 安装：① 接管菜单项 ② 装上键盘监听。
    /// 幂等，可重复调用（SwiftUI 有时会重建菜单）。
    @discardableResult
    static func install() -> Int {
        AppShortcutMonitor.install()          // ⌘W / ⌘Q 的可靠路径（与菜单项状态解耦）
        shared.installMenuTrackingObserver()
        guard let mainMenu = NSApplication.shared.mainMenu else { return 0 }
        var patched = 0

        for menuItem in mainMenu.items {
            guard let submenu = menuItem.submenu else { continue }
            for item in submenu.items where isSystemCloseItem(item) {
                item.target = shared
                item.action = #selector(CloseWindowMenu.closeKeyWindow(_:))
                // ⚠️ 只改 target/action 不够：SwiftUI 会按「窗口关闭按钮是否可用」把
                // Window ▸ Close 判为 **disabled**，而**禁用项会吞掉自己的快捷键** ——
                // 这是 v1.0.1 的 ⌘W 失效根因（且 SwiftUI 每次刷新菜单都会把 isEnabled 覆盖回去）。
                item.isEnabled = true
                patched += 1
            }
        }
        #if DEBUG
        if DebugFlags.tracesDragEvents || patched == 0 {
            // 诊断：列出主菜单里所有 ⌘W 项的实测属性，看清为何未命中
            var details: [String] = ["menus=\(mainMenu.items.count)"]
            for menuItem in mainMenu.items {
                guard let submenu = menuItem.submenu else { continue }
                for item in submenu.items where item.keyEquivalent.lowercased() == "w" {
                    let mods = item.keyEquivalentModifierMask.rawValue
                    details.append(
                        "[\(menuItem.title) ▸ \(item.title)] mods=\(mods) "
                        + "action=\(item.action.map(NSStringFromSelector) ?? "nil") "
                        + "enabled=\(item.isEnabled) hidden=\(item.isHidden)"
                    )
                }
            }
            RowTrace.log("CloseWindowMenu.install patched=\(patched) \(details.joined(separator: " "))")
        }
        #endif
        return patched
    }

    /// 命中系统「关闭窗口」项：⌘W（含 `Close` 与 `Close All`）
    ///
    /// ⚠️ **不能**再要求 `action == performClose:`：主窗口 scene 从 `WindowGroup` 改成单实例
    /// `Window` 后，系统项的 action 变了（探针实测该条件不再命中，于是补丁静默失效）。
    /// 只按快捷键匹配，对系统实现的变化更鲁棒。
    static func isSystemCloseItem(_ item: NSMenuItem) -> Bool {
        item.keyEquivalent.lowercased() == "w" && item.keyEquivalentModifierMask == .command
    }

    /// 允许菜单项保持可用（否则 AppKit 会按关闭按钮状态把它判为 disabled，快捷键失效）
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        true
    }

    /// 菜单展开前再补一次补丁
    ///
    /// ⚠️ 必须这么做：**`Window` 菜单由 AppKit 懒加载** —— 启动时它里面是空的
    /// （实测 `menus=5` 但一个 ⌘W 项都没有），Close 项要等菜单首次展开才出现；
    /// 而 scene 从 `WindowGroup` 改成单实例 `Window` 后，Close 项恰好从 File 菜单搬到了
    /// Window 菜单，启动期补丁就再也打不上了（v1.0.1 的 ⌘W 失效根因之一）。
    /// 监听「菜单开始跟踪」在展开瞬间补打，避免菜单里出现一个灰掉的 Close。
    private func installMenuTrackingObserver() {
        guard menuObserver == nil else { return }
        menuObserver = NotificationCenter.default.addObserver(
            forName: NSMenu.didBeginTrackingNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                _ = CloseWindowMenu.install()
            }
        }
    }

    /// 仅调试用：取当前菜单里 ⌘W 那一项（探针据此模拟「按下 ⌘W」）
    static func currentCloseItem() -> NSMenuItem? {
        guard let mainMenu = NSApplication.shared.mainMenu else { return nil }
        for menuItem in mainMenu.items {
            guard let submenu = menuItem.submenu else { continue }
            for item in submenu.items where item.keyEquivalent.lowercased() == "w"
                && item.keyEquivalentModifierMask == .command {
                return item
            }
        }
        return nil
    }
}
