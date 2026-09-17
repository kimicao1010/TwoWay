import CoreGraphics
import Foundation
import Testing

@testable import TwoWay

/// DR-01 拖动排序：方向分流与插入位换算（纯逻辑）
struct ReorderLogicTests {

    // MARK: 方向分流（竖直=排序 / 水平=左滑）

    @Test("竖直位移达到阈值且大于水平 → 判定为排序")
    func verticalCountsAsReorder() {
        #expect(ReorderLogic.isVerticalReorder(dx: 2, dy: 24, activation: 24))
        #expect(ReorderLogic.isVerticalReorder(dx: 2, dy: -30, activation: 24))
        #expect(ReorderLogic.isVerticalReorder(dx: -8, dy: 40, activation: 24))
    }

    @Test("未达阈值 / 水平占优 → 不判定为排序（留给左滑）")
    func notReorder() {
        #expect(!ReorderLogic.isVerticalReorder(dx: 0, dy: 23.9, activation: 24))
        #expect(!ReorderLogic.isVerticalReorder(dx: 30, dy: 25, activation: 24))   // 水平占优
        #expect(!ReorderLogic.isVerticalReorder(dx: 25, dy: 25, activation: 24))   // 平手让给左滑
        #expect(!ReorderLogic.isVerticalReorder(dx: 0, dy: 0, activation: 24))
    }

    // MARK: 插入位换算

    @Test("位移不足半行 → 落点仍是原位（不改变顺序）")
    func insertionStays() {
        #expect(ReorderLogic.landingIndex(from: 1, dy: 0, step: 84, count: 5) == 1)
        #expect(ReorderLogic.landingIndex(from: 1, dy: 30, step: 84, count: 5) == 1)   // 30 < 半行 42
        #expect(ReorderLogic.landingIndex(from: 1, dy: -30, step: 84, count: 5) == 1)
        #expect(ReorderLogic.insertionIndex(from: 1, dy: 30, step: 84, count: 5) == 1)
    }

    @Test("越过半行即跨一格（消除首格死区）")
    func crossingUsesRounding() {
        // 步长 84：跨 1 格 = 84；过半格 42 就算跨过
        #expect(ReorderLogic.landingIndex(from: 0, dy: 41, step: 84, count: 5) == 0)
        #expect(ReorderLogic.landingIndex(from: 0, dy: 42, step: 84, count: 5) == 1)
        #expect(ReorderLogic.landingIndex(from: 0, dy: 84, step: 84, count: 5) == 1)
        #expect(ReorderLogic.landingIndex(from: 0, dy: 168, step: 84, count: 5) == 2)
        #expect(ReorderLogic.landingIndex(from: 3, dy: -168, step: 84, count: 5) == 1)
        #expect(ReorderLogic.landingIndex(from: 0, dy: 126, step: 84, count: 5) == 2)   // 1.5 格 → 2
    }

    @Test("落点夹取在 0...count-1；两端边界不越界")
    func insertionClamped() {
        // 已是最上 / 最下时继续拖 → 落点不变（原位，不产生移动）
        #expect(ReorderLogic.landingIndex(from: 0, dy: -500, step: 84, count: 5) == 0)
        #expect(ReorderLogic.landingIndex(from: 4, dy: 500, step: 84, count: 5) == 4)
        #expect(ReorderLogic.insertionIndex(from: 0, dy: -500, step: 84, count: 5) == 0)
        #expect(ReorderLogic.insertionIndex(from: 4, dy: 500, step: 84, count: 5) == 4)
        // 从最上拖到最下 → 插入位 = count（数组末尾）
        #expect(ReorderLogic.insertionIndex(from: 0, dy: 500, step: 84, count: 5) == 5)
        #expect(ReorderLogic.moved(["A", "B", "C", "D", "E"], from: 0, to: 5) == ["B", "C", "D", "E", "A"])
    }

    @Test("向下移动的插入位比落点大 1（缝隙语义以「移除拖动行之前」的数组为准）")
    func insertionVersusLanding() {
        // 3 行，把第 0 行向下拖一格 → 落点 1、插入位 2 → [B, A, C]
        #expect(ReorderLogic.landingIndex(from: 0, dy: 84, step: 84, count: 3) == 1)
        #expect(ReorderLogic.insertionIndex(from: 0, dy: 84, step: 84, count: 3) == 2)
        #expect(ReorderLogic.moved(["A", "B", "C"], from: 0, to: 2) == ["B", "A", "C"])
        // 向上移动时插入位与落点相同 → [A, C, B]
        #expect(ReorderLogic.landingIndex(from: 2, dy: -84, step: 84, count: 3) == 1)
        #expect(ReorderLogic.insertionIndex(from: 2, dy: -84, step: 84, count: 3) == 1)
        #expect(ReorderLogic.moved(["A", "B", "C"], from: 2, to: 1) == ["A", "C", "B"])
    }

    @Test("退化输入不崩：步长 0 / 空列表 / 非法下标")
    func degenerateInputs() {
        #expect(ReorderLogic.landingIndex(from: 0, dy: 100, step: 0, count: 5) == 0)
        #expect(ReorderLogic.landingIndex(from: 0, dy: 100, step: 84, count: 0) == 0)
        #expect(ReorderLogic.landingIndex(from: 9, dy: 100, step: 84, count: 5) == 9)
    }

    // MARK: 数组重排（插入位是「移除前」的缝隙下标）

    @Test("向下移动：插到原第 2 行之后")
    func moveDown() {
        let items = ["A", "B", "C", "D"]
        // 把 A（0）放到 B 之后 → 插入位 2
        #expect(ReorderLogic.moved(items, from: 0, to: 2) == ["B", "A", "C", "D"])
        // 把 A 放到 D 之后 → 插入位 4（末尾）
        #expect(ReorderLogic.moved(items, from: 0, to: 4) == ["B", "C", "D", "A"])
    }

    @Test("向上移动：插到目标行之前")
    func moveUp() {
        let items = ["A", "B", "C", "D"]
        // 把 D（3）放到 B 之前 → 插入位 1
        #expect(ReorderLogic.moved(items, from: 3, to: 1) == ["A", "D", "B", "C"])
        // 把 D 放到最顶 → 插入位 0
        #expect(ReorderLogic.moved(items, from: 3, to: 0) == ["D", "A", "B", "C"])
    }

    @Test("原位落下（插入位 = from 或 from+1）不改动数组")
    func noOpInsertion() {
        let items = ["A", "B", "C"]
        #expect(ReorderLogic.moved(items, from: 1, to: 1) == items)
        #expect(ReorderLogic.moved(items, from: 1, to: 2) == items)
    }

    @Test("非法下标不崩、原样返回")
    func invalidIndex() {
        let items = ["A", "B"]
        #expect(ReorderLogic.moved(items, from: 5, to: 0) == items)
        #expect(ReorderLogic.moved(items, from: 0, to: 99) == ["B", "A"])
    }
}
