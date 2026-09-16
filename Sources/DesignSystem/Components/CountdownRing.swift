import SwiftUI

/// 倒计时环的**纯几何换算**（独立出来是为了可被单测覆盖，C0-2）
///
/// 对应 Demo 的 `stroke-dasharray = C` / `stroke-dashoffset = C × (1 - progress)`：
/// 可见弧长 = 周长 × progress，起点在 12 点钟方向、顺时针。
enum RingGeometry {

    /// 把任意输入收敛到合法区间。NaN / 负数 / 超界都不能让绘制出错。
    static func clamped(_ progress: Double) -> Double {
        guard progress.isFinite else { return 0 }
        return min(1, max(0, progress))
    }

    /// `Circle().trim(from: 0, to:)` 的终止值
    static func strokeEnd(for progress: Double) -> Double {
        clamped(progress)
    }

    /// 可见弧长（pt）。用于断言换算结果与周长成正确比例。
    static func arcLength(radius: CGFloat, progress: Double) -> CGFloat {
        let circumference = 2 * .pi * Double(radius)
        return CGFloat(circumference * clamped(progress))
    }
}

/// 倒计时环（PRD §7.1 行末 28/描边 3；§7.5 详情 168/描边 5）
///
/// T3：由上层传入**连续** progress（来自 `TOTPTime.state.progress`），不做整秒跳变。
/// T4：剩余 ≤ 5s 时 `isWarning = true`，进度 `#F28B82`、轨道 `#3A2B2B`（多行独立判定）。
///     详情页大环的轨道是 `#3A3F45`，与列表小环不同 —— 用 `heroTrack` 区分。
struct CountdownRing: View {
    let progress: Double
    let size: CGFloat
    let strokeWidth: CGFloat
    var isWarning = false
    /// 详情页大环轨道色不同（PRD §8.1）
    var heroTrack = false

    private var trackColor: Color {
        if isWarning { return Token.Palette.ringTrackWarn }
        return heroTrack ? Token.Palette.ringTrackHero : Token.Palette.ringTrack
    }

    private var fillColor: Color {
        isWarning ? Token.Palette.dangerText : Token.Palette.accent
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(trackColor, lineWidth: strokeWidth)

            Circle()
                .trim(from: 0, to: RingGeometry.strokeEnd(for: progress))
                .stroke(
                    fillColor,
                    style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
        .animation(.linear(duration: 0.033), value: RingGeometry.strokeEnd(for: progress))
    }
}
