import CoreGraphics
import Foundation
import Observation

/// C2-2 左滑状态机（PRD FR-02 R1–R11）—— 纯逻辑，不含 SwiftUI 类型，可单测。
///
/// 规则与 Demo `index.html` 的 `attachSwipe` 逐条对齐：
/// - R2 位移夹取 `[-160, 0]`，右滑不展开
/// - R3 释放时 `|x| ≥ 72`（0.45 × 160）吸附展开，否则回弹
/// - R4 横向位移 > 8 且大于纵向位移才判定为拖拽
/// - R6 拖拽结束后短暂窗口内吞掉系统补发的 click（RK1 风险项的双保险）
enum SwipeLogic {

    /// R2：位移夹取 `[-maxOffset, 0]`（正位移一律归 0，右滑不会展开、不错位）
    static func clamp(_ dx: CGFloat, maxOffset: CGFloat) -> CGFloat {
        min(0, max(-maxOffset, dx))
    }

    /// R4：横向位移 > 阈值 且 |dx| > |dy| 才判定为拖拽；否则视为点按 / 竖向滚动
    static func isHorizontalDrag(dx: CGFloat, dy: CGFloat, threshold: CGFloat) -> Bool {
        abs(dx) > threshold && abs(dx) > abs(dy)
    }

    /// R3：释放时 `offset ≤ -threshold` 吸附至 `-maxOffset`，否则回弹归位
    /// （边界含等号：恰好 72px 也吸附，与 Demo `x < -MAX*0.45` 的取反语义一致）
    static func settle(for offset: CGFloat, maxOffset: CGFloat, threshold: CGFloat) -> CGFloat {
        offset <= -threshold ? -maxOffset : 0
    }
}

/// 单行左滑的运行时状态机。
///
/// 时间以 `now` 闭包注入（R6 的抑制窗口可测）；阈值全部由调用方传入，
/// 本类型不依赖 UI 层常量。
@MainActor
@Observable
final class SwipeRowModel {

    enum Phase: Equatable {
        case idle      // 归位
        case dragging  // 已确认为横向拖拽，跟手中（R10：此间无动画）
        case open      // 吸附展开
    }

    private(set) var phase: Phase = .idle
    /// 行内容横向位移，恒 ≤ 0（左滑为负）
    private(set) var offset: CGFloat = 0
    /// R6：最近一次**已确认**拖拽的结束时间
    private(set) var lastDragEnd: Date?

    private let maxOffset: CGFloat
    private let snapThreshold: CGFloat
    private let dragThreshold: CGFloat
    /// R6：拖拽结束后该窗口内的 click 一律吞掉
    private let tapSuppressionWindow: TimeInterval
    private let now: () -> Date

    private var confirmedHorizontal = false
    /// 拖拽基准：已展开行的基准是 -maxOffset（从展开态继续拖 = 收起方向）
    private var dragBase: CGFloat = 0

    init(
        maxOffset: CGFloat,
        snapThreshold: CGFloat,
        dragThreshold: CGFloat,
        tapSuppressionWindow: TimeInterval = 0.15,
        now: @escaping () -> Date = Date.init
    ) {
        self.maxOffset = maxOffset
        self.snapThreshold = snapThreshold
        self.dragThreshold = dragThreshold
        self.tapSuppressionWindow = tapSuppressionWindow
        self.now = now
    }

    var isDragging: Bool { phase == .dragging }
    var isOpen: Bool { phase == .open }

    /// 拖拽跟手中。未越过 R4 判定前不改变任何状态（竖向滚动 / 点按不受影响）。
    func dragChanged(_ translation: CGSize) {
        if !confirmedHorizontal {
            guard SwipeLogic.isHorizontalDrag(
                dx: translation.width,
                dy: translation.height,
                threshold: dragThreshold
            ) else { return }
            confirmedHorizontal = true
            dragBase = offset
            phase = .dragging
        }
        // R2：夹取 [-maxOffset, 0]；R10：跟手（动画由视图层在拖拽中关闭）
        offset = SwipeLogic.clamp(dragBase + translation.width, maxOffset: maxOffset)
    }

    /// 拖拽释放。未确认为横向拖拽的释放（竖向滚动 / 纯点按）不影响任何状态。
    func dragEnded() {
        guard confirmedHorizontal else { return }
        confirmedHorizontal = false
        lastDragEnd = now()   // R6
        let settled = SwipeLogic.settle(for: offset, maxOffset: maxOffset, threshold: snapThreshold)
        offset = settled
        phase = settled == 0 ? .idle : .open
    }

    /// 吸附展开（R9 同步 / 程序化展开）
    func open() {
        confirmedHorizontal = false
        offset = -maxOffset
        phase = .open
    }

    /// 复位归零（R5 点按收起 / R7 R8 操作后复位 / R9 互斥 / E8 切屏复位）
    func close() {
        confirmedHorizontal = false
        offset = 0
        phase = .idle
    }

    /// R6：拖拽刚结束的瞬间，系统补发的 click 必须被吞掉。
    /// 超过抑制窗口后恢复点按语义（R5 / R1）。
    func shouldSuppressTap() -> Bool {
        guard let last = lastDragEnd else { return false }
        return now().timeIntervalSince(last) < tapSuppressionWindow
    }
}
