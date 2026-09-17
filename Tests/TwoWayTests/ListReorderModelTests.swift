import CoreGraphics
import Foundation
import Testing

@testable import TwoWay

/// DR-01 拖动会话：让位位移与落点判定（视图渲染依赖这套数学）
@MainActor
struct ListReorderModelTests {

    private let step: CGFloat = 84   // 行高 76 + 间距 8
    private func makeModel(count: Int = 5) -> ListReorderModel {
        let model = ListReorderModel()
        model.begin(id: UUID(), originIndex: 0, step: step, count: count)
        return model
    }

    @Test("未开始时：无位移、无落点、不产生移动")
    func idleModel() {
        let model = ListReorderModel()
        #expect(model.isActive == false)
        #expect(model.shift(forRowAt: 0) == 0)
        #expect(model.landingIndex == nil)
        #expect(model.hasPendingMove == false)
    }

    @Test("向下拖：中间的行整体上移一个步长，拖动行自身与外围行为 0")
    func shiftWhenMovingDown() {
        let model = makeModel()
        // 第 0 行往下拖 2 格 → 落点 2
        model.update(translationY: step * 2)

        #expect(model.landingIndex == 2)
        #expect(model.shift(forRowAt: 0) == 0)      // 拖动行自身由 offsetY 承载
        #expect(model.shift(forRowAt: 1) == -step)  // 被让位
        #expect(model.shift(forRowAt: 2) == -step)  // 被让位
        #expect(model.shift(forRowAt: 3) == 0)
        #expect(model.shift(forRowAt: 4) == 0)
    }

    @Test("向上拖：中间的行整体下移一个步长")
    func shiftWhenMovingUp() {
        let model = ListReorderModel()
        model.begin(id: UUID(), originIndex: 4, step: step, count: 5)
        model.update(translationY: -step * 2)       // 第 4 行往上拖 2 格 → 落点 2

        #expect(model.landingIndex == 2)
        #expect(model.shift(forRowAt: 4) == 0)
        #expect(model.shift(forRowAt: 2) == step)
        #expect(model.shift(forRowAt: 3) == step)
        #expect(model.shift(forRowAt: 1) == 0)
        #expect(model.shift(forRowAt: 0) == 0)
    }

    @Test("不足半格：落点不变 → 无让位、不提交")
    func belowHalfStep() {
        let model = makeModel()
        model.update(translationY: 30)

        #expect(model.landingIndex == 0)
        #expect(model.hasPendingMove == false)
        #expect(model.shift(forRowAt: 1) == 0)
        #expect(model.shift(forRowAt: 2) == 0)
    }

    @Test("越过半格即产生落点与让位（消除首格死区）")
    func halfStepCrosses() {
        let model = makeModel()
        model.update(translationY: step / 2)

        #expect(model.landingIndex == 1)
        #expect(model.hasPendingMove)
        #expect(model.shift(forRowAt: 1) == -step)
        #expect(model.shift(forRowAt: 2) == 0)
    }

    @Test("end() 清空会话，后续不再参与渲染")
    func endResets() {
        let model = makeModel()
        model.update(translationY: step * 2)
        model.end()

        #expect(model.isActive == false)
        #expect(model.landingIndex == nil)
        #expect(model.shift(forRowAt: 1) == 0)
        #expect(model.hasPendingMove == false)
    }
}
