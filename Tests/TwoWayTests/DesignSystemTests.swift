import Foundation
import Testing
@testable import TwoWay

/// C0-2：倒计时环几何换算 + Toast 状态机
@Suite("倒计时环几何")
struct RingGeometryTests {

    @Test("progress 越界与非法值都被收敛到 0...1", arguments: [
        (-1.0, 0.0), (0.0, 0.0), (0.25, 0.25), (0.5, 0.5),
        (1.0, 1.0), (1.5, 1.0), (Double.infinity, 0.0),
        (-Double.infinity, 0.0), (Double.nan, 0.0),
    ])
    func clamping(input: Double, expected: Double) {
        #expect(RingGeometry.clamped(input) == expected)
        #expect(RingGeometry.strokeEnd(for: input) == expected)
    }

    @Test("弧长与周长成正确比例（列表小环 r=11）")
    func arcLengthProportional() {
        let radius: CGFloat = 11
        let full = 2 * Double.pi * Double(radius)
        #expect(abs(Double(RingGeometry.arcLength(radius: radius, progress: 1)) - full) < 1e-9)
        #expect(abs(Double(RingGeometry.arcLength(radius: radius, progress: 0.5)) - full / 2) < 1e-9)
        #expect(RingGeometry.arcLength(radius: radius, progress: 0) == 0)
    }

    @Test("progress=1 时环满、progress=0 时环空（T3 极值）")
    func extremes() {
        #expect(RingGeometry.strokeEnd(for: 1) == 1)
        #expect(RingGeometry.strokeEnd(for: 0) == 0)
    }

    @Test("与 TOTPTime 联动：任意时刻的 progress 都落在合法区间")
    func integrationWithClock() {
        for t in stride(from: 0.0, through: 90.0, by: 0.037) {
            let state = TOTPTime.state(atUnixTime: t, period: 30)
            let end = RingGeometry.strokeEnd(for: state.progress)
            #expect(end >= 0 && end <= 1, "t=\(t)")
        }
    }
}

/// Toast 自动消失走真实计时，但时长/间隔留了 5~10 倍裕度避免偶发
@Suite("Toast 状态机")
@MainActor
struct ToastCenterTests {

    @Test("show 后立即可见，超时后自动消失")
    func showThenAutoDismiss() async {
        let center = ToastCenter(duration: 0.1)
        center.show("验证码已复制")
        #expect(center.current?.message == "验证码已复制")

        try? await Task.sleep(nanoseconds: 500_000_000)   // 0.5s ≫ 0.1s
        #expect(center.current == nil)
    }

    @Test("连续 show 替换文案并重置计时")
    func consecutiveShowsReplace() async throws {
        let center = ToastCenter(duration: 0.3)
        center.show("第一条")
        try await Task.sleep(nanoseconds: 50_000_000)     // 0.05s < 0.3s
        center.show("第二条")
        #expect(center.current?.message == "第二条")

        try await Task.sleep(nanoseconds: 700_000_000)    // 0.7s ≫ 0.3s（重置后）
        #expect(center.current == nil)
    }

    @Test("dismiss 立即隐藏，不等计时")
    func dismissImmediately() async {
        let center = ToastCenter(duration: 5)
        center.show("x")
        #expect(center.current != nil)
        center.dismiss()
        #expect(center.current == nil)
    }

    @Test("连续两条是不同的 Toast 实例（id 唯一，供视图做过渡动画）")
    func uniqueIdentifiers() {
        let center = ToastCenter(duration: 5)
        center.show("a")
        let first = center.current
        center.show("b")
        #expect(center.current?.id != first?.id)
    }
}
