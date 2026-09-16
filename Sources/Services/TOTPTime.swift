import Foundation

/// 由时钟推得的展示态（PRD T3 / T4 / T5）
struct TOTPTimeState: Equatable, Sendable {
    /// 当前周期序号。**变化即跨周期**，所有可见验证码据此统一刷新（T5）
    let counter: UInt64
    /// 「N 秒后刷新」的显示值，向上取整（PRD §7.5 详情页 meta）
    let secondsRemaining: Int
    /// 倒计时环进度 0...1，连续平滑、非整秒跳变（T3）
    let progress: Double
    /// 剩余 ≤ 5 秒进入告警态（T4），各账户独立判定
    let isWarning: Bool
}

/// 时钟 → 展示态的纯换算。无状态、可注入任意时间做单测（C1-4）。
///
/// 时钟源本身由 UI 层的 `TimelineView(.animation(minimumInterval: 1/30))` 驱动，
/// 本类型只负责「给一个时刻 → 算出四个值」，保证 7 个环同相位（P-1）。
enum TOTPTime {

    /// PRD T4：剩余 ≤ 5 秒进入告警态
    static let warningThreshold: TimeInterval = 5

    static func state(at date: Date, period: TimeInterval) -> TOTPTimeState {
        precondition(period > 0, "period 必须为正")
        let unixTime = date.timeIntervalSince1970
        let elapsed = unixTime.truncatingRemainder(dividingBy: period)
        let remaining = max(0, period - elapsed)

        return TOTPTimeState(
            counter: UInt64((unixTime / period).rounded(.down)),
            secondsRemaining: Int(remaining.rounded(.up)),
            progress: min(1, remaining / period),
            isWarning: remaining <= warningThreshold
        )
    }

    /// 便捷重载：直接给 unix 秒（测试常用）
    static func state(atUnixTime t: TimeInterval, period: TimeInterval) -> TOTPTimeState {
        state(at: Date(timeIntervalSince1970: t), period: period)
    }
}
