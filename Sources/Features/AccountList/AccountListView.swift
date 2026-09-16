import SwiftUI

/// 验证码列表（PRD FR-01 / FR-03 / §7.1；行交互 R1 / R11）
///
/// 左滑操作（R2–R11）单独成卡 C2-2，本页不含。
struct AccountListView: View {
    @Bindable var store: AccountStore
    var onAdd: () -> Void

    @State private var toast = ToastCenter()

    var body: some View {
        VStack(spacing: 0) {
            searchField
                .padding(.all, Token.Metrics.searchAreaPadding)

            // T3/T5：单一时钟源驱动全部验证码与倒计环，30Hz 已足够平滑（P-1）
            // 空列表时暂停时钟，避免空转耗 CPU
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: store.filteredAccounts.isEmpty)) { context in
                AccountRows(store: store, now: context.date) { account in
                    copy(account)
                }
            }

            footer
        }
        .overlay(alignment: .bottom) {
            if let toast = toast.current {
                ToastView(message: toast.message)
                    .padding(.bottom, 44)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(.easeOut(duration: 0.2), value: toast.current)
    }

    // MARK: 搜索（FR-03）

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Token.Palette.t3)
            TextField("", text: $store.searchQuery, prompt: Text("搜索账户或发行方").foregroundStyle(Token.Palette.t3))
                .textFieldStyle(.plain)
                .font(Token.Typography.body)
        }
        .padding(.horizontal, 9)
        .frame(height: Token.Metrics.searchFieldHeight)
        .background(Token.Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: Token.Metrics.searchFieldRadius))
    }

    // MARK: 底部栏（§7.1）

    private var footer: some View {
        HStack {
            Text(store.countText)
                .font(Token.Typography.caption)
                .foregroundStyle(Token.Palette.t3)

            Spacer(minLength: 0)

            Button(action: onAdd) {
                HStack(spacing: 7) {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .semibold))
                    Text("添加账户")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundStyle(Token.Palette.onAccent)
                .padding(.horizontal, 16)
                .frame(height: Token.Metrics.addButtonHeight)
                .background(Token.Palette.accent)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Token.Metrics.footerHPadding)
        .frame(height: Token.Metrics.footerHeight)
    }

    // MARK: R1 复制

    private func copy(_ account: Account) {
        guard let code = store.code(for: account.id) else { return }
        if Clipboard.copyString(code) {
            toast.show("验证码已复制")
        } else {
            toast.show("复制失败，请手动复制")   // E1：不静默失败
        }
    }
}

/// 行列表（滚动条隐藏，PRD FR-01 AC）
private struct AccountRows: View {
    var store: AccountStore
    let now: Date
    var onTap: (Account) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(spacing: Token.Metrics.rowSpacing) {
                ForEach(store.filteredAccounts) { account in
                    AccountRowView(
                        account: account,
                        code: store.displayCode(for: account.id),
                        timeState: store.timeState(for: account.id),
                        onTap: { onTap(account) }
                    )
                }
            }
            .padding(.horizontal, Token.Metrics.listPaddingH)
            .padding(.vertical, Token.Metrics.listPaddingV)
        }
        .scrollIndicators(.hidden)
    }
}

/// 单行（PRD §7.1：高 76 / 水平内边距 12 / 名 15 SemiBold / 码 22 等宽 字距 1.5）
private struct AccountRowView: View {
    let account: Account
    let code: String?
    let timeState: TOTPTimeState?
    var onTap: () -> Void

    @State private var hovering = false

    private var background: Color {
        hovering ? Token.Palette.surface : Token.Palette.winBg
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(account.displayName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Token.Palette.t1)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(code ?? "-- ----")
                    .font(.system(size: 22, weight: .medium, design: .monospaced))
                    .kerning(1.5)
                    .foregroundStyle(Token.Palette.code)
                    .monospacedDigit()
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            // R11：悬停才浮现复制图标
            if hovering {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Token.Palette.accent)
                    .transition(.opacity)
            }

            if let timeState {
                CountdownRing(
                    progress: timeState.progress,
                    size: Token.Metrics.ringSmallSize,
                    strokeWidth: Token.Metrics.ringSmallStroke,
                    isWarning: timeState.isWarning
                )
            }
        }
        .padding(.horizontal, Token.Metrics.rowHPadding)
        .frame(maxWidth: .infinity, minHeight: Token.Metrics.rowHeight)
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: Token.Metrics.rowCornerRadius))
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeIn(duration: 0.15)) { self.hovering = hovering }
        }
        .onTapGesture(perform: onTap)
    }
}
