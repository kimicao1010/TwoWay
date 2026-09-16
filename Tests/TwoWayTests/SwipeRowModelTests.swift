import CoreGraphics
import Foundation
import Testing
@testable import TwoWay

/// C2-2：左滑状态机（PRD FR-02 R2/R3/R4/R6）—— 阈值取 PRD 数值：max 160 / 吸附 72 / 判定 8
@MainActor
@Suite("SwipeRowModel（左滑状态机）")
struct SwipeRowModelTests {

    private let max: CGFloat = 160
    private let snap: CGFloat = 72
    private let drag: CGFloat = 8

    private func makeModel(now: @escaping () -> Date = Date.init) -> SwipeRowModel {
        SwipeRowModel(
            maxOffset: max,
            snapThreshold: snap,
            dragThreshold: drag,
            tapSuppressionWindow: 0.15,
            now: now
        )
    }

    // MARK: R2 位移夹取

    @Test("R2：位移夹取 [-160, 0]，右滑归 0 不展开不错位")
    func clamp() {
        #expect(SwipeLogic.clamp(-50, maxOffset: max) == -50)
        #expect(SwipeLogic.clamp(-160, maxOffset: max) == -160)
        #expect(SwipeLogic.clamp(-200, maxOffset: max) == -160)   // 超出上限夹取
        #expect(SwipeLogic.clamp(0, maxOffset: max) == 0)
        #expect(SwipeLogic.clamp(30, maxOffset: max) == 0)        // 右滑不允许展开
    }

    // MARK: R4 拖拽判定

    @Test("R4：横向位移 > 8 且大于纵向位移才判定为拖拽")
    func horizontalDetection() {
        #expect(SwipeLogic.isHorizontalDrag(dx: 10, dy: 2, threshold: drag))     // 横向拖拽
        #expect(SwipeLogic.isHorizontalDrag(dx: -10, dy: 0, threshold: drag))    // 左滑
        #expect(!SwipeLogic.isHorizontalDrag(dx: 5, dy: 0, threshold: drag))     // 不足 8px → 点按
        #expect(!SwipeLogic.isHorizontalDrag(dx: 10, dy: 20, threshold: drag))   // 纵向占优 → 滚动
        #expect(!SwipeLogic.isHorizontalDrag(dx: 0, dy: 30, threshold: drag))    // 纯竖向
    }

    // MARK: R3 吸附 / 回弹

    @Test("R3：释放 |x| ≥ 72 吸附展开，否则回弹归位（含边界）")
    func settle() {
        #expect(SwipeLogic.settle(for: -80, maxOffset: max, threshold: snap) == -160)
        #expect(SwipeLogic.settle(for: -72, maxOffset: max, threshold: snap) == -160)   // 恰好阈值 → 吸附
        #expect(SwipeLogic.settle(for: -71.9, maxOffset: max, threshold: snap) == 0)    // 差 0.1 → 回弹
        #expect(SwipeLogic.settle(for: -10, maxOffset: max, threshold: snap) == 0)
        #expect(SwipeLogic.settle(for: 0, maxOffset: max, threshold: snap) == 0)
    }

    // MARK: 完整手势流程

    @Test("拖拽超过阈值释放 → 吸附展开；小幅拖拽释放 → 回弹")
    func dragFlow() {
        let m = makeModel()

        m.dragChanged(CGSize(width: -10, height: 0))   // 确认横向
        m.dragChanged(CGSize(width: -90, height: 0))
        m.dragEnded()
        #expect(m.isOpen)
        #expect(m.offset == -max)

        m.close()
        #expect(!m.isOpen && m.offset == 0)

        m.dragChanged(CGSize(width: -40, height: 0))
        m.dragEnded()
        #expect(m.phase == .idle)
        #expect(m.offset == 0)   // 回弹
    }

    @Test("从展开态继续拖拽：基准为 -160，右滑回位")
    func dragFromOpenState() {
        let m = makeModel()
        m.open()
        #expect(m.offset == -max)

        m.dragChanged(CGSize(width: 10, height: 2))    // 右滑 10px → x = -150，仍吸附
        m.dragEnded()
        #expect(m.isOpen)

        m.dragChanged(CGSize(width: 120, height: 0))   // 右滑 120px → x = -40 → 回弹收起
        m.dragEnded()
        #expect(m.phase == .idle && m.offset == 0)
    }

    @Test("展开态左滑拖拽不会越界（x = clamp(-160 + dx)）")
    func dragLeftWhileOpenClamped() {
        let m = makeModel()
        m.open()
        m.dragChanged(CGSize(width: -50, height: 0))   // 基准 -160 再左滑 → 夹取 -160
        #expect(m.offset == -max)
    }

    // MARK: R6 吞 click

    @Test("R6：已确认拖拽结束后短窗口内吞掉 click；窗口过后恢复")
    func tapSuppression() throws {
        var clock = 1_000.0
        let m = makeModel(now: { Date(timeIntervalSince1970: clock) })

        m.dragChanged(CGSize(width: -50, height: 0))
        m.dragEnded()
        #expect(m.shouldSuppressTap())             // 刚结束 → 吞掉

        clock += 0.14
        #expect(m.shouldSuppressTap())

        clock += 0.02                              // 共 0.16s > 0.15s
        #expect(!m.shouldSuppressTap())            // 恢复点按语义（R5/R1）
    }

    @Test("R6：未确认的释放（竖向滚动 / 纯点按）不产生抑制窗口")
    func noSuppressionWithoutConfirmedDrag() {
        let m = makeModel()
        m.dragChanged(CGSize(width: 0, height: 30))    // 纵向 → 不确认
        m.dragEnded()
        #expect(!m.shouldSuppressTap())
        #expect(m.phase == .idle)

        m.dragEnded()                              // 无人拖拽时释放同样无害
        #expect(!m.shouldSuppressTap())
    }

    // MARK: R5 / 程序化控制

    @Test("open/close 程序化控制：R5 点按收起、R9 互斥同步、E8 切屏复位都走这两个入口")
    func programmaticControl() {
        let m = makeModel()
        m.open()
        #expect(m.isOpen && m.offset == -max)
        m.close()
        #expect(m.phase == .idle && m.offset == 0)
    }
}
