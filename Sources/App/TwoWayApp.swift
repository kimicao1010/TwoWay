import SwiftUI

@main
struct TwoWayApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        // D2：隐藏系统标题栏，保留交通灯，标题栏区域由 WindowTitlebar 自绘（PRD G-03）
        //
        // ⚠️ .windowResizability(.contentSize) 不能删（C0-3 实测）：
        //    删掉后 SwiftUI 会给 styleMask 补回 .resizable 并把窗口顶回 732
        //    （700 内容 + 32 隐形标题栏），WindowConfigurator 的 setFrame 打不赢。
        //    保留它 + Configurator 补 fullSizeContentView / setFrame 才能收敛到 400×700。
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultSize(
            width: Token.Metrics.windowWidth,
            height: Token.Metrics.windowHeight
        )
    }
}
