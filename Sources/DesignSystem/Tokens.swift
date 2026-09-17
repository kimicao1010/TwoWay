import SwiftUI

/// Design Tokens —— PRD §8 + Demo `index.html` 的 `:root` 全量取值
///
/// 纪律：所有颜色 / 圆角 / 尺寸只此一处定义，视图层禁止硬编码字面量。
/// 说明：PRD §8.1 的表格未列全（缺 border / card-border / win-border / dialog /
/// dialog-border / t-title / ring-track-warn），缺失项以 Demo 实测值为准
/// —— PRD 修订记录已声明「交互参数以可交互原型实测值为准」。
enum Token {

    // MARK: - 颜色（PRD §8.1）

    enum Palette {
        /// 窗口底 / 行默认底
        static let winBg = Color(hex: 0x1B1C1E)
        /// 标题栏
        static let titlebar = Color(hex: 0x1F2124)
        /// 分隔线
        static let divider = Color(hex: 0x26282C)
        /// 悬停态 / 搜索框 / 次级按钮
        static let surface = Color(hex: 0x232528)
        /// 卡片底
        static let card = Color(hex: 0x1F2225)
        /// 输入框底
        static let input = Color(hex: 0x212326)
        /// 分段控件容器
        static let seg = Color(hex: 0x26282C)
        /// 分段控件选中段
        static let segActive = Color(hex: 0x43474B)

        /// 输入框 / 次级按钮描边
        static let border = Color(hex: 0x2E3036)
        /// 卡片描边
        static let cardBorder = Color(hex: 0x292E30)
        /// 窗口描边
        static let winBorder = Color(hex: 0x33363B)
        /// 弹窗底
        static let dialog = Color(hex: 0x24272B)
        /// 弹窗描边
        static let dialogBorder = Color(hex: 0x36383D)

        /// 文字一级
        static let t1 = Color(hex: 0xE9EBED)
        /// 文字二级
        static let t2 = Color(hex: 0x8A8F94)
        /// 文字三级
        static let t3 = Color(hex: 0x63686D)
        /// 文字四级
        static let t4 = Color(hex: 0x7C8186)
        /// 标题文字
        static let tTitle = Color(hex: 0xC9CDD1)

        /// 验证码数字
        static let code = Color(hex: 0xF2F4F5)
        /// 强调色
        static let accent = Color(hex: 0x8AB4F8)
        /// 强调色之上的文字
        static let onAccent = Color(hex: 0x1B1C1E)

        /// 危险（实心）
        static let danger = Color(hex: 0xE5484D)
        /// 危险（文字）
        static let dangerText = Color(hex: 0xF28B82)

        /// 倒计时环轨道
        static let ringTrack = Color(hex: 0x33363A)
        /// 倒计时环轨道（告警态，剩余 ≤ 5s）
        static let ringTrackWarn = Color(hex: 0x3A2B2B)
        /// 详情页大环轨道（与列表小环不同，勿混用）
        static let ringTrackHero = Color(hex: 0x3A3F45)

        /// 行复制反馈底色
        static let copied = Color(hex: 0x2E3237)
        /// 操作块「详情」底
        static let actionDetail = Color(hex: 0x2E3237)
        /// 操作块「详情」悬停底
        static let actionDetailHover = Color(hex: 0x383D42)

        /// 弹窗遮罩
        static let scrim = Color(hex: 0x0D0D0F).opacity(0.65)
        /// 头像渐变起点
        static let avatarGradStart = Color(hex: 0x5787F0)
        /// 头像渐变终点
        static let avatarGradEnd = Color(hex: 0x4761D9)
        /// 扫码取景框渐变起点
        static let scannerGradStart = Color(hex: 0x0F121A)
        /// 扫码取景框渐变终点
        static let scannerGradEnd = Color(hex: 0x212433)
    }

    // MARK: - 尺寸（PRD §8.3、§6 G-01、7.1–7.6）

    enum Metrics {
        /// v1.10：400 → **360**（用户反馈 400 过宽，按 20 一档比选后拍板）。
        /// 比选证据：`build/width-preview.png`（400/380/360/340/320 同数据实测对比）
        static let windowWidth: CGFloat = 360
        /// v1.2 / D8：窗口总高 400×732 = 内容最小 700 + 32pt 隐形标题栏
        /// （TECH_PLAN §11 RK7：`.hiddenTitleBar` 保留 32pt 参与窗口尺寸计算且无法收回），
        /// 多出的 32pt 归列表区
        static let windowHeight: CGFloat = 732
        /// 根视图内容最小高度（700）。SwiftUI 按它 + 32 定窗口尺寸；
        /// 根视图可向上伸缩，实际由窗口提议的高度决定（列表区吸收 32pt）
        static let designedContentHeight: CGFloat = 700
        static let windowCornerRadius: CGFloat = 12

        static let titlebarHeight: CGFloat = 52
        static let titlebarHPadding: CGFloat = 16
        // D10（2026-09-16）：系统交通灯（关闭/最小化/缩放）已完全移除，
        // 相关尺寸 token（原 trafficLightSize/Gap/BlockWidth）随之废弃；
        // 关闭入口移入「⋯」菜单的「退出 2way」，窗口拖动改由自绘标题栏的原生拖拽区负责。
        /// 标题栏右侧操作区最小宽（对应 Demo `.tb-right` 的 min-width）
        static let titlebarTrailingMinWidth: CGFloat = 52

        static let searchAreaPadding: CGFloat = 16
        static let searchFieldHeight: CGFloat = 36
        static let searchFieldRadius: CGFloat = 9

        static let rowHeight: CGFloat = 76
        static let rowHPadding: CGFloat = 12
        static let rowSpacing: CGFloat = 2
        static let listPaddingH: CGFloat = 8
        static let listPaddingV: CGFloat = 4
        static let rowCornerRadius: CGFloat = 10

        static let footerHeight: CGFloat = 72
        static let footerHPadding: CGFloat = 20
        static let addButtonHeight: CGFloat = 40
        static let addButtonRadius: CGFloat = 20

        /// 左滑最大位移 = 72×2 + 间距 8 + 右边距 8（PRD R2）
        static let swipeMaxOffset: CGFloat = 160
        /// 吸附阈值 = 0.45 × 160（PRD R3）
        static let swipeSnapThreshold: CGFloat = 72
        /// 拖拽判定阈值（PRD R4）
        static let swipeDragThreshold: CGFloat = 8
        static let actionButtonWidth: CGFloat = 72
        static let actionButtonSpacing: CGFloat = 8

        static let ringSmallSize: CGFloat = 28
        static let ringSmallStroke: CGFloat = 3
        static let ringSmallRadius: CGFloat = 11
        static let ringHeroSize: CGFloat = 168
        static let ringHeroStroke: CGFloat = 5
        static let ringHeroRadius: CGFloat = 76

        static let avatarSize: CGFloat = 64
        static let avatarRadius: CGFloat = 18

        static let segmentedHeight: CGFloat = 34
        static let segmentedRadius: CGFloat = 9
        static let segmentedItemHeight: CGFloat = 28
        static let segmentedItemRadius: CGFloat = 7

        static let inputHeight: CGFloat = 42
        static let inputRadius: CGFloat = 10
        static let primaryButtonHeight: CGFloat = 44
        static let primaryButtonRadius: CGFloat = 12
        static let secondaryButtonHeight: CGFloat = 40
        static let previewCardHeight: CGFloat = 76

        /// 导入图片页拖放区**高度**（v1.10：宽度改为自适应 —— 窗口收窄到 360 后
        /// 内容区只有 320pt，固定 360 宽会溢出窗口）
        static let scannerHeight: CGFloat = 340
        static let scannerRadius: CGFloat = 14
        static let dialogWidth: CGFloat = 304
        static let dialogRadius: CGFloat = 16

        static let pagePadding: CGFloat = 20
    }

    // MARK: - 动效（PRD §7.2 R1/R3/R8）

    enum Motion {
        /// 行复制反馈持续时长
        static let copiedFeedback: Double = 0.65
        /// 左滑吸附 / 回弹
        static let swipeSettle: Double = 0.3
        /// 左滑吸附曲线 cubic-bezier(.2,.8,.2,1)
        static let swipeCurve = UnitCurve.bezier(
            startControlPoint: UnitPoint(x: 0.2, y: 0.8),
            endControlPoint: UnitPoint(x: 0.2, y: 1.0)
        )
        /// 屏幕切换
        static let screenTransition: Double = 0.26
        /// Toast 停留时长
        static let toastDuration: Double = 1.8
    }

    // MARK: - 字体（PRD §8.2，D4 决策：等价替代）
    //
    // 用 system(design: .monospaced) 对应 SF Mono，中文自动回落到 PingFang SC。
    // 验证码必须叠加 .monospacedDigit()，这是 AC「数字变化时列宽不跳动」的直接保障。

    enum Typography {
        /// 窗口标题 13 / Medium
        static let windowTitle = Font.system(size: 13, weight: .medium)
        /// 账户名（列表）15 / SemiBold
        static let accountName = Font.system(size: 15, weight: .semibold)
        /// 验证码（列表）22 / Medium，字距 1.5
        static let codeList = Font.system(size: 22, weight: .medium, design: .monospaced)
        /// 验证码（详情）28 / Medium，字距 1
        static let codeHero = Font.system(size: 28, weight: .medium, design: .monospaced)
        /// 验证码（预览）20 / Medium，字距 1.5
        static let codePreview = Font.system(size: 20, weight: .medium, design: .monospaced)

        static let body = Font.system(size: 13, weight: .regular)
        static let label = Font.system(size: 12, weight: .medium)
        static let caption = Font.system(size: 11, weight: .regular)
        static let button = Font.system(size: 15, weight: .semibold)
    }
}

// MARK: - Hex 初始化

extension Color {
    /// 以 0xRRGGBB 形式构造颜色（Design Tokens 专用）
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0,
            opacity: 1.0
        )
    }
}
