import SwiftUI
import UniformTypeIdentifiers

/// 导入图片页（PRD §7.4，C2-6）—— 拖放 / 文件选择 → Vision 解码 → 预填
///
/// 异常路径（PRD §9）：
/// - E9 无二维码 / 图片损坏 → 原地提示「未识别到二维码…」，**保留已选图片**
/// - E10 非 otpauth → 「这不是一个验证器二维码」
/// - E11 多二维码 → 取面积最大者（解码结果已按面积降序）
/// - 不申请摄像头权限（Info.plist 无 NSCameraUsageDescription，验收判据）
struct ImportImageView: View {
    /// 单账户解码成功：预填 + 自动切「手动输入」分段（PRD：交由用户确认后提交）
    var onDecoded: (QRImport.PrefilledAccount) -> Void
    /// GA 迁移码多账户：批量直接导入（单账户迁移仍走预填确认流）
    var onBatchImport: ([QRImport.PrefilledAccount], _ skippedHOTPCount: Int) -> Void

    @State private var selectedImage: NSImage?
    @State private var errorMessage: String?
    @State private var isTargeted = false
    @State private var isDecoding = false

    var body: some View {
        VStack(spacing: 16) {
            dropZone

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(Token.Palette.dangerText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }

            SecondaryButton(
                title: isDecoding ? "解码中…" : "选择图片…",
                systemImage: "photo",
                action: openPanel
            )
            .disabled(isDecoding)

            guideCard
        }
        .frame(maxWidth: .infinity)
        .animation(.easeOut(duration: 0.18), value: errorMessage)
        .animation(.easeOut(duration: 0.12), value: isTargeted)
    }

    // MARK: 拖放区（PRD：360×340 / 圆角 14 / 渐变底 / 1px 虚线描边）

    private var dropZone: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Token.Metrics.scannerRadius)
                .fill(
                    LinearGradient(
                        colors: [Token.Palette.scannerGradStart, Token.Palette.scannerGradEnd],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    // 拖入悬停态：底色提亮（PRD）
                    Color.white.opacity(isTargeted ? 0.06 : 0)
                        .clipShape(RoundedRectangle(cornerRadius: Token.Metrics.scannerRadius))
                )

            content
        }
        .frame(width: Token.Metrics.scannerSize.width, height: Token.Metrics.scannerSize.height)
        .overlay(
            RoundedRectangle(cornerRadius: Token.Metrics.scannerRadius)
                .strokeBorder(
                    // 拖入悬停态：虚线描边转强调色（PRD）
                    isTargeted ? Token.Palette.accent : Token.Palette.border,
                    style: StrokeStyle(lineWidth: 1, dash: [5, 4])
                )
        )
        .onDrop(of: [UTType.fileURL, UTType.image], isTargeted: $isTargeted, perform: handleDrop)
        .onTapGesture { openPanel() }
        .contentShape(RoundedRectangle(cornerRadius: Token.Metrics.scannerRadius))
    }

    @ViewBuilder private var content: some View {
        if let selectedImage {
            VStack(spacing: 10) {
                Image(nsImage: selectedImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 170)
                Text(isDecoding ? "正在识别二维码…" : "再次拖入图片可更换")
                    .font(Token.Typography.caption)
                    .foregroundStyle(Token.Palette.t3)
            }
            .padding(16)
        } else {
            VStack(spacing: 10) {
                Image(systemName: "photo")
                    .font(.system(size: 28, weight: .regular))
                    .foregroundStyle(Token.Palette.t4)
                Text("拖入二维码图片，或点击选择文件")
                    .font(.system(size: 13))
                    .foregroundStyle(Token.Palette.t1)
                Text("支持 PNG / JPEG / HEIC")
                    .font(Token.Typography.caption)
                    .foregroundStyle(Token.Palette.t3)
            }
        }
    }

    // MARK: 引导卡（PRD 7.4：「在哪里找到二维码？」）

    private var guideCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("在哪里找到二维码？")
                .font(Token.Typography.label)
                .foregroundStyle(Token.Palette.tTitle)
            Text("登录服务商的账户安全设置，选择「设置两步验证」即可看到二维码；也可以在手机上截图后拖入本窗口。")
                .font(.system(size: 12))
                .foregroundStyle(Token.Palette.t4)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Token.Palette.card)
        .overlay(
            RoundedRectangle(cornerRadius: Token.Metrics.primaryButtonRadius)
                .stroke(Token.Palette.cardBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Token.Metrics.primaryButtonRadius))
    }

    // MARK: 输入路径

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }

        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            // Finder 拖入的文件：取文件 URL 读图（PNG / JPEG / HEIC 全覆盖）
            _ = provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
                guard let data else { return }
                Task { @MainActor in
                    guard let url = try? URL(dataRepresentation: data, relativeTo: nil) else {
                        showReadError()
                        return
                    }
                    if let image = NSImage(contentsOf: url) {
                        decodeImage(image)
                    } else {
                        showReadError()
                    }
                }
            }
        } else {
            // 网页 / 应用拖入的图片位图
            _ = provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                guard let data else { return }
                Task { @MainActor in
                    if let image = NSImage(data: data) {
                        decodeImage(image)
                    } else {
                        showReadError()
                    }
                }
            }
        }
        return true
    }

    private func openPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.image]   // 仅允许图片类型（PRD）
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            if let image = NSImage(contentsOf: url) {
                decodeImage(image)
            } else {
                showReadError()
            }
        }
    }

    // MARK: 解码（PRD：释放即开始解码）

    private func decodeImage(_ image: NSImage) {
        selectedImage = image   // E9：先保留已选图片，失败不清空
        errorMessage = nil
        isDecoding = true

        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            isDecoding = false
            showReadError()
            return
        }

        // 图片小（截图量级），同步解码 < 100ms，可接受且免去跨线程的 Sendable 纠缠
        let strings = (try? QRImageDecoder.decode(in: cgImage)) ?? []
        isDecoding = false

        switch QRImport.resolve(strings) {
        case .account(let fields):
            onDecoded(fields)   // 成功 → 预填 + 切手动分段
        case .migrated(let accounts, let skipped):
            if accounts.count == 1 {
                onDecoded(accounts[0])   // 单账户迁移仍走「预填确认」流
            } else {
                onBatchImport(accounts, skipped)
            }
        case .migrationWithoutTOTP:
            errorMessage = "迁移码中没有可导入的 TOTP 账户（HOTP 暂不支持）"
        case .noQRCode:
            errorMessage = "未识别到二维码，请确认图片清晰、完整且包含有效二维码"
        case .notOTPAuth:
            errorMessage = "这不是一个验证器二维码"
        case .invalidOTPAuth:
            errorMessage = "二维码中的验证器信息无效或不受支持"
        }
    }

    private func showReadError() {
        errorMessage = "图片无法读取，请换一张试试"
    }
}
