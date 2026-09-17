import Foundation
import Testing

@testable import TwoWay

/// DR-02：「状态栏 → 打开主窗口」的目标决策（不得重复建窗）
struct MainWindowPolicyTests {

    @Test("没有主窗口 → 请求打开（首次启动 / 已关闭）")
    func openWhenAbsent() {
        #expect(MainWindowPolicy.action(hasExistingWindow: false, isMiniaturized: false) == .openNew)
        #expect(MainWindowPolicy.action(hasExistingWindow: false, isMiniaturized: true) == .openNew)
    }

    @Test("已有主窗口 → 前置而不是新建（用户实测缺陷的回归护城河）")
    func focusWhenPresent() {
        #expect(
            MainWindowPolicy.action(hasExistingWindow: true, isMiniaturized: false)
                == .focusExisting(deminiaturize: false)
        )
    }

    @Test("已有但被最小化 → 前置前先还原")
    func deminiaturizeWhenNeeded() {
        #expect(
            MainWindowPolicy.action(hasExistingWindow: true, isMiniaturized: true)
                == .focusExisting(deminiaturize: true)
        )
    }

    @Test("任何情况下都不会在已有窗口时走 openNew（重复建窗的根因）")
    func neverOpensWhenPresent() {
        for miniaturized in [true, false] {
            let action = MainWindowPolicy.action(hasExistingWindow: true, isMiniaturized: miniaturized)
            if case .openNew = action {
                Issue.record("已有主窗口时不应请求新窗口（isMiniaturized=\(miniaturized)）")
            }
        }
    }
}
