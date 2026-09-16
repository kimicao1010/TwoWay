import SwiftUI

/// 账户详情页（PRD FR-05 / §7.5，C2-7）+ 删除确认弹窗（FR-06 / §7.6，C2-8）
struct AccountDetailView: View {
    @Bindable var store: AccountStore
    let toast: ToastCenter
    /// C2-8：删除确认弹窗是否可见（R8 由路由延迟 260ms 置真）
    var showsDeleteDialog: Bool
    var onRequestDeleteDialog: () -> Void
    var onCancelDelete: () -> Void
    /// 确认删除后回调（回列表 + toast「已删除「名称」」）
    var onDeleted: (String) -> Void

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()

    private var account: Account? { store.selectedAccount }

    var body: some View {
        VStack(spacing: 0) {
            WindowTitlebar(title: "账户详情") {
                HStack(spacing: 14) {
                    // 编辑账户（P1 backlog）：入口占位，点击明确告知
                    Button {
                        toast.show("编辑账户将在后续版本提供")
                    } label: {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Token.Palette.t2)
                    }
                    .buttonStyle(.plain)
                    .help("编辑账户")

                    Button(action: onRequestDeleteDialog) {
                        Image(systemName: "trash")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Token.Palette.dangerText)
                    }
                    .buttonStyle(.plain)
                    .help("删除账户")
                }
            }
            Divider1px()

            ScrollView {
                VStack(spacing: 16) {
                    identity
                    hero
                    metaCard
                    actions
                }
                .padding(Token.Metrics.pagePadding)
            }
            .scrollIndicators(.hidden)
        }
        .overlay {
            if showsDeleteDialog {
                deleteDialog
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.22), value: showsDeleteDialog)
    }

    // MARK: 身份区（64×64 圆角18 渐变 + 名 20 + 标识 13）

    private var identity: some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: Token.Metrics.avatarRadius)
                    .fill(
                        LinearGradient(
                            colors: [Token.Palette.avatarGradStart, Token.Palette.avatarGradEnd],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: "checkmark.shield")
                    .font(.system(size: 26, weight: .regular))
                    .foregroundStyle(.white)
            }
            .frame(width: Token.Metrics.avatarSize, height: Token.Metrics.avatarSize)
            .shadow(color: Token.Palette.avatarGradStart.opacity(0.35), radius: 8, x: 0, y: 6)

            VStack(spacing: 6) {
                Text(account?.displayName ?? "")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Token.Palette.t1)
                    .lineLimit(1)

                // 账户标识 = 发行方 + 账户名（发行方在列表面不展示，详情页给出完整身份）
                Text(identityLine)
                    .font(.system(size: 13))
                    .foregroundStyle(Token.Palette.t2)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.top, 4)
    }

    private var identityLine: String {
        guard let account else { return "" }
        if let issuer = account.issuer, !issuer.isEmpty, issuer != account.displayName {
            return "\(issuer) · \(account.displayName)"
        }
        return account.displayName
    }

    // MARK: 验证码主视觉（168 大环 / 描边 5 / 轨道 #3A3F45 / 内嵌 28 码）

    private var hero: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
            let timeState = store.timeState(for: account?.id ?? UUID())
            ZStack {
                CountdownRing(
                    progress: timeState?.progress ?? 0,
                    size: Token.Metrics.ringHeroSize,
                    strokeWidth: Token.Metrics.ringHeroStroke,
                    isWarning: timeState?.isWarning ?? false,
                    heroTrack: true   // 详情大环轨道 #3A3F45（与列表小环不同，勿混）
                )
                VStack(spacing: 8) {
                    Text(store.displayCode(for: account?.id ?? UUID()) ?? "-- ----")
                        .font(Token.Typography.codeHero)
                        .kerning(1)
                        .foregroundStyle(Token.Palette.code)
                        .monospacedDigit()
                    Text(timeState.map { "\($0.secondsRemaining) 秒后刷新" } ?? "--")
                        .font(.system(size: 11))
                        .foregroundStyle(Token.Palette.t3)
                }
            }
        }
        .frame(width: Token.Metrics.ringHeroSize, height: Token.Metrics.ringHeroSize)
    }

    // MARK: 参数卡（账户类型 / 算法 / 位数 / 周期 / 添加时间）

    private var metaCard: some View {
        VStack(spacing: 12) {
            if let account {
                metaRow(key: "账户类型", value: "基于时间（TOTP）")
                metaRow(key: "哈希算法", value: account.parameters.algorithm.displayValue)
                metaRow(key: "验证码位数", value: "\(account.parameters.digits) 位")
                metaRow(key: "刷新周期", value: "\(Int(account.parameters.period)) 秒")
                metaRow(
                    key: "添加时间",
                    value: Self.dateFormatter.string(from: account.addedAt)
                )
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Token.Palette.card)
        .overlay(
            RoundedRectangle(cornerRadius: Token.Metrics.primaryButtonRadius)
                .stroke(Token.Palette.cardBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Token.Metrics.primaryButtonRadius))
    }

    private func metaRow(key: String, value: String) -> some View {
        HStack(spacing: 6) {
            Text(key)
                .font(.system(size: 13))
                .foregroundStyle(Token.Palette.t2)
            Spacer(minLength: 0)
            Text(value)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Token.Palette.t1)
        }
        .frame(height: 20)
    }

    // MARK: 操作区（复制占满 + 删除 100 宽红描边）

    private var actions: some View {
        HStack(spacing: 10) {
            PrimaryButton(title: "复制验证码", action: copyCode)

            DeleteOutlineButton(action: onRequestDeleteDialog)
        }
    }

    private func copyCode() {
        guard let account, let code = store.code(for: account.id) else { return }
        toast.show(Clipboard.copyString(code) ? "验证码已复制" : "复制失败，请手动复制")
    }

    // MARK: 删除确认弹窗（FR-06：必经二次确认，文案明示不可恢复）

    private var deleteDialog: some View {
        ZStack {
            Rectangle()
                .fill(Token.Palette.scrim)   // rgba(13,13,15,.65)
                .onTapGesture(perform: onCancelDelete)

            VStack(spacing: 16) {
                Text("删除此账户？")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Token.Palette.t1)

                Text("删除后需要重新导入二维码图片或输入密钥才能恢复，该账户的验证码将立即失效。")
                    .font(.system(size: 13))
                    .lineSpacing(5)
                    .foregroundStyle(Token.Palette.t2)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    Button(action: onCancelDelete) {
                        Text("取消")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Token.Palette.t1)
                            .frame(maxWidth: .infinity)
                            .frame(height: Token.Metrics.secondaryButtonHeight)
                            .background(Token.Palette.actionDetail)
                            .clipShape(RoundedRectangle(cornerRadius: Token.Metrics.inputRadius))
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.cancelAction)

                    Button(action: confirmDelete) {
                        Text("删除")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: Token.Metrics.secondaryButtonHeight)
                            .background(Token.Palette.danger)
                            .clipShape(RoundedRectangle(cornerRadius: Token.Metrics.inputRadius))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(Token.Metrics.pagePadding)
            .frame(width: Token.Metrics.dialogWidth)
            .background(Token.Palette.dialog)
            .overlay(
                RoundedRectangle(cornerRadius: Token.Metrics.dialogRadius)
                    .stroke(Token.Palette.dialogBorder, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Token.Metrics.dialogRadius))
            .shadow(color: .black.opacity(0.5), radius: 20, x: 0, y: 16)
        }
    }

    private func confirmDelete() {
        guard let account else { return }
        let name = account.displayName
        do {
            try store.delete(id: account.id)
            onDeleted(name)
        } catch {
            toast.show("删除失败，请重试")
        }
    }
}

/// 删除描边按钮（Demo `.btn-del`：宽 100 / 高 44 / 红字红描边，悬停淡红底）
private struct DeleteOutlineButton: View {
    var action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text("删除")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Token.Palette.dangerText)
                .frame(width: 100, height: Token.Metrics.primaryButtonHeight)
                .background(hovering ? Token.Palette.dangerText.opacity(0.1) : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: Token.Metrics.primaryButtonRadius)
                        .strokeBorder(
                            Token.Palette.dangerText.opacity(hovering ? 0.6 : 0.35),
                            lineWidth: 1
                        )
                )
                .clipShape(RoundedRectangle(cornerRadius: Token.Metrics.primaryButtonRadius))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
