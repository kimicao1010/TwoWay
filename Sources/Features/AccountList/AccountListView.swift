import SwiftUI

/// 验证码列表（PRD FR-01 / FR-03 / §7.1；行交互 R1–R11）
///
/// C2-2：左滑操作已并入本页，规则实现在 `SwipeRowModel`（可单测）+
/// `SwipeableAccountRow`（手势与操作块 UI）。
struct AccountListView: View {
    @Bindable var store: AccountStore
    /// 共享 Toast（复制反馈 / 添加成功提示等，渲染在 RootView 层）
    let toast: ToastCenter
    var onAdd: () -> Void
    /// R7：左滑「详情」→ 进入详情页（切屏在 C2-7 接入）
    var onDetail: (Account) -> Void
    /// R8：左滑「删除」→ 进入详情页并自动弹删除确认（260ms 弹窗在 C2-8 接入）
    var onDelete: (Account) -> Void

    var body: some View {
        VStack(spacing: 0) {
            searchField
                .padding(.all, Token.Metrics.searchAreaPadding)

            // 验证码文本由整秒脉冲驱动（与环同一时钟源 → 换码与环重置同刻）
            AccountRows(
                store: store,
                pulse: SecondPulse.shared.value,
                onCopy: copy,
                onDetail: onDetail,
                onDelete: onDelete
            )

            footer
        }
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

            #if DEBUG
            // 调试：证明整秒脉冲在推进（生产构建不显示）
            Text("· \(SecondPulse.shared.value)")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Token.Palette.t4)
            #endif

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

    // MARK: R1 复制（成功返回 true 供行闪烁；E1 失败 toast 不静默）

    private func copy(_ account: Account) -> Bool {
        guard let code = store.code(for: account.id) else { return false }
        if Clipboard.copyString(code) {
            toast.show("验证码已复制")
            return true
        } else {
            toast.show("复制失败，请手动复制")   // E1：不静默失败
            return false
        }
    }
}

/// 行列表（滚动条隐藏，PRD FR-01 AC）
private struct AccountRows: View {
    var store: AccountStore
    /// 整秒脉冲值：变化即重算全部验证码文本（SwiftUI 观察依赖，T5）
    var pulse: Int
    var onCopy: (Account) -> Bool
    var onDetail: (Account) -> Void
    var onDelete: (Account) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(spacing: Token.Metrics.rowSpacing) {
                ForEach(store.filteredAccounts) { account in
                    SwipeableAccountRow(
                        account: account,
                        code: store.displayCode(for: account.id),
                        isOpen: store.openedRowID == account.id,
                        onTapCopy: { onCopy(account) },
                        onDetail: { onDetail(account) },
                        onDelete: { onDelete(account) },
                        onSetOpen: { store.setOpenedRow($0 ? account.id : nil) }
                    )
                }
            }
            .padding(.horizontal, Token.Metrics.listPaddingH)
            .padding(.vertical, Token.Metrics.listPaddingV)
        }
        .scrollIndicators(.hidden)
    }
}

/// 左滑容器（PRD FR-02 R2/R5/R7/R8/R9/R10）
///
/// 层次：ZStack 底层是右侧操作块（详情｜删除），上层是不透明行内容。
/// 行底色必须不透明（`#1B1C1E`），否则操作块会透出（PRD 7.2）。
private struct SwipeableAccountRow: View {
    let account: Account
    let code: String?
    let isOpen: Bool
    /// 点按复制，返回是否成功（成功 → 行闪烁 R1）
    var onTapCopy: () -> Bool
    var onDetail: () -> Void
    var onDelete: () -> Void
    /// 展开/收起 → 写回 store.openedRowID（R9 单值互斥）
    var onSetOpen: (Bool) -> Void

    @State private var model = SwipeRowModel(
        maxOffset: Token.Metrics.swipeMaxOffset,
        snapThreshold: Token.Metrics.swipeSnapThreshold,
        dragThreshold: Token.Metrics.swipeDragThreshold
    )

    /// R10：拖拽中关闭过渡（跟手），释放后恢复吸附曲线 cubic-bezier(.2,.8,.2,1)
    private var offsetAnimation: Animation? {
        model.isDragging
            ? nil
            : .timingCurve(Token.Motion.swipeCurve, duration: Token.Motion.swipeSettle)
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            actionBlock
            rowContent
        }
        // isOpen 由 AccountRows 依据 store.openedRowID 计算，
        // 它变化即 R9 互斥同步 / R7 R8 复位 / E8 切屏复位
        .onChange(of: isOpen) { _, open in
            if open {
                model.open()          // R9：本行被置为展开
            } else if !model.isDragging {
                model.close()         // R9：其他行展开 / 切屏复位时本行收起
            }
        }
    }

    // MARK: 操作块（PRD 7.2：72 宽 × 76 高 / 圆角 10 / 间距 8 / 右边距 8）

    private var actionBlock: some View {
        HStack(spacing: Token.Metrics.actionButtonSpacing) {
            ActionButton(title: "详情", background: Token.Palette.actionDetail, hoverBackground: Token.Palette.actionDetailHover) {
                // R7：行复位 + 进入详情
                onSetOpen(false)
                onDetail()
            }
            ActionButton(title: "删除", background: Token.Palette.danger, hoverBackground: Token.Palette.danger.opacity(0.92)) {
                // R8：行复位 + 进入详情并自动弹确认（弹窗时序在 C2-8 接入）
                onSetOpen(false)
                onDelete()
            }
        }
        .padding(.trailing, Token.Metrics.actionButtonSpacing)
    }

    // MARK: 行内容 + 手势

    private var rowContent: some View {
        AccountRowView(
            account: account,
            code: code,
            isOpen: isOpen,
            onTap: handleTap
        )
        .offset(x: model.offset)
        .animation(offsetAnimation, value: model.offset)
        .gesture(dragGesture)
    }

    private var dragGesture: some Gesture {
        // R4：minimumDistance 8；R4 的方向判定在 model.dragChanged 内完成
        DragGesture(minimumDistance: Token.Metrics.swipeDragThreshold)
            .onChanged { value in
                let wasDragging = model.isDragging
                model.dragChanged(value.translation)
                // R9：一旦确认为本行的横向拖拽，立即收起其他行（对齐 Demo pointerdown 行为）
                if !wasDragging && model.isDragging && !isOpen {
                    onSetOpen(false)
                }
            }
            .onEnded { _ in
                model.dragEnded()
                onSetOpen(model.isOpen)   // R3 落定后回写互斥状态
            }
    }

    /// R5/R6：点按语义 —— 展开行点按仅收起；拖拽刚结束的 click 吞掉
    private func handleTap() -> Bool {
        guard !model.shouldSuppressTap() else { return false }   // R6
        if model.isOpen || isOpen {
            onSetOpen(false)                                     // R5
            return false
        }
        return onTapCopy()                                       // R1
    }
}

/// 操作块按钮（Demo `.act-btn`：宽 72 / 圆角 10 / 13px Medium）
private struct ActionButton: View {
    let title: String
    let background: Color
    let hoverBackground: Color
    var action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(title == "删除" ? Color.white : Token.Palette.t1)
                .frame(width: Token.Metrics.actionButtonWidth, height: Token.Metrics.rowHeight)
                .background(hovering ? hoverBackground : background)
                .clipShape(RoundedRectangle(cornerRadius: Token.Metrics.rowCornerRadius))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// 单行（PRD §7.1：高 76 / 水平内边距 12 / 名 15 SemiBold / 码 22 等宽 字距 1.5）
private struct AccountRowView: View {
    let account: Account
    let code: String?
    /// 展开态行底色 = surface（Demo `.acc-row.open`）
    let isOpen: Bool
    /// 返回复制是否成功（R1：成功才闪烁 `#2E3237`）
    var onTap: () -> Bool

    @State private var hovering = false
    @State private var flashCopy = false
    @State private var flashTask: Task<Void, Never>?

    private var background: Color {
        if flashCopy { return Token.Palette.copied }
        if hovering || isOpen { return Token.Palette.surface }
        return Token.Palette.winBg
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(account.displayName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Token.Palette.t1)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .textSelection(.disabled)   // R10：禁止文本选中

                Text(code ?? "-- ----")
                    .font(.system(size: 22, weight: .medium, design: .monospaced))
                    .kerning(1.5)
                    .foregroundStyle(Token.Palette.code)
                    .monospacedDigit()
                    .lineLimit(1)
                    .textSelection(.disabled)   // R10：禁止文本选中
            }

            Spacer(minLength: 0)

            // R11：悬停才浮现复制图标；点击同样复制且不冒泡（Button 吞掉点击）
            if hovering {
                Button {
                    if onTap() { flashCopied() }
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Token.Palette.accent)
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }

            CountdownRing(
                period: account.parameters.period,
                size: Token.Metrics.ringSmallSize,
                strokeWidth: Token.Metrics.ringSmallStroke
            )
        }
        .padding(.horizontal, Token.Metrics.rowHPadding)
        .frame(maxWidth: .infinity, minHeight: Token.Metrics.rowHeight)
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: Token.Metrics.rowCornerRadius))
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeIn(duration: 0.15)) { self.hovering = hovering }
        }
        .onTapGesture {
            if onTap() { flashCopied() }
        }
    }

    /// R1：行底色闪烁 `#2E3237`，持续 650ms
    private func flashCopied() {
        flashTask?.cancel()
        flashCopy = true
        flashTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(Token.Motion.copiedFeedback * 1_000_000_000))
            guard !Task.isCancelled else { return }
            flashCopy = false
        }
    }
}
