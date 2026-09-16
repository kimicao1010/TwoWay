import Foundation
import Testing
@testable import TwoWay

/// C1-4：时钟 → 展示态换算（PRD T3 连续平滑 / T4 告警阈值 / T5 跨周期刷新依据）
@Suite("TOTP 时钟换算")
struct TOTPTimeTests {

    private let period: TimeInterval = 30

    // MARK: counter（T5 的刷新依据）

    @Test("counter 随周期递增，边界处精确切换")
    func counterProgression() {
        #expect(TOTPTime.state(atUnixTime: 0, period: period).counter == 0)
        #expect(TOTPTime.state(atUnixTime: 29.999, period: period).counter == 0)
        #expect(TOTPTime.state(atUnixTime: 30, period: period).counter == 1)
        #expect(TOTPTime.state(atUnixTime: 59.999, period: period).counter == 1)
        #expect(TOTPTime.state(atUnixTime: 60, period: period).counter == 2)
        // 远期时间不溢出（2603 年对应 RFC 向量 T=20000000000）
        #expect(TOTPTime.state(atUnixTime: 20_000_000_000, period: period).counter == 666_666_666)
    }

    // MARK: progress（T3 连续平滑）

    @Test("progress 连续取值，且与剩余时间严格成比例")
    func progressSmoothness() {
        let cases: [(TimeInterval, Double)] = [
            (0, 1.0),          // 周期开始，满格
            (3, 27.0 / 30.0),
            (15, 0.5),
            (25, 5.0 / 30.0),
            (29.999_999, 0.000_000_033),
        ]
        for (t, expected) in cases {
            let progress = TOTPTime.state(atUnixTime: t, period: period).progress
            #expect(abs(progress - expected) < 1e-6, "t=\(t)")
            #expect(progress >= 0 && progress <= 1)
        }
    }

    @Test("progress 在周期内单调递减（相邻采样不跳变）")
    func progressMonotonic() {
        var previous = 1.0
        var t: TimeInterval = 0
        while t < 30 {
            let p = TOTPTime.state(atUnixTime: t, period: period).progress
            #expect(p <= previous + 1e-12)
            #expect(p >= 0)
            previous = p
            t += 0.033   // ≈ 30Hz 采样步长，与 P-1 的实现采样率一致
        }
    }

    // MARK: secondsRemaining

    @Test("secondsRemaining 向上取整")
    func secondsRemainingCeil() {
        #expect(TOTPTime.state(atUnixTime: 0, period: period).secondsRemaining == 30)
        #expect(TOTPTime.state(atUnixTime: 0.001, period: period).secondsRemaining == 30)
        #expect(TOTPTime.state(atUnixTime: 1, period: period).secondsRemaining == 29)
        #expect(TOTPTime.state(atUnixTime: 29.4, period: period).secondsRemaining == 1)
        #expect(TOTPTime.state(atUnixTime: 29.999, period: period).secondsRemaining == 1)
    }

    // MARK: 告警态（T4）

    @Test("T4：剩余 ≤ 5 秒进入告警态，阈值边界精确")
    func warningThresholdBoundary() {
        // 剩余 5.01 秒 → 未告警
        #expect(!TOTPTime.state(atUnixTime: 30 - 5.01, period: period).isWarning)
        // 剩余恰好 5 秒 → 告警（≤）
        #expect(TOTPTime.state(atUnixTime: 25, period: period).isWarning)
        // 剩余 4.99 秒 → 告警
        #expect(TOTPTime.state(atUnixTime: 30 - 4.99, period: period).isWarning)
        // 周期刚开始 → 不告警
        #expect(!TOTPTime.state(atUnixTime: 0, period: period).isWarning)
    }

    @Test("T4：告警态每个周期都会独立触发（不是一次性状态）")
    func warningRepeatsEachPeriod() {
        for cycle in 0..<5 {
            let t = TimeInterval(cycle) * period + 27   // 每个周期的第 27 秒
            #expect(TOTPTime.state(atUnixTime: t, period: period).isWarning, "cycle \(cycle)")
            let early = TimeInterval(cycle) * period + 3
            #expect(!TOTPTime.state(atUnixTime: early, period: period).isWarning, "cycle \(cycle)")
        }
    }

    // MARK: 其它周期

    @Test("非默认周期（60 秒）同样成立")
    func nonDefaultPeriod() {
        let state = TOTPTime.state(atUnixTime: 45, period: 60)
        #expect(state.counter == 0)
        #expect(state.secondsRemaining == 15)
        #expect(abs(state.progress - 0.25) < 1e-12)
        #expect(!state.isWarning)
    }

    @Test("非法周期被参数校验拦截（而非在换算里静默除零）")
    func invalidPeriodRejected() {
        #expect(throws: OTPParameters.ValidationError.invalidPeriod(0)) {
            _ = try OTPParameters(algorithm: .sha1, digits: 6, period: 0)
        }
        #expect(throws: OTPParameters.ValidationError.invalidPeriod(-30)) {
            _ = try OTPParameters(algorithm: .sha1, digits: 6, period: -30)
        }
    }
}
