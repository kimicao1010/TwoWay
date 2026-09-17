import AppKit
import SwiftUI

/// 状态栏（菜单栏）下拉面板 —— 快速取码（P2「菜单栏常驻」提前落地）
///
/// 交互（用户需求）：
/// - 点状态栏图标 → 下拉 → **点行即复制**，不用切窗口；
/// - 默认只列**最多 5 条**（与主列表同序：最近添加在前），其余**靠搜索**找；
/// - 输入关键词后不再受 5 条限制（否则搜到了也看不见第 6 条）；
/// - 复制走 `ClipboardGuard`（S4：30s 后自动清除；仅当剪贴板仍归本应用所有才清）。
///
/// 与主窗口的关系：共用同一个 `AccountStore` 实例（由 `TwoWayApp` 持有），
/// 因此「主窗口删了账户」「状态栏复制」看到的是同一份数据，不存在双源不一致。
struct MenuBarView: View {

    let store: AccountStore

    @State private var query = Self.debugInitialQuery
    @State private var feedback: Feedback?
    @FocusState private var searchFocused: Bool
    @Environment(\.openWindow) private var openWindow

    private struct Feedback: Equatable {
        enum Kind { case copied, failed }
        let id: UUID
        let kind: Kind
    }

    /// 调试：`--debug-menubar-query <文本>` 预填搜索词（用于截图验证搜索态；生产恒为空）
    static var debugInitialQuery: String {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "--debug-menubar-query"),
              index + 1 < arguments.count
        else { return "" }
        return arguments[index + 1]
        #else
        return ""
        #endif
    }

    private var selection: MenuBarSelection.Result {
        MenuBarSelection.entries(from: store.accounts, query: query, limit: MenuBarSelection.defaultLimit)
    }

    var body: some View {
        // 读换码脉冲 → 建立观察依赖：跨周期时整块面板的码文本一起刷新（与主列表同机制）
        let pulse = CodePulse.shared.value

        return VStack(spacing: 0) {
            searchField
            Divider1px()
            content(pulse: pulse)
            Divider1px()
            footer
        }
        .frame(width: 300)
        .background(Token.Palette.winBg)
        .onAppear {
            try? AppBootstrap.start(store: store)
            searchFocused = true
        }
    }

    // MARK: - 搜索

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Token.Palette.t3)

            TextField(
                "",
                text: $query,
                prompt: Text("搜索账户或发行方").foregroundStyle(Token.Palette.t3)
            )
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .focused($searchFocused)
            // 回车复制第一条命中：键盘可达的「快速取码」（PRD C3 精神）
            .onSubmit { copyFirstMatch() }

            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Token.Palette.t4)
                }
                .buttonStyle(.plain)
                .help("清空搜索")
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 34)
    }

    // MARK: - 列表

    @ViewBuilder
    private func content(pulse: Int) -> some View {
        if store.accounts.isEmpty {
            hint("还没有账户，先在主窗口添加")
        } else if selection.accounts.isEmpty {
            hint("未找到匹配的账户")
        } else {
            VStack(spacing: 0) {
                ForEach(selection.accounts) { account in
                    row(account, pulse: pulse)
                }

                if selection.hiddenCount > 0 {
                    Text("还有 \(selection.hiddenCount) 个账户 —— 输入关键词搜索")
                        .font(.system(size: 11))
                        .foregroundStyle(Token.Palette.t4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                }
            }
        }
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(Token.Palette.t3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 14)
    }

    private func row(_ account: Account, pulse: Int) -> some View {
        MenuBarRow(
            account: account,
            code: store.displayCode(for: account.id),
            // nil = 无反馈（显示倒计环）；true = 已复制；false = 复制失败
            feedback: feedback?.id == account.id
                ? (feedback?.kind == .copied)
                : nil,
            pulse: pulse,
            onCopy: { copy(account) }
        )
    }

    // MARK: - 底部

    private var footer: some View {
        HStack(spacing: 10) {
            Button(action: openMainWindow) {
                Text("打开主窗口")
                    .font(.system(size: 12))
                    .foregroundStyle(Token.Palette.accent)
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)

            Text("\(store.accounts.count) 个账户")
                .font(.system(size: 11))
                .foregroundStyle(Token.Palette.t4)
                .monospacedDigit()

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Text("退出")
                    .font(.system(size: 12))
                    .foregroundStyle(Token.Palette.t2)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
    }

    // MARK: - 动作

    /// 复制验证码（S4：30s 后自动清除；E1：失败不静默，行内提示）
    private func copy(_ account: Account) {
        guard let code = store.code(for: account.id), ClipboardGuard.shared.copy(code) else {
            showFeedback(.failed, for: account.id)
            return
        }
        showFeedback(.copied, for: account.id)
    }

    private func copyFirstMatch() {
        guard let first = selection.accounts.first else { return }
        copy(first)
    }

    private func showFeedback(_ kind: Feedback.Kind, for id: UUID) {
        feedback = Feedback(id: id, kind: kind)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            if feedback?.id == id { feedback = nil }
        }
    }

    private func openMainWindow() {
        openWindow(id: TwoWayApp.mainWindowID)
        NSApplication.shared.activate()
    }
}

// MARK: - 单行

private struct MenuBarRow: View {
    let account: Account
    let code: String?
    /// nil = 无反馈（显示倒计环）；true = 已复制；false = 复制失败
    let feedback: Bool?
    /// 换码脉冲：作为存储属性参与 diff，跨周期时本行重建（码文本刷新）
    let pulse: Int
    var onCopy: () -> Void

    var body: some View {
        Button(action: onCopy) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(account.issuerQualifiedName)
                        .font(.system(size: 12))
                        .foregroundStyle(Token.Palette.t2)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Text(code ?? "-- ----")
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .kerning(1)
                        .foregroundStyle(Token.Palette.code)
                        .monospacedDigit()
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                if let feedback {
                    Text(feedback ? "已复制" : "复制失败")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(feedback ? Token.Palette.accent : Token.Palette.dangerText)
                } else {
                    CountdownRing(
                        period: account.parameters.period,
                        size: 20,
                        strokeWidth: 2.5
                    )
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 46)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("复制「\(account.displayName)」的验证码")
    }
}
