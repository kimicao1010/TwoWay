import SwiftUI

/// 添加账户页（PRD §7.4）：分段控件在「导入图片 / 手动输入」间切换。
///
/// C2-5 先交付手动输入；导入图片只搭外壳（视觉占位），解码链路在 C2-6 接入。
/// 两个状态独立成屏 —— 切段时表单状态保留在 `ManualEntryModel`。
struct AddAccountView: View {
    enum Method: Hashable {
        case importImage
        case manual
    }

    @Bindable var store: AccountStore
    /// 只调用 show()，不在本视图渲染 → 无需订阅
    let toast: ToastCenter
    var onCancel: () -> Void
    /// 成功添加后调用（回列表 + toast「已添加「名称」」）
    var onAdded: (String) -> Void

    @State private var method: Method = .manual
    @State private var model = ManualEntryModel()

    var body: some View {
        VStack(spacing: 0) {
            WindowTitlebar(title: "添加账户") {
                Button("取消", action: handleCancel)
                    .buttonStyle(.plain)
                    .font(Token.Typography.body)
                    .foregroundStyle(Token.Palette.t2)
            }
            Divider1px()

            ScrollView {
                VStack(spacing: 16) {
                    SegmentedControl(
                        options: [Method.importImage, .manual],
                        title: Self.segmentTitle,
                        selection: $method
                    )

                    switch method {
                    case .importImage:
                        ImportImagePlaceholder()
                    case .manual:
                        ManualEntryView(model: model, onSubmit: submit)
                    }
                }
                .padding(Token.Metrics.pagePadding)
            }
            .scrollIndicators(.hidden)
        }
    }

    private static func segmentTitle(_ method: Method) -> String {
        switch method {
        case .importImage: "导入图片"
        case .manual: "手动输入"
        }
    }

    private func handleCancel() {
        model.reset()
        onCancel()
    }

    private func submit() {
        do {
            let name = try model.submit(into: store)
            onAdded(name)
        } catch let error as Base32.DecodingError {
            // E4：提交时拦截，给出明确提示，不静默
            toast.show(ManualEntryModel.message(for: error))
        } catch {
            toast.show("添加失败，请检查密钥后重试")
        }
    }
}

// MARK: - 显示名

extension OTPParameters.HashAlgorithm {
    /// UI 显示名（PRD §7.4：SHA-1）
    var displayValue: String {
        switch self {
        case .sha1: "SHA-1"
        case .sha256: "SHA-256"
        case .sha512: "SHA-512"
        }
    }
}

// MARK: - 手动输入（PRD §7.4 手动输入表）

/// 字段：账户名称 / 密钥（E3 清洗 + E4 校验）/ 高级选项（可折叠）/ 实时预览 / 提交
struct ManualEntryView: View {
    let model: ManualEntryModel
    var onSubmit: () -> Void

    @State private var advancedExpanded = true

    var body: some View {
        VStack(spacing: 16) {
            TokenTextField(
                label: "账户名称",
                text: Binding(get: { model.displayName }, set: { model.displayName = $0 }),
                placeholder: "例如：you@example.com"
            )

            TokenTextField(
                label: "密钥",
                text: Binding(get: { model.secretRaw }, set: { model.secretRaw = $0 }),
                placeholder: "JBSWY3DPEHPK3PXP",
                monospaced: true,
                helpText: "服务商提供的 Base32 密钥，空格与连字符会自动忽略",
                errorMessage: model.secretError,
                trailingSystemImage: "key"
            )

            advancedCard

            // T3/T5：预览由单一时间源驱动，30Hz 连续刷新；密钥变更即重算
            TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                PreviewCard(model: model, now: context.date)
            }

            PrimaryButton(title: "添加账户", action: onSubmit)
        }
    }

    // MARK: 高级选项（PRD：可折叠卡，默认值即可用）

    private var advancedCard: some View {
        VStack(spacing: 12) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) { advancedExpanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Token.Palette.t4)
                        .rotationEffect(.degrees(advancedExpanded ? 0 : -90))
                    Text("高级选项")
                        .font(Token.Typography.label)
                        .foregroundStyle(Token.Palette.tTitle)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if advancedExpanded {
                VStack(spacing: 10) {
                    optionRow(
                        key: "算法",
                        selection: Binding(
                            get: { model.algorithm },
                            set: { model.algorithm = $0 }
                        )
                    ) {
                        ForEach(OTPParameters.HashAlgorithm.allCases, id: \.self) { algorithm in
                            Text(algorithm.displayValue).tag(algorithm)
                        }
                    }
                    optionRow(
                        key: "位数",
                        selection: Binding(
                            get: { model.digits },
                            set: { model.digits = $0 }
                        )
                    ) {
                        ForEach([6, 8], id: \.self) { digits in
                            Text("\(digits) 位").tag(digits)
                        }
                    }
                    optionRow(
                        key: "刷新周期",
                        selection: Binding(
                            get: { model.period },
                            set: { model.period = $0 }
                        )
                    ) {
                        ForEach([30, 60], id: \.self) { seconds in
                            Text("\(seconds) 秒").tag(TimeInterval(seconds))
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(Token.Palette.card)
        .overlay(
            RoundedRectangle(cornerRadius: Token.Metrics.primaryButtonRadius)
                .stroke(Token.Palette.cardBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Token.Metrics.primaryButtonRadius))
    }

    /// 参数行（Demo `.adv-row`：k 左 t2 13 / v 右 t1 13 Medium）
    ///
    /// 用原生 `Picker(.menu)`：macOS 的 `Menu` 自定义标签渲染不可控
    /// （标签被替换成菜单项模板），Picker 则可靠地显示当前值 + 指示箭头。
    private func optionRow<T: Hashable>(
        key: String,
        selection: Binding<T>,
        @ViewBuilder items: () -> some View
    ) -> some View {
        HStack {
            Text(key)
                .font(.system(size: 13))
                .foregroundStyle(Token.Palette.t2)
            Spacer(minLength: 0)
            Picker("", selection: selection) {
                items()
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .font(.system(size: 13, weight: .medium))
            .tint(Token.Palette.t1)
            .frame(width: 92)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 20)
        .contentShape(Rectangle())
    }
}

// MARK: - 实时预览卡（PRD §7.4：高 76 / 码 20 等宽 字距 1.5 / 环 28）

private struct PreviewCard: View {
    let model: ManualEntryModel
    let now: Date

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(label)
                    .font(Token.Typography.caption)
                    .foregroundStyle(Token.Palette.t4)

                Text(code)
                    .font(Token.Typography.codePreview)
                    .kerning(1.5)
                    .foregroundStyle(Token.Palette.code)
                    .monospacedDigit()
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            CountdownRing(
                progress: state?.progress ?? 0,
                size: Token.Metrics.ringSmallSize,
                strokeWidth: Token.Metrics.ringSmallStroke,
                isWarning: state?.isWarning ?? false
            )
        }
        .padding(16)
        .frame(height: Token.Metrics.previewCardHeight)
        .background(Token.Palette.card)
        .overlay(
            RoundedRectangle(cornerRadius: Token.Metrics.primaryButtonRadius)
                .stroke(Token.Palette.cardBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Token.Metrics.primaryButtonRadius))
    }

    /// 密钥有效时随时间实时换算；无效则显示占位（E4：不产出错误验证码）
    private var state: TOTPTimeState? {
        guard let secret = try? Base32.decode(model.secretRaw), let params = model.parameters else {
            return nil
        }
        return TOTPTime.state(at: now, period: params.period)
    }

    private var code: String {
        guard
            let secret = try? Base32.decode(model.secretRaw),
            let params = model.parameters,
            let timeState = state
        else { return "-- ----" }
        let raw = TOTPEngine.rawCode(secret: secret, counter: timeState.counter, parameters: params)
        return TOTPEngine.grouped(raw)
    }

    private var label: String {
        guard let timeState = state else { return "实时预览" }
        return "实时预览 · 剩余 \(timeState.secondsRemaining) 秒"
    }
}

// MARK: - 导入图片占位（C2-6 接入：拖放 + NSOpenPanel + Vision 解码 + 预填）

/// 视觉按 PRD §7.4 搭好（拖放区 / 文案 / 引导卡），解码链路 C2-6 落地。
private struct ImportImagePlaceholder: View {
    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: Token.Metrics.scannerRadius)
                    .fill(
                        LinearGradient(
                            colors: [Token.Palette.scannerGradStart, Token.Palette.scannerGradEnd],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
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
            .frame(width: Token.Metrics.scannerSize.width, height: Token.Metrics.scannerSize.height)
            .overlay(
                RoundedRectangle(cornerRadius: Token.Metrics.scannerRadius)
                    .strokeBorder(
                        Token.Palette.border,
                        style: StrokeStyle(lineWidth: 1, dash: [5, 4])
                    )
            )

            guideCard
        }
        .frame(maxWidth: .infinity)
    }

    /// 引导卡（PRD 7.4：「在哪里找到二维码？」+ 服务商路径示例）
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
}
