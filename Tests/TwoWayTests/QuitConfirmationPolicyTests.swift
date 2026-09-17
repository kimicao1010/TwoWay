import Foundation
import Testing

@testable import TwoWay

/// R13：退出二次确认的触发条件
struct QuitConfirmationPolicyTests {

    @Test("主窗口开着 → 需要确认（此时 ⌘Q 多为误触）")
    func confirmsWhenMainWindowVisible() {
        #expect(QuitConfirmationPolicy.shouldConfirm(isMainWindowVisible: true))
    }

    @Test("主窗口已关（仅菜单栏驻留）→ 直接退出，不再拦一道")
    func doesNotConfirmWhenWindowClosed() {
        #expect(QuitConfirmationPolicy.shouldConfirm(isMainWindowVisible: false) == false)
    }
}
