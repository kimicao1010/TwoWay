import AppKit

/// 剪贴板封装（PRD R1 / E1）
enum Clipboard {

    /// 写入纯文本。返回是否成功 —— E1 要求失败时给出提示，**不静默失败**。
    @discardableResult
    static func copyString(_ string: String) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.setString(string, forType: .string)
    }
}
