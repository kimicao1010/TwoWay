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

            AccountListView(
                store: store,
                onAdd: {
                    // C2-5 / C2-6（添加账户）尚未实现，先占位
                },
                onDetail: { account in
                    // R7：切屏到详情页在 C2-7 接入，此处先记录选中项
                    store.selectedAccountID = account.id
                },
                onDelete: { account in
                    // R8：切屏 + 260ms 弹删除确认在 C2-8 接入，此处先记录选中项
                    store.selectedAccountID = account.id
                }
            )
        }
        .frame(minWidth: Token.Metrics.windowWidth, maxWidth: Token.Metrics.windowWidth)
        .frame(minHeight: Token.Metrics.designedContentHeight, maxHeight: .infinity)
        .background(Token.Palette.winBg)
        // 窗口底角由我们自绘 12px（G-02）。
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
