import SwiftUI

/// 导出范围（两个导出弹窗共用）：全部账户 / 多选指定账户
enum ExportScope: Hashable {
    case all
    case selected
}

/// 导出范围选择器：分段（全部 / 选择账户）+ 选择时**多选**账户清单
///
/// 多选是刻意设计：常见诉求是「把这几个迁到手机」，
/// 单选会逼用户导出多次（每次都是独立文件/二维码）。
struct ExportScopePicker: View {
    let accounts: [Account]
    @Binding var scope: ExportScope
    @Binding var selectedIDs: Set<UUID>

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("导出范围")
                .font(Token.Typography.label)
                .foregroundStyle(Token.Palette.t2)

            SegmentedControl(
                options: [ExportScope.all, .selected],
                title: { $0 == .all ? "全部账户（\(accounts.count)）" : "选择账户" },
                selection: $scope
            )

            if scope == .selected {
                selectedList
            }
        }
    }

    private var selectedList: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(selectedIDs.isEmpty ? "未选择账户" : "已选 \(selectedIDs.count) 个")
                    .font(Token.Typography.caption)
                    .foregroundStyle(selectedIDs.isEmpty ? Token.Palette.dangerText : Token.Palette.t3)
                Spacer(minLength: 0)
                Button("全选") { selectedIDs = Set(accounts.map(\.id)) }
                    .buttonStyle(.plain)
                    .font(Token.Typography.caption)
                    .foregroundStyle(Token.Palette.accent)
                Text("·").font(Token.Typography.caption).foregroundStyle(Token.Palette.t4)
                Button("清空") { selectedIDs = [] }
                    .buttonStyle(.plain)
                    .font(Token.Typography.caption)
                    .foregroundStyle(Token.Palette.accent)
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 4)

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(accounts) { account in
                        accountRow(account)
                    }
                }
            }
            .frame(maxHeight: 132)
            .scrollIndicators(.never)   // 铁律：勿用 `.hidden`（仍创建 scroller 并占 17px）
            .padding(.bottom, 6)
        }
        .background(Token.Palette.input)
        .overlay(
            RoundedRectangle(cornerRadius: Token.Metrics.inputRadius)
                .stroke(Token.Palette.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Token.Metrics.inputRadius))
    }

    private func accountRow(_ account: Account) -> some View {
        let isSelected = selectedIDs.contains(account.id)
        return Button {
            if isSelected {
                selectedIDs.remove(account.id)
            } else {
                selectedIDs.insert(account.id)
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isSelected ? Token.Palette.accent : Token.Palette.t4)
                Text(Self.label(for: account))
                    .font(.system(size: 13))
                    .foregroundStyle(Token.Palette.t1)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(height: 26)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(Self.label(for: account))
    }

    /// 与列表行一致的「发行方：账户名」表述
    static func label(for account: Account) -> String {
        if let issuer = account.issuer, !issuer.isEmpty, issuer != account.displayName {
            return "\(issuer)：\(account.displayName)"
        }
        return account.displayName
    }

    /// 实际导出的账户集合：nil = 全部（顺序按传入的 accounts）
    static func effectiveIDs(scope: ExportScope, selectedIDs: Set<UUID>) -> Set<UUID>? {
        scope == .selected ? selectedIDs : nil
    }
}

/// 导出加密备份（C4-3 / PRD P1「导入导出」）
struct BackupExportSheet: View {
    let accounts: [Account]
    @Binding var errorMessage: String?
    var onCancel: () -> Void
    /// 传入口令与范围（nil = 全部；非 nil = 所选账户集合）；调用方负责弹保存面板、写文件
    var onExport: (String, Set<UUID>?) -> Void

    @State private var password = ""
    @State private var confirmation = ""
    /// 默认「全部账户」；`--debug-scope-selected` 仅用于回归截图（多选清单渲染）
    @State private var scope: ExportScope = ProcessInfo.processInfo.arguments
        .contains("--debug-scope-selected") ? .selected : .all
    @State private var selectedIDs: Set<UUID> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("导出加密备份")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Token.Palette.t1)

            Text("导出为一个加密备份文件（AES-256-GCM）。\n请牢记口令：**忘记口令将无法恢复备份内容**。")
                .font(.system(size: 12))
                .foregroundStyle(Token.Palette.t2)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)

            ExportScopePicker(accounts: accounts, scope: $scope, selectedIDs: $selectedIDs)

            SecureTokenField(label: "口令（至少 8 位）", text: $password, placeholder: "用于加密备份文件")
            SecureTokenField(label: "确认口令", text: $confirmation, placeholder: "再次输入")

            if let errorMessage {
                Text(errorMessage)
                    .font(Token.Typography.caption)
                    .foregroundStyle(Token.Palette.dangerText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                DialogButton(title: "取消", style: .ghost, action: onCancel)
                DialogButton(title: "导出…", style: .primary, action: performExport)
            }
        }
        .padding(Token.Metrics.pagePadding)
        .frame(width: 380)
    }

    private func performExport() {
        errorMessage = nil
        guard !accounts.isEmpty else {
            errorMessage = "还没有可导出的账户"
            return
        }
        if scope == .selected, selectedIDs.isEmpty {
            errorMessage = "请至少选择一个账户"
            return
        }
        guard password.count >= BackupArchive.minimumPasswordLength else {
            errorMessage = "口令至少需要 \(BackupArchive.minimumPasswordLength) 位"
            return
        }
        guard password == confirmation else {
            errorMessage = "两次输入的口令不一致"
            return
        }
        onExport(password, ExportScopePicker.effectiveIDs(scope: scope, selectedIDs: selectedIDs))
    }
}

/// 导出 Google Authenticator 迁移码（C4-4）
///
/// GA 只认 `otpauth-migration://` 二维码，所以「给 GA 用」的导出方式是
/// **生成迁移码二维码 PNG**，由手机 GA「导入账户 → 扫描二维码」读取。
struct GAMigrationExportSheet: View {
    let accounts: [Account]
    @Binding var errorMessage: String?
    var onCancel: () -> Void
    /// 传入范围（nil = 全部）
    var onExport: (Set<UUID>?) -> Void

    @State private var scope: ExportScope = .all
    @State private var selectedIDs: Set<UUID> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("导出 Google Authenticator 迁移码")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Token.Palette.t1)

            Text("导出为一张**迁移码二维码 PNG**，用手机 Google Authenticator 的「导入账户 → 扫描二维码」读取。")
                .font(.system(size: 12))
                .foregroundStyle(Token.Palette.t2)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)

            ExportScopePicker(accounts: accounts, scope: $scope, selectedIDs: $selectedIDs)

            // 安全提示：迁移码载荷是明文（只做 base64），必须明示
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Token.Palette.dangerText)
                Text("该图片**未加密**：任何人拿到这张图都能导入你的账户。请勿分享或长期留存，导入完成后立即删除。")
                    .font(.system(size: 12))
                    .foregroundStyle(Token.Palette.dangerText)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Token.Palette.dangerText.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: Token.Metrics.inputRadius))

            if let errorMessage {
                Text(errorMessage)
                    .font(Token.Typography.caption)
                    .foregroundStyle(Token.Palette.dangerText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                DialogButton(title: "取消", style: .ghost, action: onCancel)
                DialogButton(title: "导出 PNG…", style: .primary, action: performExport)
            }
        }
        .padding(Token.Metrics.pagePadding)
        .frame(width: 380)
    }

    private func performExport() {
        errorMessage = nil
        guard !accounts.isEmpty else {
            errorMessage = "还没有可导出的账户"
            return
        }
        if scope == .selected, selectedIDs.isEmpty {
            errorMessage = "请至少选择一个账户"
            return
        }
        onExport(ExportScopePicker.effectiveIDs(scope: scope, selectedIDs: selectedIDs))
    }
}

/// 从备份导入（C4-3）
struct BackupImportSheet: View {
    @Binding var errorMessage: String?
    var onCancel: () -> Void
    /// 传入口令（调用方负责弹选择面板、解密、合并；失败时写 `errorMessage`）
    var onImport: (String) -> Void

    @State private var password = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("从备份导入")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Token.Palette.t1)

            Text("选择之前导出的 `.2wbackup` 文件并输入当时设置的口令。\n已存在的账户会被自动跳过（不会重复、不覆盖本地改动）。")
                .font(.system(size: 12))
                .foregroundStyle(Token.Palette.t2)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)

            SecureTokenField(label: "口令", text: $password, placeholder: "备份文件的口令")

            if let errorMessage {
                Text(errorMessage)
                    .font(Token.Typography.caption)
                    .foregroundStyle(Token.Palette.dangerText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                DialogButton(title: "取消", style: .ghost, action: onCancel)
                DialogButton(title: "选择备份文件…", style: .primary) {
                    errorMessage = nil
                    guard !password.isEmpty else {
                        errorMessage = "请先输入口令"
                        return
                    }
                    onImport(password)
                }
            }
        }
        .padding(Token.Metrics.pagePadding)
        .frame(width: 360)
    }
}

// MARK: - 局部组件

/// 口令输入框（Token 风格的安全输入）
private struct SecureTokenField: View {
    let label: String
    @Binding var text: String
    var placeholder: String = ""

    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(Token.Typography.label)
                .foregroundStyle(Token.Palette.t2)

            SecureField("", text: $text, prompt: Text(placeholder).foregroundStyle(Token.Palette.t3))
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .focused($focused)
                .padding(.horizontal, 12)
                .frame(height: Token.Metrics.inputHeight)
                .background(Token.Palette.input)
                .overlay(
                    RoundedRectangle(cornerRadius: Token.Metrics.inputRadius)
                        .stroke(focused ? Token.Palette.t2 : Token.Palette.border, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: Token.Metrics.inputRadius))
        }
    }
}

/// 弹窗按钮（ghost / primary / danger 三种样式，与删除确认弹窗一致）
struct DialogButton: View {
    enum Style {
        case ghost
        case primary
        case danger
    }

    let title: String
    let style: Style
    var action: () -> Void

    @State private var hovering = false

    private var background: Color {
        switch style {
        case .ghost: hovering ? Token.Palette.actionDetailHover : Token.Palette.actionDetail
        case .primary: Token.Palette.accent
        case .danger: Token.Palette.danger
        }
    }

    private var foreground: Color {
        switch style {
        case .ghost: Token.Palette.t1
        case .primary: Token.Palette.onAccent
        case .danger: .white
        }
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(foreground)
                .frame(maxWidth: .infinity)
                .frame(height: Token.Metrics.secondaryButtonHeight)
                .background(background)
                .clipShape(RoundedRectangle(cornerRadius: Token.Metrics.inputRadius))
                .opacity(hovering && style != .ghost ? 0.92 : 1)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
