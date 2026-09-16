import SwiftUI

/// 主按钮（PRD §7.4：高 44 / 圆角 12 / 强调色底 / 15 Semibold）
struct PrimaryButton: View {
    let title: String
    var action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Token.Typography.button)
                .foregroundStyle(Token.Palette.onAccent)
                .frame(maxWidth: .infinity)
                .frame(height: Token.Metrics.primaryButtonHeight)
                .background(Token.Palette.accent)
                .clipShape(RoundedRectangle(cornerRadius: Token.Metrics.primaryButtonRadius))
                .opacity(hovering ? 0.94 : 1)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// 次级按钮（PRD §7.4：高 40 / 描边 `--border` / 底 `--surface` / 13 Medium）
struct SecondaryButton: View {
    let title: String
    var systemImage: String? = nil
    var action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 13, weight: .medium))
                }
                Text(title)
                    .font(Token.Typography.label)
            }
            .foregroundStyle(Token.Palette.tTitle)
            .frame(maxWidth: .infinity)
            .frame(height: Token.Metrics.secondaryButtonHeight)
            .background(hovering ? Token.Palette.actionDetail : Token.Palette.surface)
            .overlay(
                RoundedRectangle(cornerRadius: Token.Metrics.inputRadius)
                    .stroke(Token.Palette.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Token.Metrics.inputRadius))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// 输入框（PRD §7.4：高 42 / 圆角 10 / 底 `--input` / 描边 `--border`）
///
/// `monospaced` 用于密钥输入（等宽 + 字距 0.5，对应 Demo `.input input.mono`）。
struct TokenTextField: View {
    let label: String
    @Binding var text: String
    var placeholder: String = ""
    var monospaced = false
    var helpText: String? = nil
    /// E4 等错误提示（危险色，显示在 help 之下）
    var errorMessage: String? = nil
    /// 输入框尾部图标（密钥字段的钥匙图标）
    var trailingSystemImage: String? = nil

    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(Token.Typography.label)
                .foregroundStyle(Token.Palette.t2)

            HStack(spacing: 8) {
                TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(Token.Palette.t3))
                    .textFieldStyle(.plain)
                    .font(
                        monospaced
                            ? .system(size: 14, weight: .medium, design: .monospaced)
                            : .system(size: 14)
                    )
                    .kerning(monospaced ? 0.5 : 0)
                    .focused($focused)
                    .disableAutocorrection(true)

                if let trailingSystemImage {
                    Image(systemName: trailingSystemImage)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(Token.Palette.t4)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: Token.Metrics.inputHeight)
            .background(Token.Palette.input)
            .overlay(
                RoundedRectangle(cornerRadius: Token.Metrics.inputRadius)
                    .stroke(focused ? Token.Palette.t2 : Token.Palette.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Token.Metrics.inputRadius))

            if let errorMessage {
                Text(errorMessage)
                    .font(Token.Typography.caption)
                    .foregroundStyle(Token.Palette.dangerText)
            }

            if let helpText {
                Text(helpText)
                    .font(Token.Typography.caption)
                    .foregroundStyle(Token.Palette.t3)
            }
        }
    }
}
