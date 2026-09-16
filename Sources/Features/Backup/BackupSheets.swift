import SwiftUI

/// 导出范围（两个导出弹窗共用）：全部账户 / 指定某一个账户
enum ExportScope: Hashable {
    case all
    case single
}

/// 导出范围选择器：分段（全部 / 指定）+ 指定时选择具体账户
struct ExportScopePicker: View {
    let accounts: [Account]
    @Binding var scope: ExportScope
    @Binding var selectedAccountID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("导出范围")
                .font(Token.Typography.label)
                .foregroundStyle(Token.Palette.t2)

            SegmentedControl(
                options: [ExportScope.all, .single],
                title: { $0 == .all ? "全部账户（\(accounts.count)）" : "指定账户" },
                selection: $scope
            )

            if scope == .single {
                Picker("", selection: $selectedAccountID) {
                    ForEach(accounts) { account in
                        Text(Self.label(for: account)).tag(Optional(account.id))
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .font(.system(size: 13))
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .onAppear {
            if selectedAccountID == nil { selectedAccountID = accounts.first?.id }
        }
    }

    /// 与列表行一致的「发行方：账户名」表述
    static func label(for account: Account) -> String {
        if let issuer = account.issuer, !issuer.isEmpty, issuer != account.displayName {
            return "\(issuer)：\(account.displayName)"
        }
        return account.displayName
    }

    /// 实际导出的账户 id：nil = 全部
    static func effectiveID(scope: ExportScope, selectedAccountID: UUID?) -> UUID? {
        scope == .single ? selectedAccountID : nil
    }
}

/// 导出加密备份（C4-3 / PRD P1「导入导出」）
struct BackupExportSheet: View {
    let accounts: [Account]
    @Binding var errorMessage: String?
    var onCancel: () -> Void
    /// 传入口令与范围（nil = 全部）；调用方负责弹保存面板、写文件
    var onExport: (String, UUID?) -> Void

    @State private var password = ""
    @State private var confirmation = ""
    @State private var scope: ExportScope = .all
    @State private var selectedAccountID: UUID?

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

            ExportScopePicker(accounts: accounts, scope: $scope, selectedAccountID: $selectedAccountID)

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
        if scope == .single, selectedAccountID == nil {
            errorMessage = "请选择要导出的账户"
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
        onExport(password, ExportScopePicker.effectiveID(scope: scope, selectedAccountID: selectedAccountID))
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
    var onExport: (UUID?) -> Void

    @State private var scope: ExportScope = .all
    @State private var selectedAccountID: UUID?

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

            ExportScopePicker(accounts: accounts, scope: $scope, selectedAccountID: $selectedAccountID)

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
        if scope == .single, selectedAccountID == nil {
            errorMessage = "请选择要导出的账户"
            return
        }
        onExport(ExportScopePicker.effectiveID(scope: scope, selectedAccountID: selectedAccountID))
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
