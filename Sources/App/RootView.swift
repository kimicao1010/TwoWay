import SwiftUI

/// 窗口根视图（PRD G-01/G-03：400×732 固定尺寸 + 52pt 自绘标题栏）
///
/// 屏幕路由由 `AppRouter` 驱动（TECH_PLAN §3）；共享 Toast 渲染在本层，
/// 列表（复制反馈）与添加页（已添加提示）共用同一个 `ToastCenter`。
struct RootView: View {
    /// 生产路径：加密文件存储（D9，用户决策弃用 Keychain —— 本机钥匙串 ACL
    /// 逐条弹授权框不可接受）。安全边界见 EncryptedStore 类注释。
    @State private var store = AccountStore(secrets: EncryptedStore())
    @State private var router = AppRouter()
    @State private var toast = ToastCenter()
    /// U3：DEBUG 调试切屏用（--debug-import）
    @State private var debugInitialMethod: AddAccountView.Method = .manual
    /// DEBUG：load 失败时把错误码亮在界面上（排查生产 Keychain 路径用）
    @State private var loadErrorText: String?

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

            case .detail:
                // E2：账户不存在（已删空 / 无选中）时回落列表
                if store.selectedAccount != nil {
                    AccountDetailView(
                        store: store,
                        toast: toast,
                        showsDeleteDialog: router.showsDeleteDialog,
                        onRequestDeleteDialog: { router.showsDeleteDialog = true },
                        onCancelDelete: { router.showsDeleteDialog = false },
                        onDeleted: { name in
                            show(.list)
                            toast.show("已删除「\(name)」")
                        }
                    )
                    .transition(.opacity)
                } else {
                    listScreen
                }
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
        .overlay(alignment: .top) {
            #if DEBUG
            if let loadErrorText {
                Text("load: \(loadErrorText)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Token.Palette.dangerText)
                    .padding(.top, 56)
            }
            #endif
        }
        .onAppear {
            do {
                try store.load()
                loadErrorText = nil
            } catch {
                #if DEBUG
                loadErrorText = String(describing: error)
                #endif
            }
            // U3：开发期调试切屏入口（仅 DEBUG 生效）
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--debug-add") {
                router.screen = .addAccount
            }
            if ProcessInfo.processInfo.arguments.contains("--debug-import") {
                router.screen = .addAccount
                debugInitialMethod = .importImage
            }
            // --debug-detail [--debug-detail-dialog]：直进详情屏（可带删除确认弹窗）
            if ProcessInfo.processInfo.arguments.contains("--debug-detail") {
                store.selectedAccountID = store.accounts.first?.id
                router.screen = .detail
                router.showsDeleteDialog = ProcessInfo.processInfo.arguments.contains("--debug-detail-dialog")
            }
            // --debug-import-file <path>：启动即模拟「拖入图片解码 → 导入」完整链路
            // （手工回归用：免掉无障碍权限下无法程序化拖放的局限）
            if let index = ProcessInfo.processInfo.arguments.firstIndex(of: "--debug-import-file"),
               index + 1 < ProcessInfo.processInfo.arguments.count {
                let path = ProcessInfo.processInfo.arguments[index + 1]
                importImageForDebug(at: path)
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
                    // R7：行复位 + 切详情屏
                    store.selectedAccountID = account.id
                    showDetail(autoDeleteConfirm: false)
                },
                onDelete: { account in
                    // R8：切详情屏后 260ms 自动弹删除确认
                    store.selectedAccountID = account.id
                    showDetail(autoDeleteConfirm: true)
                }
            )
        }
    }

    private func show(_ screen: AppRouter.Screen) {
        store.setOpenedRow(nil)   // R9/E8：离开列表屏时行复位
        router.screen = screen
    }

    /// R7/R8：进入详情。R8 在切屏动画（260ms）后自动弹删除确认（PRD §7.2）
    private func showDetail(autoDeleteConfirm: Bool) {
        store.setOpenedRow(nil)
        router.showsDeleteDialog = false
        router.screen = .detail
        if autoDeleteConfirm {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(Token.Motion.deleteDialogDelay * 1_000_000_000))
                guard router.screen == .detail else { return }
                router.showsDeleteDialog = true
            }
        }
    }

    #if DEBUG
    /// 调试链路：与 ImportImageView 相同的「解码 → resolve → 入库」路径
    private func importImageForDebug(at path: String) {
        guard
            let image = NSImage(contentsOfFile: path),
            let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { return }
        let strings = (try? QRImageDecoder.decode(in: cgImage)) ?? []
        let fields: [QRImport.PrefilledAccount]
        switch QRImport.resolve(strings) {
        case .account(let single):
            fields = [single]
        case .migrated(let multiple, _):
            fields = multiple
        default:
            return
        }
        for field in fields {
            try? store.add(
                displayName: field.displayName,
                issuer: field.issuer,
                secretBase32: field.secretBase32,
                parameters: field.parameters
            )
        }
    }
    #endif
}

#Preview {
    RootView()
}
