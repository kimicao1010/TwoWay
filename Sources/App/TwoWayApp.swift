import SwiftUI

@main
struct TwoWayApp: App {

    /// 主窗口 scene id（状态栏「打开主窗口」用它唤回；调试参数也用它开预览窗）
    static let mainWindowID = "main"
    #if DEBUG
    /// 状态栏面板的预览窗口 id（仅调试：面板本体属于系统菜单栏，无法用截图工具定位）
    static let menuBarPreviewWindowID = "menubar-preview"
    #endif

    /// 生产路径：加密文件存储（D9，用户决策弃用 Keychain —— 本机钥匙串 ACL
    /// 逐条弹授权框不可接受）。安全边界见 `EncryptedStore` 类注释。
    ///
    /// 由 App 层持有：主窗口与状态栏下拉**共用同一实例**（单一数据源，避免双源不一致）
    @State private var store = AccountStore(secrets: EncryptedStore(directory: Self.walletDirectory))

    /// 应用偏好（隐藏 Dock 图标等），主窗口与状态栏共用
    @State private var settings = AppSettings()

    /// 钱包目录：生产为默认目录；DEBUG 下 `--wallet-dir` 可指向隔离目录（截图用虚构数据）
    private static var walletDirectory: URL? {
        #if DEBUG
        return DebugFlags.walletDirectoryOverride
        #else
        return nil
        #endif
    }

    var body: some Scene {
        WindowGroup(id: Self.mainWindowID) {
            RootView(store: store, settings: settings)
        }
        // D2：隐藏系统标题栏，保留交通灯，标题栏区域由 WindowTitlebar 自绘（PRD G-03）
        //
        // 窗口总高 = 内容最小高度(700) + 32pt 隐形标题栏 = 732（PRD G-01 / D8），
        // 多出的 32pt 由列表区吸收（根视图 minHeight 可伸缩）。
        //
        // ⚠️ .windowResizability(.contentSize) 不能删（C0-3 实测）：
        //    删掉后 SwiftUI 会给 styleMask 补回 .resizable，窗口尺寸不再受控。
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultSize(
            width: WindowMetrics.width,
            height: Token.Metrics.windowHeight
        )

        // 状态栏常驻（P2：「菜单栏常驻与快速取码」提前落地）
        //
        // `.menuBarExtraStyle(.window)` = 点图标弹出一个可承载输入控件的面板
        // （`.menu` 那种原生菜单无法放搜索框，故必须用 window 形态）。
        MenuBarExtra {
            MenuBarView(store: store, settings: settings)
        } label: {
            Image("StatusBarIcon")
                .accessibilityLabel("2way 验证码")
        }
        .menuBarExtraStyle(.window)

        // 偏好设置（⌘, ；主窗口「⋯」菜单也有入口）
        Settings {
            SettingsView(settings: settings)
        }

        #if DEBUG
        // 仅调试：把状态栏面板放到普通窗口里，便于截图/回归（菜单栏面板无法按窗口 ID 截取）。
        // ⚠️ `Window` scene 默认会随 App 启动一起打开 —— 由宿主视图在非调试启动时自动关掉，
        //    否则每次调试构建都会多出一个空窗。
        Window("状态栏面板预览", id: Self.menuBarPreviewWindowID) {
            MenuBarPreviewHost(store: store, settings: settings)
        }
        .defaultSize(width: 300, height: 400)
        .windowResizability(.contentSize)   // 窗口贴合面板内容（截图用于文档时更像真实面板）
        #endif
    }
}

#if DEBUG
/// 状态栏面板预览窗宿主（仅 `--debug-menubar` 启动时保留该窗）
private struct MenuBarPreviewHost: View {
    let store: AccountStore
    let settings: AppSettings
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        MenuBarView(store: store, settings: settings)
            .task {
                guard !ProcessInfo.processInfo.arguments.contains("--debug-menubar") else { return }
                dismissWindow(id: TwoWayApp.menuBarPreviewWindowID)
            }
    }
}
#endif
