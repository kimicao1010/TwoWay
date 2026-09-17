import AppKit
import Foundation
import Observation

/// 应用偏好（UserDefaults 持久化；均为非敏感信息 —— 密钥/验证码绝不进这里，S1/S2）
@MainActor
@Observable
final class AppSettings {

    /// 持久化键（与 `defaults read/write com.kimi.2way` 同名，便于调试）
    static let hideDockIconKey = "hideDockIcon"

    private let defaults: UserDefaults

    /// 隐藏 Dock 图标
    ///
    /// 实现方式：切换进程的**激活策略** —— `.accessory` 时 App 不出现在 Dock 与 Cmd-Tab，
    /// 只保留菜单栏图标；`.regular` 恢复常规 App。macOS 不支持运行时改 Info.plist 的
    /// `LSUIElement`，`setActivationPolicy` 是官方支持的等价手段。
    var hideDockIcon: Bool {
        didSet {
            guard hideDockIcon != oldValue else { return }
            defaults.set(hideDockIcon, forKey: Self.hideDockIconKey)
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.hideDockIcon = defaults.bool(forKey: Self.hideDockIconKey)
    }

    /// 期望的激活策略（纯计算，便于单测）
    var activationPolicy: NSApplication.ActivationPolicy {
        hideDockIcon ? .accessory : .regular
    }

    /// 应用到进程（幂等，可在每次启动 / 每次改动后调用）
    func applyActivationPolicy() {
        NSApplication.shared.setActivationPolicy(activationPolicy)
    }
}
