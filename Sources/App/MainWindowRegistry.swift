import AppKit

/// 主窗口登记表（DR-02：状态栏「打开主窗口」必须**复用**已有窗口，而不是每次新建）
///
/// 为什么需要它（两个机制缺一不可）：
/// - `WindowGroup` + `openWindow(id:)` 的语义是**每次调用都新建窗口**（WindowGroup 为多窗口/
///   多文档设计）→ 用户实测「点一次多一个窗」，即使主窗口还开着；
/// - 单实例 scene `Window` 解决了重复，但它的 `openWindow` 在窗口**已存在**时不会把它带到前台。
///
/// 于是：scene 用 `Window` 兜住「不重复」，这里登记实例以便点击时能主动前置。
@MainActor
enum MainWindowRegistry {

    private(set) static weak var window: NSWindow?

    /// 由 `WindowConfigurator` 在窗口挂载时登记（当前全仓只有主窗口用它）
    ///
    /// ⚠️ **刻意不在窗口关闭时清空引用**：关闭走的是 AppKit `NSWindow.close()`（见 `CloseWindowMenu`），
    /// SwiftUI 并不知道场景已空 —— 此时单实例 `Window` 的 `openWindow(id:)` 是**空操作**，
    /// 结果「关窗后点状态栏什么都不会出现」。保留引用后用 `makeKeyAndOrderFront` 重新显示，
    /// 才是可靠的重开路径（`close()` 只是把窗口 order out，对象仍在；真被释放时 weak 自动变 nil，
    /// 此时再回落到 `openWindow`）。
    static func register(_ window: NSWindow) {
        self.window = window
    }
}

/// 「打开主窗口」的目标决策（纯逻辑，可单测）
enum MainWindowPolicy {

    enum Action: Equatable {
        /// 已有主窗口对象（无论当前是否可见）→ 前置 / 重新显示，**不新建**
        case focusExisting(deminiaturize: Bool)
        /// 确实没有窗口对象（首次启动前 / 对象已被释放）→ 请求系统打开
        case openNew
    }

    static func action(hasExistingWindow: Bool, isMiniaturized: Bool) -> Action {
        guard hasExistingWindow else { return .openNew }
        return .focusExisting(deminiaturize: isMiniaturized)
    }
}
