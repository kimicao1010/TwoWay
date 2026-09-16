import SwiftUI

/// 导出加密备份（C4-3 / PRD P1「导入导出」）
struct BackupExportSheet: View {
    let accountCount: Int
    @Binding var errorMessage: String?
    var onCancel: () -> Void
    /// 传入口令（调用方负责弹保存面板、写文件；失败时写 `errorMessage`）
    var onExport: (String) -> Void

    @State private var password = ""
    @State private var confirmation = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("导出加密备份")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Token.Palette.t1)

            Text("将 \(accountCount) 个账户导出为一个加密备份文件（AES-256-GCM）。\n请牢记口令：**忘记口令将无法恢复备份内容**。")
                .font(.system(size: 12))
                .foregroundStyle(Token.Palette.t2)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)

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
        .frame(width: 360)
    }

    private func performExport() {
        errorMessage = nil
        guard password.count >= BackupArchive.minimumPasswordLength else {
            errorMessage = "口令至少需要 \(BackupArchive.minimumPasswordLength) 位"
            return
        }
        guard password == confirmation else {
            errorMessage = "两次输入的口令不一致"
            return
        }
        onExport(password)
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
