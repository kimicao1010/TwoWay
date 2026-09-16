import Observation
import SwiftUI

/// 分段控件（PRD §7.4：容器 34 / 圆角 9 / 段 28 / 圆角 7 / 选中 `--seg-active`）
struct SegmentedControl<Option: Hashable>: View {
    let options: [Option]
    let title: (Option) -> String
    @Binding var selection: Option

    var body: some View {
        HStack(spacing: 3) {
            ForEach(options, id: \.self) { option in
                let selected = option == selection
                Button {
                    selection = option
                } label: {
                    Text(title(option))
                        .font(Token.Typography.label)
                        .foregroundStyle(selected ? Token.Palette.t1 : Token.Palette.t2)
                        .frame(maxWidth: .infinity)
                        .frame(height: Token.Metrics.segmentedItemHeight)
                        .background(selected ? Token.Palette.segActive : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: Token.Metrics.segmentedItemRadius))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .frame(height: Token.Metrics.segmentedHeight)
        .background(Token.Palette.seg)
        .clipShape(RoundedRectangle(cornerRadius: Token.Metrics.segmentedRadius))
    }
}

/// Toast（PRD §7.2 R1 / §9 E1）
///
/// Demo 规格：底部 44pt、停留 1.8s、再次触发时替换文案并重置计时。
struct ToastView: View {
    let message: String

    var body: some View {
        Text(message)
            .font(Token.Typography.body)
            .foregroundStyle(Token.Palette.t1)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(Token.Palette.actionDetail)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Token.Palette.ringTrack, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

/// Toast 的状态机 —— 独立成类型是为了可注入时间做单测（C2-3 会用到）
///
/// ⚠️ 必须是 `@Observable`（而不是 `ObservableObject` + `@Published`）：
/// 持有方 `RootView` 用 `@State` 保存它，而 `@State` **不会**订阅 `ObservableObject`
/// 的变化 —— 那样 toast 状态变了界面也不刷新（复制后「无提示」的根因）。
@MainActor
@Observable
final class ToastCenter {
    struct Toast: Equatable {
        let id = UUID()
        let message: String
    }

    private(set) var current: Toast?

    /// 停留时长（Demo 实测 1.8s）
    private let duration: TimeInterval
    /// 等待用的闭包，测试注入短时长避免真实 sleep
    private let wait: (TimeInterval) async throws -> Void
    private var dismissTask: Task<Void, Never>?

    init(duration: TimeInterval = Token.Motion.toastDuration,
         wait: @escaping (TimeInterval) async throws -> Void = { try await Task.sleep(nanoseconds: UInt64($0 * 1_000_000_000)) }) {
        self.duration = duration
        self.wait = wait
    }

    /// 显示 toast；连续调用会替换文案并重置计时（Demo 行为）
    func show(_ message: String) {
        dismissTask?.cancel()
        current = Toast(message: message)
        let waited = wait
        let seconds = duration
        dismissTask = Task { [weak self] in
            do { try await waited(seconds) } catch { return }   // 被新 toast 取消
            guard !Task.isCancelled else { return }
            self?.current = nil
        }
    }

    /// 立即隐藏（用于切屏等场景）
    func dismiss() {
        dismissTask?.cancel()
        current = nil
    }
}
