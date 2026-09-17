#if DEBUG
import AppKit

/// 滚动容器取证探针（仅 DEBUG；启动参数 `--scroll-probe <输出路径>`）
///
/// 依据《滚动条去除方法论》：
/// - 纪律 1：「以像素/截图为准，不以属性为准」→ 这里直接读**实际承载显示的对象**
///   （NSScrollView）的几何，而不是猜 SwiftUI 修饰符的语义；
/// - 纪律 10：「最可靠的做法：让被测程序自己把状态写文件」→ 自报 JSON，免 OCR/像素反推；
/// - 纪律 8：必须配阳性对照 → 修复前先跑一次拿到「有滚动条 + 17px 占位」的基线。
///
/// 判据（占位差 = NSScrollView 宽度 − 裁剪区 clipView 宽度）：
///   17 = legacy 滚动条挤压布局（会连带内容左右位移）
///    0 = 不创建滚动条
enum ScrollProbe {

    /// 延迟到首屏布局稳定后再采样，避免量到构建中间态
    static func schedule(outputPath: String, delay: TimeInterval = 2.5) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            write(to: outputPath)
        }
    }

    @MainActor
    private static func write(to path: String) {
        // 扫**全部**可见窗口：sheet / 弹窗是独立 NSWindow，只扫第一个窗口会漏掉
        // （方法论纪律 2：必须复刻用户报告问题的同一承载环境）
        let windows = NSApp.windows.filter { $0.isVisible && $0.contentView != nil }
        guard !windows.isEmpty else {
            try? #"{"error":"no visible window"}"#
                .write(toFile: path, atomically: true, encoding: .utf8)
            return
        }

        var windowRecords: [[String: Any]] = []

        for (windowIndex, window) in windows.enumerated() {
            guard let contentView = window.contentView else { continue }
            var records: [[String: Any]] = []

            func walk(_ view: NSView, at viewPath: String) {
                if let scrollView = view as? NSScrollView {
                    let frameWidth = scrollView.frame.width
                    let clipWidth = scrollView.contentView.frame.width
                    records.append([
                        "viewPath": viewPath,
                        "class": String(describing: type(of: scrollView)),
                        "documentViewClass": scrollView.documentView
                            .map { String(describing: type(of: $0)) } ?? "nil",
                        "hasVerticalScroller": scrollView.hasVerticalScroller,
                        "verticalScrollerExists": scrollView.verticalScroller != nil,
                        "scrollerStyle": scrollView.scrollerStyle == .legacy ? "legacy" : "overlay",
                        "scrollViewWidth": Double(frameWidth),
                        "clipViewWidth": Double(clipWidth),
                        "placeholderWidth": Double(frameWidth - clipWidth),
                        "documentWidth": Double(scrollView.documentView?.frame.width ?? -1)
                    ])
                }
                for (index, subview) in view.subviews.enumerated() {
                    walk(subview, at: "\(viewPath)/\(type(of: subview))[\(index)]")
                }
            }

            walk(contentView, at: "contentView")

            windowRecords.append([
                "windowIndex": windowIndex,
                "windowClass": String(describing: type(of: window)),
                "windowWidth": Double(window.frame.width),
                "windowHeight": Double(window.frame.height),
                "isSheet": window.isSheet,
                "scrollViewCount": records.count,
                "scrollViews": records
            ])
        }

        let payload: [String: Any] = [
            "windowCount": windows.count,
            "windows": windowRecords
        ]

        guard let data = try? JSONSerialization.data(
            withJSONObject: payload,
            options: [.prettyPrinted, .sortedKeys]
        ), let json = String(data: data, encoding: .utf8) else { return }
        try? json.write(toFile: path, atomically: true, encoding: .utf8)
    }
}
#endif
