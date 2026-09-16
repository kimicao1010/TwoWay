import AppKit
import SwiftUI

/// 标题栏（PRD G-03）
///
/// 高 52pt；标题居中 13pt Medium；右侧为上下文操作区；
/// 左侧在交通灯之后可放「返回」等前导操作（子页面用）。
/// 系统交通灯由 `.windowStyle(.hiddenTitleBar)` 保留并由系统绘制，
/// 本视图只负责让开它的位置 —— 不重绘交通灯。
///
/// 用 ZStack 而非 HStack 承载标题：这样标题始终在窗口几何中心，
/// 不受右侧操作区实际宽度影响（Demo 用 flex:1 + 等宽左右块达成同样效果）。
struct WindowTitlebar<Trailing: View, Leading: View>: View {
    let title: String
    @ViewBuilder var leading: () -> Leading
    @ViewBuilder var trailing: () -> Trailing

    init(
        title: String,
        @ViewBuilder leading: @escaping () -> Leading,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.title = title
        self.leading = leading
        self.trailing = trailing
    }

    /// 无前导操作的常用形态（列表页等）
    init(title: String, @ViewBuilder trailing: @escaping () -> Trailing) where Leading == EmptyView {
        self.init(title: title, leading: { EmptyView() }, trailing: trailing)
    }

    var body: some View {
        ZStack {
            Text(title)
                .font(Token.Typography.windowTitle)
                .foregroundStyle(Token.Palette.tTitle)
                .kerning(0.2)

            HStack(spacing: 0) {
                // D10：系统交通灯已隐藏，无需为其预留空间
                leading()
                Spacer(minLength: 0)
                trailing()
                    .frame(minWidth: Token.Metrics.titlebarTrailingMinWidth, alignment: .trailing)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: Token.Metrics.titlebarHeight)
        .padding(.horizontal, Token.Metrics.titlebarHPadding)
        .background(Token.Palette.titlebar)
        // 无系统标题栏后，用原生拖拽区让窗口可拖动（不阻挡上层按钮/菜单的点击）
        .background(WindowDragArea())
    }
}

/// 窗口拖拽区（D10）：无系统标题栏时，按住自绘标题栏空白处即可拖动窗口。
///
/// 用 `NSWindow.performDrag(with:)` 走 AppKit 原生拖动（含吸附、多显示器处理）。
/// 放在背景层：上层是可交互的按钮/菜单，空白处的点击才会落到这里。
struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        DraggableView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class DraggableView: NSView {
        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
    }
}

/// 子页面返回按钮（问题反馈：详情页原先没有退出路径）
struct TitlebarBackButton: View {
    var action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.left")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(hovering ? Token.Palette.t1 : Token.Palette.t2)
                .frame(width: 28, height: 28)
                .background(hovering ? Token.Palette.surface : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("返回")
    }
}

/// 1px 分隔线（PRD §8.1 `--divider`）
struct Divider1px: View {
    var body: some View {
        Rectangle()
            .fill(Token.Palette.divider)
            .frame(height: 1)
    }
}
