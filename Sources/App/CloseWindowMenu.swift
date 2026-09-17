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
@MainActor
final class CloseWindowMenu: NSObject {

    /// 菜单项的 target 是弱引用，必须由我们持有强引用
    static let shared = CloseWindowMenu()

    /// 关闭当前窗口（`close()` 不等价于 `performClose` —— 后者会被按钮状态拦住）
    @objc func closeKeyWindow(_ sender: Any?) {
        let application = NSApplication.shared
        let target = application.keyWindow
            ?? application.mainWindow
            ?? application.windows.first { $0.isVisible && !$0.isSheet }
        target?.close()
    }

    /// 安装：把主菜单里「⌘W 且 action 为 performClose:」的项改指向我们的 action。
    /// 幂等，可重复调用（SwiftUI 有时会重建菜单）。
    @discardableResult
    static func install() -> Int {
        guard let mainMenu = NSApplication.shared.mainMenu else { return 0 }
        var patched = 0

        for menuItem in mainMenu.items {
            guard let submenu = menuItem.submenu else { continue }
            for item in submenu.items where isSystemCloseItem(item) {
                item.target = shared
                item.action = #selector(CloseWindowMenu.closeKeyWindow(_:))
                patched += 1
            }
        }
        return patched
    }

    /// 命中系统「Close」项：⌘W 且 action 是 `performClose:`
    static func isSystemCloseItem(_ item: NSMenuItem) -> Bool {
        guard item.keyEquivalent.lowercased() == "w",
              item.keyEquivalentModifierMask == .command
        else { return false }
        return item.action == #selector(NSWindow.performClose(_:))
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
