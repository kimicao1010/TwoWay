import CoreGraphics
import Foundation

/// 窗口尺寸的运行时入口
///
/// 存在的理由：窗口宽度需要**比选**（用户反馈 400 太宽，想按 20 一档收窄）。
/// `Token.Metrics.windowWidth` 是编译期常量，改一次要重编一次；这里允许
/// DEBUG 启动参数 `--width <pt>` 在运行时覆盖，便于一次性出多个宽度的预览截图。
enum WindowMetrics {

    /// 允许的宽度区间（防止误传把窗口搞成不可用）
    static let allowedWidthRange: ClosedRange<Double> = 260 ... 420

    /// 当前窗口宽度
    static var width: CGFloat {
        width(overrideArguments: ProcessInfo.processInfo.arguments)
    }

    /// 纯函数版本（便于单测）：识别 `--width <pt>`，非法值一律回落到默认
    static func width(
        overrideArguments arguments: [String],
        fallback: CGFloat = Token.Metrics.windowWidth
    ) -> CGFloat {
        guard
            let index = arguments.firstIndex(of: "--width"),
            index + 1 < arguments.count,
            let value = Double(arguments[index + 1]),
            allowedWidthRange.contains(value)
        else {
            return fallback
        }
        return CGFloat(value)
    }

    /// 弹窗（sheet）宽度：窄窗口下自适应，避免 380 的弹窗顶出窗口
    static func sheetWidth(preferred: CGFloat = 380) -> CGFloat {
        min(preferred, max(280, width - 24))
    }
}
