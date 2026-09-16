import Foundation
import CoreGraphics

// 按进程名查找窗口 ID（CGWindowList 不需要辅助功能权限）
let target = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "2way"
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []

for info in list {
    let owner = (info[kCGWindowOwnerName as String] as? String) ?? ""
    let name = (info[kCGWindowName as String] as? String) ?? ""
    guard owner.contains(target) || name.contains(target) else { continue }
    let number = (info[kCGWindowNumber as String] as? Int) ?? -1
    let bounds = (info[kCGWindowBounds as String] as? [String: Any]) ?? [:]
    let width = (bounds["Width"] as? Int) ?? 0
    let height = (bounds["Height"] as? Int) ?? 0
    guard width > 100, height > 100 else { continue }   // 排除小托盘窗口
    print("\(number) \(owner) \(name) \(width)x\(height)")
}
