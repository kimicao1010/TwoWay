import SwiftUI

/// 窗口根视图（PRD G-01/G-03：400×732 固定尺寸 + 52pt 自绘标题栏）
struct RootView: View {
    /// 生产路径：真实钥匙串，service 用 Bundle ID（TECH_PLAN §4.2 D3）
    @State private var store = AccountStore(
        secrets: KeychainStore(service: Bundle.main.bundleIdentifier ?? "com.kimi.2way")
    )

    var body: some View {
        VStack(spacing: 0) {
            WindowTitlebar(title: "验证器") {
                EmptyView()
            }
            Divider1px()

            AccountListView(store: store) {
                // C2-5 / C2-6（添加账户）尚未实现，先占位
            }
        }
        .frame(
            width: Token.Metrics.windowWidth,
            height: Token.Metrics.windowHeight
        )
        .background(Token.Palette.winBg)
        // 窗口底角由我们自绘 12px（G-02）。
        // SwiftUI 会恒定给窗口加 32pt 隐形标题栏（frame = 内容 + 32），导致
        // 内容底边落在窗口中部、系统不会在那里画圆角 —— 必须自己裁。
        // 顶角仍由系统裁（≈13px），与 12px 差 1px，肉眼不可辨。
        .clipShape(RoundedRectangle(cornerRadius: Token.Metrics.windowCornerRadius))
        .background(WindowConfigurator())
        .ignoresSafeArea()
        .onAppear {
            try? store.load()
        }
    }
}

#Preview {
    RootView()
}
