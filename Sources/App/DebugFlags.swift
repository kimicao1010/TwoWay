#if DEBUG
import Foundation

/// DEBUG 专用启动开关集中处（Release 构建里本文件不存在，调用点全部用 `#if DEBUG` 包住）
///
/// 主要用途之一是**产出可公开的截图**：把钱包指向隔离目录并灌入虚构演示账户，
/// 避免把真实账户信息截进 README / 文档。
enum DebugFlags {

    private static let arguments = ProcessInfo.processInfo.arguments

    /// `--wallet-dir <path>`：改用隔离的加密钱包目录（不碰用户真实数据）
    static var walletDirectoryOverride: URL? {
        guard let index = arguments.firstIndex(of: "--wallet-dir"),
              index + 1 < arguments.count
        else { return nil }
        return URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
    }

    /// `--seed-demo`：钱包为空时灌入**虚构演示账户**（截图用；密钥取自 RFC 6238 测试向量）
    static var seedsDemoData: Bool {
        arguments.contains("--seed-demo")
    }

    /// `--debug-pulse`：底部显示换码/秒脉冲计数（默认关闭 —— 截图不应出现调试痕迹）
    static var showsPulseCounter: Bool {
        arguments.contains("--debug-pulse")
    }

    /// 演示账户：名称/发行方/密钥全部为虚构或公开测试向量
    static let demoAccounts: [(displayName: String, issuer: String?, secretBase32: String)] = [
        ("you@example.com", "GitHub", "JBSWY3DPEHPK3PXP"),
        ("alex@example.com", "Google", "GEZDGNBVGY3TQOJQGEZDGNBVGYQ"),
        ("ops@example.com", "AWS 控制台", "MFRGGZDFMZTWQ2LK"),
        ("100000000001", "腾讯云", "NBSWY3DPFQQFO33SNRSCC"),
        ("team@example.com", "Notion 工作区", "KRSXG5CTMVRXEZLU"),
        ("dev@example.com", "GitLab", "ONSWG4TFOQQGS4ZA")
    ]
}
#endif
