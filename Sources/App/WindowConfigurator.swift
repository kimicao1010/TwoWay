import SwiftUI
import AppKit

/// 拿到宿主 `NSWindow` 做系统层配置（D2 路线：保留系统交通灯，仅隐藏标题栏底）
///
/// ⚠️ 时序坑（C0-3 实测）：在 `makeNSView` 里 `DispatchQueue.main.async` 取
/// `view.window` 是**拿不到**的 —— 此时视图尚未挂进窗口，`updateNSView`
/// 又不会因无状态变化而再次调用，配置等于从未执行。
/// 必须用 `viewDidMoveToWindow` 钩子，它在视图挂进窗口的那一刻被调用。
///
/// ⚠️ 窗口高度坑（C0-3 实测，见 TECH_PLAN §11 RK7）：
/// `.hiddenTitleBar` 只是把标题栏变透明，**32pt 的标题栏区域仍参与窗口尺寸计算**，
/// 所以窗口 frame 是 732 = 700 内容 + 32 隐形标题栏。
/// 在 `viewDidMoveToWindow` 里补 `.fullSizeContentView` 后用 `setFrame(700)`
/// 会被 SwiftUI 的下一轮布局顶回 732（实测 +0.5s / +1.5s / +2.5s 反复 assert 均失败），
/// `contentMin/MaxSize` 钳制也无效 —— SwiftUI 每次布局都按「内容理想尺寸 + 标题栏高」
/// 重算 frame。**结论：走系统标题栏路线（D2 方案 A）拿不到 400×700 整。**
struct WindowConfigurator: NSViewRepresentable {
    /// 是否允许拖拽窗口背景移动窗口。
    /// 默认 false：列表行上有左滑手势，背景拖拽会抢手势。
    var movableByBackground = false
    /// 是否允许缩放。PRD G-01 固定尺寸，应为 false。
    var resizable = false

    func makeNSView(context: Context) -> NSView {
        let view = WindowAccessorView()
        view.onWindowMoved = { [weak view] window in
            guard view != nil else { return }
            self.configure(window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let window = nsView.window { configure(window) }
    }

    private func configure(_ window: NSWindow) {
        // 隐藏标题栏底色，让自绘标题栏直接顶到窗口上沿（PRD G-03）
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none

        // 让内容延伸进标题栏区域（否则内容下方会空出 32pt）
        if !window.styleMask.contains(.fullSizeContentView) {
            window.styleMask.insert(.fullSizeContentView)
        }

        window.isMovableByWindowBackground = movableByBackground

        // 固定尺寸窗口：关掉缩放，zoom（绿色）按钮随之失效
        if resizable {
            window.styleMask.insert(.resizable)
        } else {
            window.styleMask.remove(.resizable)
        }
        window.standardWindowButton(.zoomButton)?.isEnabled = resizable
        window.standardWindowButton(.zoomButton)?.alphaValue = resizable ? 1 : 0.4

        // 让 SwiftUI 层完全接管绘制；背景色交给根视图的 .background
        window.backgroundColor = NSColor.clear
        window.isOpaque = false
    }
}

/// 只为拿 window 而存在的空视图
private final class WindowAccessorView: NSView {
    var onWindowMoved: ((NSWindow) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window { onWindowMoved?(window) }
    }
}
