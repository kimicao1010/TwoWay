import AppKit
import Foundation
import Testing

@testable import TwoWay

/// 偏好设置与窗口尺寸覆盖的纯逻辑测试
@MainActor
struct AppSettingsTests {

    /// 每个用例用独立 suite，避免污染真实 UserDefaults
    private func makeDefaults() -> UserDefaults {
        let suite = "2way-tests-\(UUID().uuidString)"
        return UserDefaults(suiteName: suite)!
    }

    @Test("默认不隐藏 Dock 图标")
    func defaultOff() {
        let settings = AppSettings(defaults: makeDefaults())
        #expect(settings.hideDockIcon == false)
        #expect(settings.activationPolicy == .regular)
    }

    @Test("开启后落盘，新实例读回仍为开启")
    func persistence() {
        let defaults = makeDefaults()

        let first = AppSettings(defaults: defaults)
        first.hideDockIcon = true

        let second = AppSettings(defaults: defaults)
        #expect(second.hideDockIcon == true)
        #expect(second.activationPolicy == .accessory)

        second.hideDockIcon = false
        #expect(AppSettings(defaults: defaults).hideDockIcon == false)
    }

    @Test("激活策略映射：隐藏 Dock = .accessory，否则 .regular")
    func policyMapping() {
        let settings = AppSettings(defaults: makeDefaults())
        settings.hideDockIcon = true
        #expect(settings.activationPolicy == .accessory)
        settings.hideDockIcon = false
        #expect(settings.activationPolicy == .regular)
    }

    @Test("持久化键名固定（defaults 命令行调试依赖它）")
    func keyName() {
        #expect(AppSettings.hideDockIconKey == "hideDockIcon")
    }
}

/// 窗口宽度覆盖（`--width <pt>`）解析
struct WindowMetricsTests {

    private let fallback: CGFloat = 400

    @Test("无参数 → 用默认宽度")
    func noOverride() {
        #expect(WindowMetrics.width(overrideArguments: [], fallback: fallback) == fallback)
    }

    @Test("合法取值 → 采用覆盖值（按 20 一档比选用）")
    func validOverride() {
        for width in [380, 360, 340, 320] {
            let parsed = WindowMetrics.width(
                overrideArguments: ["2way", "--width", "\(width)"],
                fallback: fallback
            )
            #expect(parsed == CGFloat(width))
        }
    }

    @Test("非法取值一律回落：非数字 / 越界 / 缺值")
    func invalidOverride() {
        #expect(WindowMetrics.width(overrideArguments: ["--width", "abc"], fallback: fallback) == fallback)
        #expect(WindowMetrics.width(overrideArguments: ["--width", "100"], fallback: fallback) == fallback)
        #expect(WindowMetrics.width(overrideArguments: ["--width", "999"], fallback: fallback) == fallback)
        #expect(WindowMetrics.width(overrideArguments: ["--width"], fallback: fallback) == fallback)
    }

    @Test("弹窗宽度随窄窗口自适应，且不小于下限")
    func sheetWidthAdapts() {
        // 当前实现按 WindowMetrics.width 计算，这里只校验下界与上限语义
        #expect(WindowMetrics.sheetWidth(preferred: 380) <= 380)
        #expect(WindowMetrics.sheetWidth(preferred: 380) >= 280)
    }
}
