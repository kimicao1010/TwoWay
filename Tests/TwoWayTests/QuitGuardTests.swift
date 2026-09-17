import Foundation
import Testing

@testable import TwoWay

/// R13：⌘Q 防误触（提示 → 第二次退出；非激活态直接退出）
@MainActor
struct QuitGuardTests {

    // MARK: 纯策略

    @Test("主窗口未激活 → 直接退出，不提示")
    func quitsWhenWindowInactive() {
        #expect(
            QuitGuardPolicy.action(isMainWindowActive: false, isAwaitingSecondPress: false) == .quit
        )
        #expect(
            QuitGuardPolicy.action(isMainWindowActive: false, isAwaitingSecondPress: true) == .quit
        )
    }

    @Test("主窗口激活 + 首次 ⌘Q → 只给提示")
    func showsHintOnFirstPress() {
        #expect(
            QuitGuardPolicy.action(isMainWindowActive: true, isAwaitingSecondPress: false) == .showHint
        )
    }

    @Test("主窗口激活 + 提示可见期间再按 → 退出")
    func quitsOnSecondPress() {
        #expect(
            QuitGuardPolicy.action(isMainWindowActive: true, isAwaitingSecondPress: true) == .quit
        )
    }

    // MARK: 状态机（注入依赖，不真的退出/不真的 sleep）

    private func makeGuard() -> (QuitGuard, () -> Int) {
        let guardInstance = QuitGuard()
        var quitCount = 0
        guardInstance.quit = { quitCount += 1 }
        guardInstance.wait = { _ in }            // 立即返回：提示不会自动消失，便于断言
        return (guardInstance, { quitCount })
    }

    @Test("激活态：第一次 ⌘Q 只提示、不退出")
    func firstPressOnlyShowsHint() {
        let (guardInstance, quitCount) = makeGuard()
        guardInstance.isMainWindowActive = { true }

        guardInstance.handleCommandQ()

        #expect(guardInstance.isAwaitingSecondPress)
        #expect(quitCount() == 0)
    }

    @Test("激活态：第二次 ⌘Q 退出，并收起提示")
    func secondPressQuits() {
        let (guardInstance, quitCount) = makeGuard()
        guardInstance.isMainWindowActive = { true }

        guardInstance.handleCommandQ()   // 第一次：提示
        guardInstance.handleCommandQ()   // 第二次：退出

        #expect(quitCount() == 1)
        #expect(guardInstance.isAwaitingSecondPress == false)
    }

    @Test("未激活：⌘Q 直接退出，不提示")
    func inactiveQuitsImmediately() {
        let (guardInstance, quitCount) = makeGuard()
        guardInstance.isMainWindowActive = { false }

        guardInstance.handleCommandQ()

        #expect(quitCount() == 1)
        #expect(guardInstance.isAwaitingSecondPress == false)
    }

    @Test("显式退出入口（状态栏 / 菜单）从不需要二次确认")
    func explicitQuitSkipsHint() {
        let (guardInstance, quitCount) = makeGuard()
        guardInstance.isMainWindowActive = { true }

        guardInstance.quitImmediately()

        #expect(quitCount() == 1)
        #expect(guardInstance.isAwaitingSecondPress == false)
    }
}
