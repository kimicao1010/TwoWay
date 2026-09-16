import SwiftUI

@main
struct TwoWayApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
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
            width: Token.Metrics.windowWidth,
            height: Token.Metrics.windowHeight
        )
    }
}
