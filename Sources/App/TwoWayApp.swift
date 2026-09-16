import SwiftUI

@main
struct TwoWayApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        // D2：隐藏系统标题栏，保留交通灯，标题栏区域由 WindowTitlebar 自绘（PRD G-03）
        .windowStyle(.hiddenTitleBar)
        // G-01：固定 400×700，不响应式重排（原 G-05「等比缩放」为 Demo 专有，不映射到原生）
        .windowResizability(.contentSize)
        .defaultSize(
            width: Token.Metrics.windowWidth,
            height: Token.Metrics.windowHeight
        )
    }
}
