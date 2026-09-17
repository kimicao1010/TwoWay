import CoreGraphics
import Foundation

/// 拖动排序的纯逻辑（与视图/存储解耦，可单测）—— PRD DR-01 / R12
enum ReorderLogic {

    /// 放置位置：插到目标行的**前**面还是**后**面
    enum Position: Equatable {
        case before
        case after
    }

    /// 方向判定：这次拖动是「排序」（竖直）还是「左滑」（水平）？
    ///
    /// 与 `SwipeLogic.isHorizontalDrag` 互为反面，但**阈值不同**：
    /// 左滑 8pt 就该跟手（灵敏度优先），排序要 24pt 才激活 ——
    /// 因为排序会**改数据**，误触代价高（列表顺序被莫名改掉），故要求更明确的意图。
    static func isVerticalReorder(dx: CGFloat, dy: CGFloat, activation: CGFloat) -> Bool {
        abs(dy) >= activation && abs(dy) > abs(dx)
    }

    /// 拖动行**最终将占据的下标**（0..<count）
    ///
    /// - Parameters:
    ///   - from: 被拖动行当前下标
    ///   - dy: 相对按下位置的竖直位移（向下为正）
    ///   - step: 单行步长（行高 + 行间距）
    ///   - count: 行数（用于夹取）
    ///
    /// 取整用 round：**越过半行即算跨过一格**（与让位动画的观感一致，且避免首格半格死区）。
    static func landingIndex(from: Int, dy: CGFloat, step: CGFloat, count: Int) -> Int {
        guard step > 0, count > 0, (0 ..< count).contains(from) else { return from }
        let crossedSlots = Int((dy / step).rounded())
        return min(count - 1, max(0, from + crossedSlots))
    }

    /// 由拖动位移换算「插入位」（0...count 的缝隙下标，供 `moved` 使用）
    ///
    /// 语义：缝隙下标以**移除拖动行之前**的数组为准。
    /// 因此向下移动时要落到目标槽位**之后**（+1），向上移动时落在槽位**处**。
    /// 例：`[A,B,C]` 把 A 向下拖一格 → 落点槽位 1 → 插入位 2 → `[B,A,C]`。
    static func insertionIndex(from: Int, dy: CGFloat, step: CGFloat, count: Int) -> Int {
        let landing = landingIndex(from: from, dy: dy, step: step, count: count)
        return landing > from ? landing + 1 : landing
    }

    /// 把 `from` 处的元素移动到插入位 `insertion`，返回新数组
    ///
    /// 插入位是**移除前**的缝隙下标：`insertion == from` 或 `from + 1` 都等价于原地不动。
    static func moved<T>(_ items: [T], from: Int, to insertion: Int) -> [T] {
        guard items.indices.contains(from) else { return items }
        let clamped = min(items.count, max(0, insertion))
        guard clamped != from, clamped != from + 1 else { return items }

        var result = items
        let element = result.remove(at: from)
        let destination = clamped > from ? clamped - 1 : clamped
        result.insert(element, at: min(result.count, max(0, destination)))
        return result
    }

    /// 稠密化序号：按当前数组顺序产出 0..<n（DR-01 落盘用）
    static func denseIndices(count: Int) -> [Int] {
        Array(0 ..< max(0, count))
    }
}
