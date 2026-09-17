import CoreGraphics
import Foundation
import Observation

/// 列表拖动排序的**会话状态**（DR-01 / R12）
///
/// 只承载「正在拖哪一行、拖到哪了、将插入到哪个缝隙」，
/// 具体重排与落盘由 `AccountStore.move` 负责（数据层与手势层解耦，便于单测）。
@MainActor
@Observable
final class ListReorderModel {

    /// 正在拖动的账户（nil = 未在排序）
    private(set) var draggingID: UUID?
    /// 被拖动行**原位**的下标（用于算让位与插入位）
    private(set) var originIndex = 0
    /// 相对原位的竖直位移（跟随光标）
    private(set) var offsetY: CGFloat = 0
    /// 当前插入位（缝隙下标，0...行数）
    private(set) var insertionIndex: Int?

    private var step: CGFloat = 0
    private var count = 0

    var isActive: Bool { draggingID != nil }

    /// 开始拖动
    func begin(id: UUID, originIndex: Int, step: CGFloat, count: Int) {
        self.draggingID = id
        self.originIndex = originIndex
        self.offsetY = 0
        self.insertionIndex = originIndex
        self.step = step
        self.count = count
    }

    /// 拖动中：更新位移并重算插入位
    func update(translationY: CGFloat) {
        guard isActive else { return }
        offsetY = translationY
        insertionIndex = ReorderLogic.insertionIndex(
            from: originIndex,
            dy: translationY,
            step: step,
            count: count
        )
    }

    /// 结束（不论落定与否都复位；落定动作由调用方按 `insertionIndex` 执行）
    func end() {
        draggingID = nil
        offsetY = 0
        insertionIndex = nil
        originIndex = 0
    }

    /// 该行是否需要为拖动行让位（返回竖直位移量）
    func shift(forRowAt index: Int) -> CGFloat {
        guard let insertion = insertionIndex, isActive else { return 0 }
        guard index != originIndex else { return 0 }

        if originIndex < insertion, index > originIndex, index < insertion {
            return -step          // 上面的行被拖到下方 → 中间的行整体上移
        }
        if insertion < originIndex, index >= insertion, index < originIndex {
            return step           // 上面的行被拖下来 → 这些行整体下移
        }
        return 0
    }

    /// 落定后该行占据的下标（画插入位指示线用：线画在落点槽位的上沿）
    var landingIndex: Int? {
        guard isActive, let insertion = insertionIndex else { return nil }
        return insertion > originIndex ? insertion - 1 : insertion
    }

    /// 是否发生了实际位移（原位放下则不算）
    var hasPendingMove: Bool {
        guard let landing = landingIndex else { return false }
        return landing != originIndex
    }
}
