#if DEBUG
import Foundation

/// 行交互/切屏取证探针（仅 DEBUG；启动参数 `--row-trace <输出路径>`）
///
/// 目的：判定「回到主页时所有行闪现操作块」到底是
///   (a) **状态问题** —— 行的偏移真的被短暂置成 -160（程序自报可见），还是
///   (b) **渲染问题** —— 偏移恒为 0，闪现来自切屏淡入时底层操作块透出（需改过渡）
///
/// 依据《滚动条去除方法论》纪律 1/10：以现象为准、让被测程序自报状态，
/// 而不是围绕属性（offset 是否应非零）推理。
enum RowTrace {

    private static let start = Date()
    private static let lock = NSLock()
    private nonisolated(unsafe) static var url: URL?

    static var isEnabled: Bool { url != nil }

    static func enable(path: String) {
        let target = URL(fileURLWithPath: path)
        try? Data().write(to: target)
        url = target
    }

    static func log(_ message: String) {
        guard let url else { return }
        let ms = Int(Date().timeIntervalSince(start) * 1000)
        let line = Data("[\(ms)ms] \(message)\n".utf8)
        lock.lock()
        defer { lock.unlock() }
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(line)
            try? handle.close()
        }
    }
}
#endif
