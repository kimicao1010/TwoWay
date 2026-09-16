import SwiftUI

/// 窗口根视图（PRD G-01/G-03：400×732 固定尺寸 + 52pt 自绘标题栏）
///
/// 屏幕路由由 `AppRouter` 驱动（TECH_PLAN §3）；共享 Toast 渲染在本层，
/// 列表（复制反馈）与添加页（已添加提示）共用同一个 `ToastCenter`。
struct RootView: View {
    /// 生产路径：加密文件存储（D9，用户决策弃用 Keychain —— 本机钥匙串 ACL
    /// 逐条弹授权框不可接受）。安全边界见 EncryptedStore 类注释。
    @State private var store = AccountStore(secrets: EncryptedStore())
    @State private var router = AppRouter()
    @State private var toast = ToastCenter()
    /// U3：DEBUG 调试切屏用（--debug-import）
    @State private var debugInitialMethod: AddAccountView.Method = .manual
    /// DEBUG：load 失败时把错误码亮在界面上（排查生产 Keychain 路径用）
    @State private var loadErrorText: String?
    /// 备份弹窗内的错误文案（口令错误 / 文件损坏等，就地提示不静默）
    @State private var backupSheetError: String?

    var body: some View {
        ZStack {
            switch router.screen {
            case .list:
                listScreen
                    .transition(.opacity)

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
                        onCancel: { show(.detail) },
                        onAdded: { _ in },
                        onImported: { _, _ in },
                        editing: AddAccountView.EditTarget(
                            account: account,
                            secretBase32: store.secretBase32(for: account.id) ?? ""
                        ),
                        onSaved: { name in
                            show(.detail)
                            toast.show("已保存「\(name)」")
                        }
                    )
                    .transition(.opacity)
                } else {
                    listScreen
                }

            case .detail:
                // E2：账户不存在（已删空 / 无选中）时回落列表
                if store.selectedAccount != nil {
                    AccountDetailView(
                        store: store,
                        toast: toast,
                        showsDeleteDialog: router.showsDeleteDialog,
                        onRequestDeleteDialog: { router.showsDeleteDialog = true },
                        onCancelDelete: { router.showsDeleteDialog = false },
                        onRequestEdit: { router.screen = .editAccount },
                        onBack: { show(.list) },
                        onDeleted: { name in
                            show(.list)
                            toast.show("已删除「\(name)」")
                        }
                    )
                    .transition(.opacity)
                } else {
                    listScreen
                }
            }
        }
        .animation(.easeInOut(duration: Token.Motion.screenTransition), value: router.screen)
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
        .frame(minWidth: Token.Metrics.windowWidth, maxWidth: Token.Metrics.windowWidth)
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
            RingClock.shared.start()   // 全局唯一时钟：环与码文本共用（T5/T6）
            do {
                try store.load()
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
            // --debug-detail [--debug-detail-dialog]：直进详情屏（可带删除确认弹窗）
            if ProcessInfo.processInfo.arguments.contains("--debug-detail") {
                store.selectedAccountID = store.accounts.first?.id
                router.screen = .detail
                router.showsDeleteDialog = ProcessInfo.processInfo.arguments.contains("--debug-detail-dialog")
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
                    Button("导出 GA 迁移码（PNG）…") {
                        backupSheetError = nil
                        router.backupSheet = .exportGAMigration
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
                onDetail: { account in
                    // R7：行复位 + 切详情屏
                    store.selectedAccountID = account.id
                    showDetail(autoDeleteConfirm: false)
                },
                onDelete: { account in
                    // R8：切详情屏后 260ms 自动弹删除确认
                    store.selectedAccountID = account.id
                    showDetail(autoDeleteConfirm: true)
                }
            )
        }
    }

    private func show(_ screen: AppRouter.Screen) {
        store.setOpenedRow(nil)   // R9/E8：离开列表屏时行复位
        router.screen = screen
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
                accountCount: store.accounts.count,
                errorMessage: $backupSheetError,
                onCancel: dismissBackupSheet,
                onExport: exportBackup(password:)
            )
        case .importBackup:
            BackupImportSheet(
                errorMessage: $backupSheetError,
                onCancel: dismissBackupSheet,
                onImport: importBackup(password:)
            )
        case .exportGAMigration:
            GAMigrationExportSheet(
                accountCount: store.accounts.count,
                errorMessage: $backupSheetError,
                onCancel: dismissBackupSheet,
                onExport: exportGAMigration
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
    private func exportBackup(password: String) {
        let entries = store.backupEntries()
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
        panel.nameFieldStringValue = "2way-backup-\(Self.fileStamp()).2wbackup"
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
                    toast.show("已导出 \(entries.count) 个账户")
                } catch {
                    backupSheetError = "写入文件失败，请换一个位置重试"
                }
            }
        }
    }

    /// 导出 GA 迁移码：账户 → `otpauth-migration://` → 二维码 PNG
    ///
    /// 注意：迁移码是明文载荷（GA 格式只做 base64），弹窗已向用户明示风险。
    private func exportGAMigration() {
        let entries = store.backupEntries().map { entry in
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
                    toast.show("已导出 GA 迁移码（\(entries.count) 个账户）")
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

    /// R7/R8：进入详情。R8 在切屏动画（260ms）后自动弹删除确认（PRD §7.2）
    private func showDetail(autoDeleteConfirm: Bool) {
        store.setOpenedRow(nil)
        router.showsDeleteDialog = false
        router.screen = .detail
        if autoDeleteConfirm {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(Token.Motion.deleteDialogDelay * 1_000_000_000))
                guard router.screen == .detail else { return }
                router.showsDeleteDialog = true
            }
        }
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
    RootView()
}
