import Foundation

/// 启动引导（幂等）
///
/// 两个入口都会触发：主窗口出现时、以及状态栏下拉首次打开时
/// （用户可能先关掉主窗口，只剩状态栏在用）。
/// 因此加载必须「只做一次」，且全局时钟必须与视图是否出现解耦。
@MainActor
enum AppBootstrap {

    private static var didLoad = false

    /// 幂等：全局时钟启动 + 应用偏好生效 + 从加密钱包加载账户（第一次调用时才真正读盘）
    static func start(store: AccountStore, settings: AppSettings) throws {
        RingClock.shared.start()   // T5/T6：环与码文本共用同一时钟源
        settings.applyActivationPolicy()   // 隐藏 Dock 图标偏好（幂等）

        guard !didLoad else { return }
        didLoad = true
        try store.load()

        #if DEBUG
        seedDemoDataIfRequested(store: store)
        #endif
    }

    #if DEBUG
    /// `--seed-demo`：向（隔离的）钱包灌入虚构账户，用于产出可公开的截图
    private static func seedDemoDataIfRequested(store: AccountStore) {
        guard DebugFlags.seedsDemoData, store.accounts.isEmpty else { return }
        for demo in DebugFlags.demoAccounts {
            try? store.add(
                displayName: demo.displayName,
                issuer: demo.issuer,
                secretBase32: demo.secretBase32
            )
        }
    }
    #endif
}
