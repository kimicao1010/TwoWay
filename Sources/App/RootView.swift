import SwiftUI

/// 窗口根视图（PRD G-01/G-03：400×732 固定尺寸 + 52pt 自绘标题栏）
///
/// 屏幕路由由 `AppRouter` 驱动（TECH_PLAN §3）；共享 Toast 渲染在本层，
/// 列表（复制反馈）与添加页（已添加提示）共用同一个 `ToastCenter`。
struct RootView: View {
    /// 由 `TwoWayApp` 持有并注入：与状态栏下拉共用同一实例（单一数据源）
    let store: AccountStore
    /// 应用偏好（隐藏 Dock 图标等）
    let settings: AppSettings

    @State private var router = AppRouter()
    @State private var toast = ToastCenter()
    /// U3：DEBUG 调试切屏用（--debug-import）
    @State private var debugInitialMethod: AddAccountView.Method = .manual
    /// DEBUG：load 失败时把错误码亮在界面上（排查生产 Keychain 路径用）
    @State private var loadErrorText: String?
    /// DEBUG：把切屏淡入淡出时长放大（`--slow-transition <秒>`），让 260ms 级瞬态可被截图取证
    @State private var screenFadeOverride: Double?
    /// DEBUG：列表是否仍用 `.opacity` 过渡（`--list-transition-opacity`）—— 用于 A/B 取证，默认已修好
    @State private var listUsesOpacityTransition = false
    /// 备份弹窗内的错误文案（口令错误 / 文件损坏等，就地提示不静默）
    @State private var backupSheetError: String?
    /// 调试用：打开状态栏面板预览窗（`--debug-menubar`）
    @Environment(\.openWindow) private var openWindow
    /// 打开偏好设置（⌘, 同款入口）
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        ZStack {
            switch router.screen {
            case .list:
                // 列表**不做淡入淡出**（`.identity`）。
                //
                // 根因（2026-09-17 取证）：`.opacity` 过渡会把透明度逐个施加到子树里的视图，
                // 行底 alpha<1 时，ZStack 底层那张操作块（编辑｜删除）就会**透出来** ——
                // 表现为「从子页回到主页时所有行闪现两个按钮」。行偏移始终为 0（`--row-trace` 日志
                // 无任何 offset 变化），故与左滑状态无关，是纯合成问题。
                // `.identity` 让列表「先就位、再让子页淡出」，既无透出，观感也更稳。
                listScreen
                    .transition(listUsesOpacityTransition ? .opacity : .identity)

            case .addAccount:
                AddAccountView(
                    store: store,
                    toast: toast,
                    onCancel: { show(.list) },
                    onAdded: { name in
                        show(.list)
                        toast.show("已添加「\(name)」")
                    },
                    onImported: { count, skipped in
                        show(.list)
                        if skipped > 0 {
                            toast.show("已导入 \(count) 个账户（\(skipped) 个 HOTP 账户不受支持已跳过）")
                        } else {
                            toast.show("已导入 \(count) 个账户")
                        }
                    },
                    initialMethod: debugInitialMethod
                )
                .transition(.opacity)

            case .editAccount:
                // P1 C4-2：编辑选中账户；账户不存在时回落列表
                if let account = store.selectedAccount {
                    AddAccountView(
                        store: store,
                        toast: toast,
                        onCancel: { show(.list) },
                        onAdded: { _ in },
                        onImported: { _, _ in },
                        editing: AddAccountView.EditTarget(
                            account: account,
                            secretBase32: store.secretBase32(for: account.id) ?? ""
                        ),
                        onSaved: { name in
                            show(.list)
                            toast.show("已保存「\(name)」")
                        }
                    )
                    .transition(.opacity)
                } else {
                    listScreen
                }
            }

            // R8（v1.8）：删除确认**就地覆盖列表**，不再经详情页
            if let pending = pendingDeleteAccount {
                DeleteConfirmDialog(
                    accountName: pending.displayName,
                    onCancel: { router.pendingDeleteID = nil },
                    onConfirm: confirmDelete
                )
                .transition(.opacity)
            }
        }
        .animation(
            .easeInOut(duration: screenFadeOverride ?? Token.Motion.screenTransition),
            value: router.screen
        )
        .animation(.easeOut(duration: 0.22), value: router.pendingDeleteID)
        // Esc：有删除确认弹窗时先关弹窗（PRD §7.2 R8）
        .onExitCommand {
            if router.pendingDeleteID != nil {
                router.pendingDeleteID = nil
            }
        }
        // R9/E8：切屏时全部行复位
        .overlay(alignment: .bottom) {
            if let current = toast.current {
                ToastView(message: current.message)
                    .padding(.bottom, 44)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(.easeOut(duration: 0.2), value: toast.current)
        .sheet(isPresented: isBackupSheetPresented) {
            backupSheetContent
        }
        .frame(minWidth: WindowMetrics.width, maxWidth: WindowMetrics.width)
        .frame(minHeight: Token.Metrics.designedContentHeight, maxHeight: .infinity)
        .background(Token.Palette.winBg)
        // 窗口底角由我们自绘 12px（G-02）。
        // 顶角仍由系统裁（≈13px），与 12px 差 1px，肉眼不可辨。
        .clipShape(RoundedRectangle(cornerRadius: Token.Metrics.windowCornerRadius))
        .background(WindowConfigurator())
        .ignoresSafeArea()
        .overlay(alignment: .top) {
            #if DEBUG
            if let loadErrorText {
                Text("load: \(loadErrorText)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Token.Palette.dangerText)
                    .padding(.top, 56)
            }
            #endif
        }
        .onAppear {
            // ⌘W：把系统 File ▸ Close 接管成 close()（D10 隐藏关闭按钮后 performClose 必然是空操作）
            CloseWindowMenu.install()
            // SwiftUI 可能稍后才建好/重建主菜单，再补一次（幂等）
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 800_000_000)
                CloseWindowMenu.install()
            }
            // 幂等引导：全局时钟 + 首次读盘（状态栏下拉也会触发，故必须幂等）
            do {
                try AppBootstrap.start(store: store, settings: settings)
                loadErrorText = nil
            } catch {
                #if DEBUG
                loadErrorText = String(describing: error)
                #endif
            }
            // U3：开发期调试切屏入口（仅 DEBUG 生效）
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--debug-add") {
                router.screen = .addAccount
            }
            if ProcessInfo.processInfo.arguments.contains("--debug-import") {
                router.screen = .addAccount
                debugInitialMethod = .importImage
            }
            // --debug-delete-dialog：在列表上直开删除确认弹窗（回归截图用）
            if ProcessInfo.processInfo.arguments.contains("--debug-delete-dialog") {
                router.pendingDeleteID = store.accounts.first?.id
            }
            // --debug-open-row：强制展开首行，便于截图核对左滑操作块（无辅助功能权限时无法程序化拖拽）
            if ProcessInfo.processInfo.arguments.contains("--debug-open-row") {
                store.setOpenedRow(store.accounts.first?.id)
            }
            // --debug-edit：直进编辑屏
            if ProcessInfo.processInfo.arguments.contains("--debug-edit") {
                store.selectedAccountID = store.accounts.first?.id
                router.screen = .editAccount
            }
            // --debug-backup-export / --debug-backup-import：直开备份弹窗
            if ProcessInfo.processInfo.arguments.contains("--debug-backup-export") {
                router.backupSheet = .export
            }
            if ProcessInfo.processInfo.arguments.contains("--debug-backup-import") {
                router.backupSheet = .importBackup
            }
            // --debug-toast：验证 toast 渲染（复制反馈等）
            if ProcessInfo.processInfo.arguments.contains("--debug-toast") {
                toast.show("已复制")
            }
            // --debug-close-window：延时走一次 performClose（⌘W 的底层链路，无法程序化发按键）
            if ProcessInfo.processInfo.arguments.contains("--debug-close-window") {
                Task { @MainActor in
                    // 先激活：未激活窗口的标准按钮会被 AppKit 灰掉（isEnabled 读回来是 false），
                    // 不激活就量不出真实状态
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    NSApplication.shared.activate()
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    let managers = NSApplication.shared
                    // 优先取「有标题且可见」的主窗口（app 未激活时 mainWindow 可能为 nil）
                    let target = managers.mainWindow
                        ?? managers.windows.first { $0.isVisible && $0.title == "2way" }
                        ?? managers.windows.first { $0.isVisible }
                    if let target {
                        // 走**真实菜单项**的动作 —— 与按下 ⌘W 完全同一条链路
                        let item = CloseWindowMenu.currentCloseItem()
                        let button = target.standardWindowButton(.closeButton)
                        RowTrace.log(
                            "close-probe before: window=\(ObjectIdentifier(target)) "
                            + "closeBtnHidden=\(button?.isHidden.description ?? "n/a") "
                            + "closeBtnEnabled=\(button?.isEnabled.description ?? "n/a") "
                            + "menuItemTitle='\(item?.title ?? "nil")' "
                            + "patched=\(item?.action == #selector(CloseWindowMenu.closeKeyWindow(_:))) "
                            + "isVisible=\(target.isVisible)"
                        )
                        if let item, let action = item.action {
                            NSApplication.shared.sendAction(action, to: item.target, from: item)
                        }
                        try? await Task.sleep(nanoseconds: 1_000_000_000)
                        RowTrace.log(
                            "close-probe after: isVisible=\(target.isVisible) "
                            + "visibleWindows=\(managers.windows.filter(\.isVisible).count)"
                        )
                    } else {
                        RowTrace.log("close-probe: no target window")
                    }
                }
            }
            // --debug-close-window：启动后关掉主窗口**一次**（回归「关闭态 → 状态栏打开主窗口」）
            if DebugFlags.closesMainWindowAtLaunch, !DebugFlags.didCloseMainWindowOnce {
                DebugFlags.didCloseMainWindowOnce = true
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    CloseWindowMenu.shared.closeKeyWindow(nil)
                }
            }
            // --debug-menubar：打开状态栏面板的预览窗口（面板本体在系统菜单栏，截图工具无法定位）
            if ProcessInfo.processInfo.arguments.contains("--debug-menubar") {
                openWindow(id: TwoWayApp.menuBarPreviewWindowID)
            }
            // --debug-settings：打开偏好设置（截图/回归用）
            // 延后一拍 + 先激活：onAppear 阶段 Settings scene 可能尚未就绪
            if ProcessInfo.processInfo.arguments.contains("--debug-settings") {
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 1_200_000_000)
                    NSApplication.shared.activate()
                    openSettings()
                }
            }
            // --scroll-probe <path>：把窗口内所有 NSScrollView 的几何自报到 JSON（滚动条取证）
            if let index = ProcessInfo.processInfo.arguments.firstIndex(of: "--scroll-probe"),
               index + 1 < ProcessInfo.processInfo.arguments.count {
                ScrollProbe.schedule(outputPath: ProcessInfo.processInfo.arguments[index + 1])
            }
            // --row-trace <path>：行偏移/展开态/切屏时序自报（行闪现取证）
            if let index = ProcessInfo.processInfo.arguments.firstIndex(of: "--row-trace"),
               index + 1 < ProcessInfo.processInfo.arguments.count {
                RowTrace.enable(path: ProcessInfo.processInfo.arguments[index + 1])
                RowTrace.log("trace enabled")
            }
            // --slow-transition <秒>：放慢切屏淡入淡出，让 260ms 级瞬态可被截图取证
            if let index = ProcessInfo.processInfo.arguments.firstIndex(of: "--slow-transition"),
               index + 1 < ProcessInfo.processInfo.arguments.count,
               let seconds = Double(ProcessInfo.processInfo.arguments[index + 1]) {
                screenFadeOverride = seconds
            }
            // --list-transition-opacity：A/B 复现用（让列表回到「.opacity 过渡」的旧行为）
            if ProcessInfo.processInfo.arguments.contains("--list-transition-opacity") {
                listUsesOpacityTransition = true
            }
            // --debug-flip-screens [--flip-interval <秒>]：自驱列表 ↔ 添加页往返
            if ProcessInfo.processInfo.arguments.contains("--debug-flip-screens") {
                var interval: Double = 1.2
                if let index = ProcessInfo.processInfo.arguments.firstIndex(of: "--flip-interval"),
                   index + 1 < ProcessInfo.processInfo.arguments.count,
                   let seconds = Double(ProcessInfo.processInfo.arguments[index + 1]) {
                    interval = seconds
                }
                Task { @MainActor in
                    var goToAdd = true
                    while true {
                        try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                        show(goToAdd ? .addAccount : .list)
                        goToAdd.toggle()
                    }
                }
            }
            // --debug-import-file <path>：启动即模拟「拖入图片解码 → 导入」完整链路
            // （手工回归用：免掉无障碍权限下无法程序化拖放的局限）
            if let index = ProcessInfo.processInfo.arguments.firstIndex(of: "--debug-import-file"),
               index + 1 < ProcessInfo.processInfo.arguments.count {
                let path = ProcessInfo.processInfo.arguments[index + 1]
                importImageForDebug(at: path)
            }
            #endif
        }
    }

    // MARK: 屏幕

    private var listScreen: some View {
        VStack(spacing: 0) {
            WindowTitlebar(title: "TwoWay 密钥生成器") {
                // PRD §7.1：标题栏右侧上下文操作为「更多」（三点）
                Menu {
                    Button("导出加密备份…") {
                        backupSheetError = nil
                        router.backupSheet = .export
                    }
                    Button("从备份导入…") {
                        backupSheetError = nil
                        router.backupSheet = .importBackup
                    }
                    Divider()
                    Button("偏好设置…") {
                        openSettings()
                    }
                    Divider()
                    Button("导出 GA 迁移码（PNG）…") {
                        backupSheetError = nil
                        router.backupSheet = .exportGAMigration
                    }
                    Divider()
                    // D10：系统交通灯已移除，这里补图形化入口（⌘W 同样有效，链路见 CloseWindowMenu）
                    Button("关闭窗口") {
                        CloseWindowMenu.shared.closeKeyWindow(nil)
                    }
                    Divider()
                    // D10：系统「关闭」按钮已移除，这里是图形化的退出入口（另有 Cmd+W / Cmd+Q）
                    Button("退出 2way") {
                        NSApplication.shared.terminate(nil)
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Token.Palette.t2)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("更多")
            }
            Divider1px()

            AccountListView(
                store: store,
                toast: toast,
                onAdd: { show(.addAccount) },
                onEdit: { account in
                    // R7：行复位 + 进编辑页
                    store.selectedAccountID = account.id
                    show(.editAccount)
                },
                onDelete: { account in
                    // R8（v1.8）：不切屏，就地弹确认
                    store.selectedAccountID = account.id
                    router.pendingDeleteID = account.id
                }
            )
        }
    }

    private func show(_ screen: AppRouter.Screen) {
        store.setOpenedRow(nil)   // R9/E8：离开列表屏时行复位
        #if DEBUG
        RowTrace.log("show \(screen)")
        #endif
        router.screen = screen
    }

    /// 待确认删除的账户（E2：已被删掉时弹窗自然消失）
    private var pendingDeleteAccount: Account? {
        guard let id = router.pendingDeleteID else { return nil }
        return store.accounts.first { $0.id == id }
    }

    /// FR-06：确认删除 → 就地执行 + toast（不离开列表）
    private func confirmDelete() {
        defer { router.pendingDeleteID = nil }
        guard let pending = pendingDeleteAccount else { return }
        do {
            try store.delete(id: pending.id)
            toast.show("已删除「\(pending.displayName)」")
        } catch {
            toast.show("删除失败，请重试")
        }
    }

    // MARK: 备份（C4-3）

    private var isBackupSheetPresented: Binding<Bool> {
        Binding(
            get: { router.backupSheet != nil },
            set: { presented in
                if !presented { dismissBackupSheet() }
            }
        )
    }

    @ViewBuilder private var backupSheetContent: some View {
        switch router.backupSheet {
        case .export:
            BackupExportSheet(
                accounts: store.accounts,
                errorMessage: $backupSheetError,
                onCancel: dismissBackupSheet,
                onExport: exportBackup(password:onlyIDs:)
            )
        case .importBackup:
            BackupImportSheet(
                errorMessage: $backupSheetError,
                onCancel: dismissBackupSheet,
                onImport: importBackup(password:)
            )
        case .exportGAMigration:
            GAMigrationExportSheet(
                accounts: store.accounts,
                errorMessage: $backupSheetError,
                onCancel: dismissBackupSheet,
                onExport: exportGAMigration(onlyIDs:)
            )
        case nil:
            EmptyView()
        }
    }

    private func dismissBackupSheet() {
        router.backupSheet = nil
        backupSheetError = nil
    }

    /// 导出：口令 → PBKDF2 → AES-GCM → 保存面板写盘（0600）
    ///
    /// - Parameter onlyIDs: nil = 导出全部账户；非 nil = 只导出集合内的账户（可多选）
    private func exportBackup(password: String, onlyIDs: Set<UUID>?) {
        let entries = store.backupEntries().filter { onlyIDs == nil || onlyIDs!.contains($0.id) }
        let document = BackupArchive.Document(accounts: entries)

        let data: Data
        do {
            data = try BackupArchive.encrypt(document, password: password)
        } catch {
            backupSheetError = "导出失败，请重试"
            return
        }

        let panel = NSSavePanel()
        panel.title = "导出加密备份"
        panel.nameFieldStringValue = backupFileName(onlyIDs: onlyIDs, count: entries.count)
        panel.begin { response in
            Task { @MainActor in
                guard response == .OK, let url = panel.url else { return }   // 取消：留在弹窗
                do {
                    try data.write(to: url, options: .atomic)
                    try? FileManager.default.setAttributes(
                        [.posixPermissions: 0o600],
                        ofItemAtPath: url.path
                    )
                    dismissBackupSheet()
                    if let onlyIDs, onlyIDs.count == 1, let id = onlyIDs.first,
                       let account = store.accounts.first(where: { $0.id == id }) {
                        toast.show("已导出「\(account.displayName)」")
                    } else {
                        toast.show("已导出 \(entries.count) 个账户")
                    }
                } catch {
                    backupSheetError = "写入文件失败，请换一个位置重试"
                }
            }
        }
    }

    /// 备份文件名：全部 = `2way-backup-<时间>`；单个 = `2way-<账户名>-<时间>`；
    /// 多个 = `2way-backup-<N>keys-<时间>`
    private func backupFileName(onlyIDs: Set<UUID>?, count: Int) -> String {
        let stamp = Self.fileStamp()
        guard let onlyIDs else {
            return "2way-backup-\(stamp).2wbackup"
        }
        if onlyIDs.count == 1,
           let id = onlyIDs.first,
           let account = store.accounts.first(where: { $0.id == id }) {
            return "2way-\(Self.fileNameSafe(account.displayName))-\(stamp).2wbackup"
        }
        return "2way-backup-\(count)keys-\(stamp).2wbackup"
    }

    /// 账户名 → 文件名安全串（去掉路径分隔符等非法字符并限长）
    private static func fileNameSafe(_ name: String) -> String {
        let replaced = name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "\\", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String((replaced.isEmpty ? "account" : replaced).prefix(32))
    }

    /// 导出 GA 迁移码：账户 → `otpauth-migration://` → 二维码 PNG
    ///
    /// 注意：迁移码是明文载荷（GA 格式只做 base64），弹窗已向用户明示风险。
    /// - Parameter onlyIDs: nil = 全部账户；非 nil = 只导出集合内的账户（可多选）
    private func exportGAMigration(onlyIDs: Set<UUID>?) {
        let entries = store.backupEntries()
            .filter { onlyIDs == nil || onlyIDs!.contains($0.id) }
            .map { entry in
                OTPMigration.Entry(
                    displayName: entry.displayName,
                    issuer: entry.issuer,
                    secret: entry.secret,
                    parameters: entry.parameters
                )
            }
        guard !entries.isEmpty else {
            backupSheetError = "还没有可导出的账户"
            return
        }

        let uri = OTPMigration.migrationURI(entries: entries)
        let pngData: Data
        do {
            pngData = try QRCodeImage.pngData(for: uri)
        } catch {
            backupSheetError = "二维码生成失败，请重试"
            return
        }

        let panel = NSSavePanel()
        panel.title = "导出 GA 迁移码"
        panel.nameFieldStringValue = "2way-ga-migration-\(Self.fileStamp()).png"
        panel.begin { response in
            Task { @MainActor in
                guard response == .OK, let url = panel.url else { return }
                do {
                    try pngData.write(to: url, options: .atomic)
                    try? FileManager.default.setAttributes(
                        [.posixPermissions: 0o600],
                        ofItemAtPath: url.path
                    )
                    dismissBackupSheet()
                    if let onlyIDs, onlyIDs.count == 1, let id = onlyIDs.first,
                       let account = store.accounts.first(where: { $0.id == id }) {
                        toast.show("已导出「\(account.displayName)」的迁移码")
                    } else {
                        toast.show("已导出 GA 迁移码（\(entries.count) 个账户）")
                    }
                } catch {
                    backupSheetError = "写入文件失败，请换一个位置重试"
                }
            }
        }
    }

    /// 导入：选择文件 → 解密 → 合并（同 id 跳过，幂等）
    private func importBackup(password: String) {
        let panel = NSOpenPanel()
        panel.title = "选择备份文件"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        // 不限文件类型：以文件内的 magic 校验为准（避免动态 UTType 兼容问题）
        panel.begin { response in
            Task { @MainActor in
                guard response == .OK, let url = panel.url else { return }
                do {
                    let data = try Data(contentsOf: url)
                    let document = try BackupArchive.decrypt(data, password: password)
                    let result = try store.importBackup(document.accounts)
                    dismissBackupSheet()
                    if result.skipped > 0 {
                        toast.show("已导入 \(result.imported) 个账户（跳过 \(result.skipped) 个已存在）")
                    } else {
                        toast.show("已导入 \(result.imported) 个账户")
                    }
                } catch let error as BackupArchive.ArchiveError {
                    backupSheetError = Self.message(for: error)
                } catch {
                    backupSheetError = "读取备份文件失败"
                }
            }
        }
    }

    private static func message(for error: BackupArchive.ArchiveError) -> String {
        switch error {
        case .weakPassword(let minimum):
            "口令至少需要 \(minimum) 位"
        case .badMagic:
            "这不是 2way 的备份文件"
        case .unsupportedVersion(let version):
            "备份文件版本（\(version)）不受支持，请升级应用"
        case .wrongPasswordOrCorrupted:
            "口令错误，或备份文件已损坏"
        case .malformed:
            "备份文件已损坏"
        case .keyDerivationFailed:
            "密钥派生失败，请重试"
        }
    }

    private static func fileStamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmm"
        return formatter.string(from: Date())
    }

    #if DEBUG
    /// 调试链路：与 ImportImageView 相同的「解码 → resolve → 入库」路径
    private func importImageForDebug(at path: String) {
        guard
            let image = NSImage(contentsOfFile: path),
            let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { return }
        let strings = (try? QRImageDecoder.decode(in: cgImage)) ?? []
        let fields: [QRImport.PrefilledAccount]
        switch QRImport.resolve(strings) {
        case .account(let single):
            fields = [single]
        case .migrated(let multiple, _):
            fields = multiple
        default:
            return
        }
        for field in fields {
            try? store.add(
                displayName: field.displayName,
                issuer: field.issuer,
                secretBase32: field.secretBase32,
                parameters: field.parameters
            )
        }
    }
    #endif
}

#Preview {
    RootView(store: AccountStore(secrets: EncryptedStore()), settings: AppSettings())
}
