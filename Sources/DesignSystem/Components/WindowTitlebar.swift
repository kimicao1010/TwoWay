import SwiftUI

/// 标题栏（PRD G-03）
///
/// 高 52pt；标题居中 13pt Medium；右侧为上下文操作区。
/// 系统交通灯由 `.windowStyle(.hiddenTitleBar)` 保留并由系统绘制，
/// 本视图只负责让开它的位置 —— 不重绘交通灯。
///
/// 用 ZStack 而非 HStack 承载标题：这样标题始终在窗口几何中心，
/// 不受右侧操作区实际宽度影响（Demo 用 flex:1 + 等宽左右块达成同样效果）。
struct WindowTitlebar<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        ZStack {
            Text(title)
                .font(Token.Typography.windowTitle)
                .foregroundStyle(Token.Palette.tTitle)
                .kerning(0.2)

            HStack(spacing: 0) {
                // 让开系统交通灯
                Color.clear
                    .frame(width: Token.Metrics.trafficLightBlockWidth)
                Spacer(minLength: 0)
                trailing()
                    .frame(minWidth: Token.Metrics.titlebarTrailingMinWidth, alignment: .trailing)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: Token.Metrics.titlebarHeight)
        .padding(.horizontal, Token.Metrics.titlebarHPadding)
        .background(Token.Palette.titlebar)
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
