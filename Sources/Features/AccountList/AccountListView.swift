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
    /// R7：左滑「编辑」→ 进入编辑页（v1.8：原「详情」入口改为「编辑」）
    var onEdit: (Account) -> Void
    /// R8：左滑「删除」→ **就地**弹出删除确认（不切屏，v1.8）
    var onDelete: (Account) -> Void

    var body: some View {
        VStack(spacing: 0) {
            searchField
                .padding(.all, Token.Metrics.searchAreaPadding)

            // 验证码文本由「换码脉冲」驱动（与环同一时钟源 → 换码与环重置同刻）。
            // 列表不显示剩余秒数，故只需在换码时刷新（1 次/周期，而非 1 次/秒）。
            AccountRows(
                store: store,
                pulse: CodePulse.shared.value,
                onCopy: copy,
                onEdit: onEdit,
                onDelete: onDelete,
                onReorderFailure: { toast.show("排序保存失败，请重试") }
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
            // 调试：换码脉冲与秒脉冲（默认关闭 —— 截图/演示时不应出现调试痕迹；`--debug-pulse` 开启）
            if DebugFlags.showsPulseCounter {
                Text("· \(CodePulse.shared.value)/\(SecondPulse.shared.value)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Token.Palette.t4)
            }
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

    // MARK: R1 复制（成功返回 true 供行闪烁；E1 失败 toast 不静默；S4 到期自动清除）

    private func copy(_ account: Account) -> Bool {
        guard let code = store.code(for: account.id) else { return false }
        if ClipboardGuard.shared.copy(code) {
            toast.show("已复制")   // R1：底部反馈
            return true
        } else {
            toast.show("复制失败，请手动复制")   // E1：不静默失败
            return false
        }
    }
}

/// 列表的命名坐标系：拖动/左滑的位移在**这里**测量，而非行自身（DR-01 抖动修复）
///
/// 挂在滚动容器上（而非内容上）：即使内容因滚动而位移，坐标系仍然稳定；
/// 而行的拖动位移（祖先 offset）不会影响它 —— 这正是消除反馈回路的关键。
enum AccountListCoordinateSpace {
    static let name = "accountList"
}

/// 行列表（滚动条隐藏，PRD FR-01 AC）
private struct AccountRows: View {
    var store: AccountStore
    /// 换码脉冲值：变化即重算全部验证码文本（SwiftUI 观察依赖，T5）
    var pulse: Int
    var onCopy: (Account) -> Bool
    var onEdit: (Account) -> Void
    var onDelete: (Account) -> Void
    /// DR-01：排序落盘失败时的提示（不静默）
    var onReorderFailure: () -> Void

    /// 拖动排序会话状态
    @State private var reorder = ListReorderModel()

    private var rows: [Account] { store.filteredAccounts }

    /// 搜索过滤时不支持拖动排序：「插到某条前后」在过滤视图里对应的全量位置不明确，
    /// 强行映射会让用户看到的结果与预期不符（宁可禁用，也不做猜谜式落位）。
    private var allowsReorder: Bool {
        store.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// 单行步长（行高 + 行间距）—— 固定行高让插入位可以纯算术推导，无需读几何
    private var step: CGFloat { Token.Metrics.rowHeight + Token.Metrics.rowSpacing }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: Token.Metrics.rowSpacing) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, account in
                    let isDragging = reorder.draggingID == account.id

                    SwipeableAccountRow(
                        account: account,
                        code: store.displayCode(for: account.id),
                        isOpen: store.openedRowID == account.id,
                        isReordering: isDragging,
                        allowsReorder: allowsReorder,
                        reorderModel: reorder,
                        onTapCopy: { onCopy(account) },
                        onEdit: { onEdit(account) },
                        onDelete: { onDelete(account) },
                        onSetOpen: { store.setOpenedRow($0 ? account.id : nil) },
                        onReorderBegin: { beginReorder(account, at: index) },
                        onReorderChange: { translationY in reorder.update(translationY: translationY) },
                        onReorderEnd: endReorder
                    )
                    // 让位：只在跨格时变化 → 带动画。
                    // ⚠️ 拖动行**跟随光标**的位移不在这里（在行内部，且绝不能带动画）：
                    // 二者若共用一个 offset + 同一个 .animation，跨格时会重新平滑拖动行自身 → 抖动。
                    .offset(y: reorder.shift(forRowAt: index))
                    .animation(.easeOut(duration: 0.18), value: reorder.insertionIndex)
                    .zIndex(isDragging ? 1 : 0)
                }
            }
            .padding(.horizontal, Token.Metrics.listPaddingH)
            .padding(.vertical, Token.Metrics.listPaddingV)
            .overlay(alignment: .top) { insertionIndicator }
            .onAppear {
                #if DEBUG
                // --debug-reorder-drag：注入「第 1 行被往下拖两行」的状态，便于截图核对视觉
                if DebugFlags.simulatesReorderDrag, !reorder.isActive, rows.count > 2 {
                    reorder.begin(
                        id: rows[0].id,
                        originIndex: 0,
                        step: step,
                        count: rows.count,
                        hysteresis: Token.Metrics.reorderHysteresis
                    )
                    reorder.update(translationY: step * 2 + 6)
                    RowTrace.log(
                        "debug-reorder injected dragged=\(rows[0].displayName) step=\(step) "
                        + "order=[\(rows.map(\.displayName).joined(separator: ","))]"
                    )
                }
                // --debug-drag-script：脚本化拖动一段距离（带 ±3px 抖动，专踩格子边界），
                // 自报落点变化序列与主线程 tick 偏差 —— 用于验证「无抖动」是可复现的事实
                if DebugFlags.runsReorderDragScript, !reorder.isActive, rows.count > 2 {
                    runDragScript()
                }
                #endif
            }
        }
        // 铁律：滚动容器一律 `.never` —— 不创建 scroller（has=0 / scroller=nil / 占位 0px）。
        // 勿改回 `.hidden`：它只把滚动条藏起来，占位与创建照旧（实测挤压裁剪区 17px，
        // 会使内容左右微移）。取证：`--scroll-probe <path>`（DEBUG 自报 NSScrollView 几何）。
        .scrollIndicators(.never)
        // 拖动/左滑的位移测量坐标系（DR-01：见 AccountListCoordinateSpace 说明）
        .coordinateSpace(name: AccountListCoordinateSpace.name)
    }

    /// 插入位指示线（只在真正会改变顺序时出现）
    ///
    /// 线画在**落点槽位的上沿**（而不是原始缝隙），这样用户看到的线与行实际落下的位置一致。
    @ViewBuilder
    private var insertionIndicator: some View {
        if reorder.hasPendingMove, let landing = reorder.landingIndex {
            RoundedRectangle(cornerRadius: Token.Metrics.reorderIndicatorHeight / 2)
                .fill(Token.Palette.accent)
                .frame(height: Token.Metrics.reorderIndicatorHeight)
                .padding(.horizontal, Token.Metrics.listPaddingH + Token.Metrics.rowHPadding)
                .offset(y: indicatorY(forLanding: landing))
                .allowsHitTesting(false)
        }
    }

    private func indicatorY(forLanding landing: Int) -> CGFloat {
        max(
            Token.Metrics.listPaddingV - Token.Metrics.rowSpacing / 2,
            Token.Metrics.listPaddingV + CGFloat(landing) * step - Token.Metrics.rowSpacing / 2
                - Token.Metrics.reorderIndicatorHeight / 2
        )
    }

    // MARK: - DR-01 拖动排序

    private func beginReorder(_ account: Account, at index: Int) {
        store.setOpenedRow(nil)   // 先收起左滑，避免「左滑位移 + 拖动位移」叠加
        reorder.begin(
            id: account.id,
            originIndex: index,
            step: step,
            count: rows.count,
            hysteresis: Token.Metrics.reorderHysteresis
        )
        #if DEBUG
        RowTrace.log(
            "reorder begin id=\(account.displayName) origin=\(index) count=\(rows.count) "
            + "order=[\(rows.map(\.displayName).joined(separator: ","))]"
        )
        #endif
    }

    #if DEBUG
    /// 脚本化拖动（`--debug-drag-script`）：1.6 秒内平滑下拖约 2.5 格，
    /// 并叠加 ±3pt 抖动（振幅略小于滞回余量），专门踩在跨格边界上。
    ///
    /// 期望：落点单调推进（不来回翻转），tick 偏差小 → 证明「边界抖动」已被滞回消除。
    private func runDragScript() {
        reorder.begin(
            id: rows[0].id,
            originIndex: 0,
            step: step,
            count: rows.count,
            hysteresis: Token.Metrics.reorderHysteresis
        )
        RowTrace.log("drag-script begin rows=\(rows.count) step=\(step)")

        Task { @MainActor in
            let intervalMs = 8.0
            let totalMs = 3000.0
            var elapsed = 0.0
            var lastLanding = reorder.landingIndex
            var transitions: [String] = []
            var maxTickMs = 0.0
            var maxTickAt = 0.0
            var lateMaxTickMs = 0.0          // 后半段（跳过启动期抖动）的最差 tick

            while elapsed < totalMs {
                let start = Date()
                let base = elapsed * 0.07                       // 3s → ≈210pt ≈ 2.7 格
                let jitter = sin(elapsed / 6) * 3               // ±3pt 边界抖动
                reorder.update(translationY: CGFloat(base + jitter))

                if reorder.landingIndex != lastLanding {
                    let from = lastLanding.map(String.init) ?? "-"
                    let to = reorder.landingIndex.map(String.init) ?? "-"
                    transitions.append("\(from)>\(to)")
                    lastLanding = reorder.landingIndex
                }

                try? await Task.sleep(nanoseconds: UInt64(intervalMs * 1_000_000))
                let tick = Date().timeIntervalSince(start) * 1000
                if tick > maxTickMs {
                    maxTickMs = tick
                    maxTickAt = elapsed
                }
                if elapsed > totalMs / 2 {
                    lateMaxTickMs = max(lateMaxTickMs, tick)
                }
                elapsed += intervalMs
            }

            // 来回翻转会让 transitions 里出现 A>B>A 模式；单调推进则只应看到单向前进
            let flips = zip(transitions, transitions.dropFirst()).filter { lhs, rhs in
                lhs.hasPrefix(String(rhs.suffix(1))) && lhs.hasSuffix(String(rhs.prefix(1)))
            }.count

            RowTrace.log(
                "drag-script done transitions=[\(transitions.joined(separator: ","))] "
                + "backFlips=\(flips) maxTickMs=\(String(format: "%.1f", maxTickMs))@\(String(format: "%.0f", maxTickAt))ms "
                + "lateMaxTickMs=\(String(format: "%.1f", lateMaxTickMs)) "
                + "finalLanding=\(reorder.landingIndex.map(String.init) ?? "nil")"
            )
            reorder.end()
        }
    }
    #endif

    /// 落定：把拖动行放到插入位对应的目标行之前/之后
    private func endReorder() {
        defer { reorder.end() }

        // 防线：位移未达激活阈值就结束的会话不提交（手势被系统取消 / 视图重建 /
        // 调试注入等情况下会走到这里，若不拦住会**悄悄改掉用户排好的顺序**）
        guard abs(reorder.offsetY) >= Token.Metrics.reorderActivation,
              reorder.hasPendingMove,
              let insertion = reorder.insertionIndex,
              let draggingID = reorder.draggingID
        else { return }

        let origin = reorder.originIndex
        let target: (id: UUID, position: ReorderLogic.Position)

        if insertion > origin + 1 {
            // 向下拖：落到「插入位前一行」之后
            guard insertion - 1 < rows.count else { return }
            target = (rows[insertion - 1].id, .after)
        } else if insertion < origin {
            // 向上拖：落到「插入位那一行」之前
            guard insertion < rows.count else { return }
            target = (rows[insertion].id, .before)
        } else {
            return
        }

        #if DEBUG
        RowTrace.log(
            "reorder end origin=\(origin) insertion=\(insertion) target=\(target.position) "
            + "dy=\(reorder.offsetY)"
        )
        #endif

        do {
            try store.move(id: draggingID, relativeTo: target.id, position: target.position)
        } catch {
            onReorderFailure()   // E1 精神：失败不静默
        }
    }
}

/// 左滑容器（PRD FR-02 R2/R5/R7/R8/R9/R10）
///
/// 层次：ZStack 底层是右侧操作块（编辑｜删除），上层是不透明行内容。
/// 行底色必须不透明（`#1B1C1E`），否则操作块会透出（PRD 7.2）。
private struct SwipeableAccountRow: View {
    let account: Account
    let code: String?
    let isOpen: Bool
    /// DR-01：本行正在被拖动排序
    let isReordering: Bool
    /// DR-01：当前是否允许拖动排序（搜索过滤中禁用）
    let allowsReorder: Bool
    /// DR-01：拖动会话（**只有被拖动的那一行**会读它的 `offsetY`，避免整表每帧重算）
    let reorderModel: ListReorderModel
    /// 点按复制，返回是否成功（成功 → 行闪烁 R1）
    var onTapCopy: () -> Bool
    var onEdit: () -> Void
    var onDelete: () -> Void
    /// 展开/收起 → 写回 store.openedRowID（R9 单值互斥）
    var onSetOpen: (Bool) -> Void
    /// DR-01：拖动排序回调
    var onReorderBegin: () -> Void
    var onReorderChange: (CGFloat) -> Void
    var onReorderEnd: () -> Void

    @State private var model = SwipeRowModel(
        maxOffset: Token.Metrics.swipeMaxOffset,
        snapThreshold: Token.Metrics.swipeSnapThreshold,
        dragThreshold: Token.Metrics.swipeDragThreshold
    )
    /// DR-01：排序刚结束的瞬间系统可能补发一次 click，需吞掉（与 R6 同理）
    @State private var lastReorderEnd: Date?

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
        // DR-01：跟手位移。**绝不加任何动画**（`.animation` 会在每次落点变化时
        // 重新平滑这一行的位置，光标却仍在移动 → 表现为拖动行剧烈抖动）。
        // 同时该读取只在本行被拖动时发生 → Observation 依赖范围限定在这一行，
        // 列表其余行不会随鼠标每移动一像素就重算 body。
        .offset(y: isReordering ? reorderModel.offsetY : 0)
        // DR-01：拖动中的行「抬起」——轻微放大 + 投影，明确区分于原位行
        .scaleEffect(isReordering ? 1.02 : 1)
        .shadow(
            color: isReordering ? Color.black.opacity(0.5) : .clear,
            radius: isReordering ? 10 : 0,
            y: isReordering ? 5 : 0
        )
        // 首帧即已展开（如调试钩子 / 状态预设）：直接对齐，避免
        // `onChange` 不触发导致「store 说展开、视觉没展开」的不一致
        .onAppear {
            #if DEBUG
            RowTrace.log("appear \(account.displayName) isOpen=\(isOpen) offset=\(model.offset)")
            #endif
            if isOpen { model.open() }
        }
        #if DEBUG
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear {
                        RowTrace.log("zstack \(account.displayName) w=\(geo.size.width) h=\(geo.size.height)")
                    }
            }
        )
        .onChange(of: model.offset) { old, new in
            if abs(old) > 0.01 || abs(new) > 0.01 {
                RowTrace.log("offset \(account.displayName) \(old) → \(new) phase=\(model.phase)")
            }
        }
        #endif
        // isOpen 由 AccountRows 依据 store.openedRowID 计算，
        // 它变化即 R9 互斥同步 / R7 R8 复位 / E8 切屏复位
        .onChange(of: isOpen) { _, open in
            #if DEBUG
            RowTrace.log("isOpen \(account.displayName) → \(open) offset=\(model.offset)")
            #endif
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
            ActionButton(title: "编辑", background: Token.Palette.actionDetail, hoverBackground: Token.Palette.actionDetailHover) {
                // R7：行复位 + 进入编辑页（v1.8：原「详情」入口改为「编辑」）
                onSetOpen(false)
                onEdit()
            }
            ActionButton(title: "删除", background: Token.Palette.danger, hoverBackground: Token.Palette.danger.opacity(0.92)) {
                // R8：行复位 + 就地弹出删除确认（不切屏，v1.8）
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
            isReordering: isReordering,
            onTap: handleTap
        )
        .offset(x: model.offset)
        .animation(offsetAnimation, value: model.offset)
        .gesture(dragGesture)
    }

    /// 统一拖动手势（DR-01 v1.10）
    ///
    /// **竖直 → 拖动排序，水平 → 左滑**，由方向 + 距离双重判定分流：
    /// - 水平且 |dx| > 8（`swipeDragThreshold`）→ 走 `SwipeRowModel`（原 R2–R4）
    /// - 竖直且 |dy| ≥ 24（`reorderActivation`）→ 走排序会话
    /// - 两者都不满足（小幅抖动 / 轻点）→ 不做任何事，点击仍走 `onTapGesture`
    ///
    /// macOS 上鼠标拖动**不会滚动** NSScrollView（滚动靠滚轮/触控板），
    /// 所以这里与列表滚动天然不冲突，无需长按等额外门槛。
    private var dragGesture: some Gesture {
        // ⚠️ 必须用**稳定的命名坐标系**，不能用默认的 `.local`：
        // 拖动排序时整行被 offset（祖先视图的几何变换），行的 local 坐标系会随之移动，
        // 于是「位移 = 光标位置 − 起点」里的光标位置被行自身位移抵消 → 行弹回原位 → 再跟手，
        // 形成每帧一次的锯齿抖动（实测 dy: -26, -2, -28, -4, -28…，locY 在两个值间跳）。
        // 挂到列表容器的命名坐标系后，测量不再受行自身位移影响（左滑同样受益）。
        DragGesture(
            minimumDistance: Token.Metrics.swipeDragThreshold,
            coordinateSpace: .named(AccountListCoordinateSpace.name)
        )
            .onChanged { value in
                let dx = value.translation.width
                let dy = value.translation.height

                // 已在排序会话中：只更新位移
                if isReordering {
                    #if DEBUG
                    // 取证（`--debug-drag-trace`）：真实手势下 dy 是否单调。同时上报 start/location ——
                    // 若 startLocation 恒定而 location 在两个值之间跳，说明测量坐标系自身在动
                    // （自指反馈回路，v1.13 的抖动根因）。默认关闭：每事件写盘会干扰手感。
                    if DebugFlags.tracesDragEvents {
                        RowTrace.log(
                            "drag \(account.displayName) dy=\(Int(dy)) "
                            + "startY=\(Int(value.startLocation.y)) locY=\(Int(value.location.y))"
                        )
                    }
                    #endif
                    onReorderChange(dy)
                    return
                }

                if allowsReorder,
                   ReorderLogic.isVerticalReorder(
                       dx: dx,
                       dy: dy,
                       activation: Token.Metrics.reorderActivation
                   ) {
                    // 排序前先收起左滑，避免两种位移叠加
                    model.close()
                    onReorderBegin()
                    onReorderChange(dy)
                    return
                }

                // R4：水平拖拽（方向判定在 model.dragChanged 内完成）
                let wasDragging = model.isDragging
                model.dragChanged(value.translation)
                // R9：一旦确认为本行的横向拖拽，立即收起其他行（对齐 Demo pointerdown 行为）
                if !wasDragging && model.isDragging && !isOpen {
                    onSetOpen(false)
                }
            }
            .onEnded { _ in
                if isReordering {
                    lastReorderEnd = Date()   // 吞掉紧随其后的 click（与 R6 同思路）
                    onReorderEnd()
                    return
                }
                model.dragEnded()
                onSetOpen(model.isOpen)   // R3 落定后回写互斥状态
            }
    }

    /// R5/R6/DR-01：点按语义 —— 展开行点按仅收起；拖拽（左滑或排序）刚结束的 click 吞掉
    private func handleTap() -> Bool {
        guard !model.shouldSuppressTap() else { return false }   // R6
        if let last = lastReorderEnd, Date().timeIntervalSince(last) < 0.15 {
            return false                                         // DR-01：排序落定后的补发 click
        }
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
    /// DR-01：拖动排序中（底色提亮，配合外层的投影做出「抬起」观感）
    let isReordering: Bool
    /// 返回复制是否成功（R1：成功才闪烁 `#2E3237`）
    var onTap: () -> Bool

    @State private var hovering = false
    @State private var flashCopy = false
    @State private var flashTask: Task<Void, Never>?

    private var background: Color {
        if flashCopy { return Token.Palette.copied }
        if isReordering { return Token.Palette.actionDetail }   // DR-01：拖动中提亮（#2E3237）
        if hovering || isOpen { return Token.Palette.surface }
        return Token.Palette.winBg
    }

    /// 账户标题：`发行方：账户名`；发行方缺失或与名称相同时只显示名称
    private var titleLine: Text {
        let name = Text(account.displayName)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Token.Palette.t1)

        guard let issuer = account.issuer,
              !issuer.isEmpty,
              issuer != account.displayName
        else { return name }

        return Text(issuer)
            .font(.system(size: 15, weight: .regular))
            .foregroundStyle(Token.Palette.t2)
            + Text("：")
            .font(.system(size: 15))
            .foregroundStyle(Token.Palette.t3)
            + name
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                // 账户标题：`发行方：账户名`（发行方次要色、账户名主色；无发行方时只显示名称）
                titleLine
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
