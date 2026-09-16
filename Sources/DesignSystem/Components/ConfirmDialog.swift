import SwiftUI

/// 删除确认弹窗（PRD FR-06 / §7.6）
///
/// v1.8 起**就地覆盖列表**：左滑「删除」直接弹本弹窗，不再先切到详情页
/// （用户反馈：详情页纯多余，删除多一次跳转没有价值）。
/// 弹窗全屏遮罩 `rgba(13,13,15,.65)` + 304 宽卡片，文案明示不可恢复。
struct DeleteConfirmDialog: View {
    /// 待删除账户名（标题处明示对象，避免误删相邻行）
    let accountName: String
    var onCancel: () -> Void
    var onConfirm: () -> Void

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Token.Palette.scrim)
                .onTapGesture(perform: onCancel)

            VStack(spacing: 16) {
                Text("删除「\(accountName)」？")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Token.Palette.t1)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text("删除后需要重新导入二维码图片或输入密钥才能恢复，该账户的验证码将立即失效。")
                    .font(.system(size: 13))
                    .lineSpacing(5)
                    .foregroundStyle(Token.Palette.t2)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    Button(action: onCancel) {
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

                    Button(action: onConfirm) {
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
}
