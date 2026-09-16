import SwiftUI

/// 窗口根视图 —— 400×700 固定尺寸外壳
///
/// 当前为阶段 0 骨架：标题栏 + 占位内容。
/// 屏幕路由、状态层、服务层按 TECH_PLAN §6 分卡引入。
struct RootView: View {
    var body: some View {
        VStack(spacing: 0) {
            WindowTitlebar(title: "验证器") {
                EmptyView()
            }
            Divider1px()

            Spacer()

            VStack(spacing: 8) {
                Text("阶段 0 · 工程骨架")
                    .font(Token.Typography.body)
                    .foregroundStyle(Token.Palette.t2)
                Text("窗口 400×700 · 标题栏 52pt")
                    .font(Token.Typography.caption)
                    .foregroundStyle(Token.Palette.t3)
            }

            Spacer()
        }
        .frame(
            width: Token.Metrics.windowWidth,
            height: Token.Metrics.windowHeight
        )
        .background(Token.Palette.winBg)
        .ignoresSafeArea()
    }
}

#Preview {
    RootView()
}
