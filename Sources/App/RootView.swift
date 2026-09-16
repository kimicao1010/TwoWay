import SwiftUI

/// 窗口根视图（PRD G-01/G-03：400×732 固定尺寸 + 52pt 自绘标题栏）
///
/// 屏幕路由由 `AppRouter` 驱动（TECH_PLAN §3）；共享 Toast 渲染在本层，
/// 列表（复制反馈）与添加页（已添加提示）共用同一个 `ToastCenter`。
struct RootView: View {
    /// 生产路径：真实钥匙串，service 用 Bundle ID（TECH_PLAN §4.2 D3）
    @State private var store = AccountStore(
        secrets: KeychainStore(service: Bundle.main.bundleIdentifier ?? "com.kimi.2way")
    )
    @State private var router = AppRouter()
    @State private var toast = ToastCenter()
    /// U3：DEBUG 调试切屏用（--debug-import）
    @State private var debugInitialMethod: AddAccountView.Method = .manual

    var body: some View {
        ZStack {
            switch router.screen {
            case .list:
                listScreen
                    .transition(.opacity)

            case .addAccount:
                AddAccountView(
                    store: store,
                    toast: toast,
                    onCancel: { show(.list) },
                    onAdded: { name in
                        show(.list)
                        toast.show("已添加「\(name)」")
                    },
                    onImported: { count, skipped in
                        show(.list)
                        if skipped > 0 {
                            toast.show("已导入 \(count) 个账户（\(skipped) 个 HOTP 账户不受支持已跳过）")
                        } else {
                            toast.show("已导入 \(count) 个账户")
                        }
                    },
                    initialMethod: debugInitialMethod
                )
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: Token.Motion.screenTransition), value: router.screen)
        // R9/E8：切屏时全部行复位
        .overlay(alignment: .bottom) {
            if let current = toast.current {
                ToastView(message: current.message)
                    .padding(.bottom, 44)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(.easeOut(duration: 0.2), value: toast.current)
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
            // U3：开发期调试切屏入口（仅 DEBUG 生效）
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--debug-add") {
                router.screen = .addAccount
            }
            if ProcessInfo.processInfo.arguments.contains("--debug-import") {
                router.screen = .addAccount
                debugInitialMethod = .importImage
            }
            #endif
        }
    }

    // MARK: 屏幕

    private var listScreen: some View {
        VStack(spacing: 0) {
            WindowTitlebar(title: "验证器") {
                EmptyView()
            }
            Divider1px()

            AccountListView(
                store: store,
                toast: toast,
                onAdd: { show(.addAccount) },
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
    }

    private func show(_ screen: AppRouter.Screen) {
        store.setOpenedRow(nil)   // R9/E8：离开列表屏时行复位
        router.screen = screen
    }
}

#Preview {
    RootView()
}
