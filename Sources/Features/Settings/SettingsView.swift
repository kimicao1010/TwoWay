import SwiftUI

/// 偏好设置（⌘, 打开；主窗口「⋯」菜单也有入口）
struct SettingsView: View {
    @Bindable var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("外观与行为")
                .font(Token.Typography.label)
                .foregroundStyle(Token.Palette.t2)

            Toggle(isOn: $settings.hideDockIcon) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("隐藏 Dock 图标")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Token.Palette.t1)
                    Text("开启后 App 不出现在 Dock 与 Cmd-Tab，只保留菜单栏图标；\n仍可从菜单栏下拉或 ⌘, 打开本设置。")
                        .font(.system(size: 11))
                        .foregroundStyle(Token.Palette.t4)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            // 立即生效（accessory ↔ regular），无需重启
            .onChange(of: settings.hideDockIcon) { _, _ in
                settings.applyActivationPolicy()
            }

            Divider()

            Text("2way \(Self.version)")
                .font(.system(size: 11))
                .foregroundStyle(Token.Palette.t4)
        }
        .padding(Token.Metrics.pagePadding)
        .frame(width: 380, alignment: .leading)
        .background(Token.Palette.winBg)
    }

    private static var version: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "—"
    }
}
