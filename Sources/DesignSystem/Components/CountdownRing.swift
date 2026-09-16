import SwiftUI

/// 倒计时环的**纯几何换算**（独立出来是为了可被单测覆盖，C0-2）
///
/// 对应 Demo 的 `stroke-dasharray = C` / `stroke-dashoffset = C × (1 - progress)`：
/// 可见弧长 = 周长 × progress，起点在 12 点钟方向、顺时针。
enum RingGeometry {

    /// 把任意输入收敛到合法区间。NaN / 负数 / 超界都不能让绘制出错。
    static func clamped(_ progress: Double) -> Double {
        guard progress.isFinite else { return 0 }
        return min(1, max(0, progress))
    }

    /// `CAShapeLayer.strokeEnd` 的取值
    static func strokeEnd(for progress: Double) -> Double {
        clamped(progress)
    }

    /// 可见弧长（pt）。用于断言换算结果与周长成正确比例。
    static func arcLength(radius: CGFloat, progress: Double) -> CGFloat {
        let circumference = 2 * .pi * Double(radius)
        return CGFloat(circumference * clamped(progress))
    }
}

// MARK: - 单一 30Hz 时钟（TECH_PLAN §4.4 / P-1）

/// 所有环共用一个 30Hz Timer；每帧只做「读 TOTPTime.state → 写 strokeEnd」。
///
/// 性能（C3-2 实测教训）：SwiftUI `TimelineView(.animation)` 30Hz 会让整个行列表
/// 每帧失效，连带 AppKit 全窗口 `layoutIfNeeded`（sample 实测主线程 2/3 时间在
/// 布局引擎），5 环 CPU ≈ 36%。改为 CAShapeLayer 直接驱动后，
/// SwiftUI 每秒只在整秒边界失效一次（验证码文本刷新），环的更新完全绕开 SwiftUI。
@MainActor
final class RingClock {
    static let shared = RingClock()

    private struct WeakBox { weak var view: RingLayerView? }

    private var clients: [WeakBox] = []
    private var timer: Timer?
    /// 已广播到的整秒（秒脉冲去重）
    private var lastBroadcastSecond: Int?

    func add(_ view: RingLayerView) {
        clients.append(WeakBox(view: view))
        start()
    }

    func remove(_ view: RingLayerView) {
        clients.removeAll { $0.view === view }
    }

    /// 常驻启动（幂等）。由 `RootView.onAppear` 与首次订阅触发。
    ///
    /// 注意：时钟**不随订阅者清空而停止** —— 早先的实现会在 clients 瞬时为空时
    /// 自停，之后无人唤醒，导致「环静止 + 码文本冻结」（用户实测反馈）。
    /// 常驻的代价只是一次/33ms 的空转回调，可忽略。
    func start() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.tick()
            }
        }
        RunLoop.main.add(timer, forMode: .common)   // .common：滚动列表时环不冻结
        self.timer = timer
    }

    private func tick() {
        clients.removeAll { $0.view == nil }
        for box in clients {
            box.view?.tick()   // 尺寸未就绪 / 不在窗口内的 view 自行早退
        }

        // 整秒脉冲（绝对秒对齐）：验证码文本 / 剩余秒数由它驱动刷新。
        // 环与码共用这一个时钟 → 换码与环重置严格同刻（T5/T6）。
        // 无条件推进（不依赖订阅者数量），保证列表为空/无环时文本仍按秒刷新。
        let second = Int(Date().timeIntervalSince1970.rounded(.down))
        if second != lastBroadcastSecond {
            lastBroadcastSecond = second
            SecondPulse.shared.bump()
        }
    }
}

/// 全局秒脉冲：`value` 每整秒 +1（由 RingClock 推进）。
///
/// 视图在 body 中读取 `SecondPulse.shared.value` 即建立 `@Observable` 观察依赖，
/// 整秒时由 SwiftUI 原生机制触发重算验证码文本。
///
/// 为什么不用 `TimelineView(.periodic)` / `onReceive`：实测两者在真实 App 中
/// 未能触发重算（码文本冻结，环在动），改用 `@Observable` 观察最可靠。
@MainActor
@Observable
final class SecondPulse {
    static let shared = SecondPulse()

    private(set) var value = 0

    func bump() {
        value &+= 1
    }
}

/// 读取全局秒脉冲并传入内容：`content` 中的验证码文本在整秒时重算。
struct SecondPulseReader<Content: View>: View {
    @ViewBuilder var content: (Int) -> Content

    var body: some View {
        content(SecondPulse.shared.value)
    }
}

// MARK: - CALayer 环视图

/// 轨道 + 进度两个 CAShapeLayer；`tick()` 由 `RingClock` 30Hz 驱动。
/// T4：剩余 ≤5s 各环独立切换告警色；T3：30Hz strokeEnd 连续推进（视觉平滑）。
final class RingLayerView: NSView {

    var period: TimeInterval = 30
    var heroTrack = false

    private let trackLayer = CAShapeLayer()
    private let progressLayer = CAShapeLayer()
    private var strokeWidth: CGFloat = 3
    private var isWarning = false
    private var lastCounter: UInt64?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true

        for layer in [trackLayer, progressLayer] {
            layer.fillColor = NSColor.clear.cgColor
            layer.lineCap = .round
            self.layer?.addSublayer(layer)
        }
        // 起点 12 点钟方向、顺时针（与 Demo stroke-dashoffset 行为一致）
        let rotation = CATransform3DMakeRotation(-.pi / 2, 0, 0, 1)
        trackLayer.transform = rotation
        progressLayer.transform = rotation

        applyColors()
    }

    required init?(coder: NSCoder) {
        fatalError("不支持 IB 初始化")
    }

    func configure(period: TimeInterval, heroTrack: Bool, strokeWidth: CGFloat) {
        if self.period != period {
            self.period = period
            lastCounter = nil   // 周期变更：下一 tick 重设进度动画
        }
        if self.heroTrack != heroTrack {
            self.heroTrack = heroTrack
            applyColors()
        }
        if self.strokeWidth != strokeWidth {
            self.strokeWidth = strokeWidth
            trackLayer.lineWidth = strokeWidth
            progressLayer.lineWidth = strokeWidth
            needsLayerGeometryUpdate = true
            needsLayout = true
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            RingClock.shared.add(self)
            tick()
        } else {
            RingClock.shared.remove(self)
        }
    }

    private var needsLayerGeometryUpdate = true

    override func layout() {
        super.layout()
        let radius = (min(bounds.width, bounds.height) - strokeWidth) / 2
        guard radius > 0 else { return }
        let rect = CGRect(
            x: bounds.midX - radius,
            y: bounds.midY - radius,
            width: radius * 2,
            height: radius * 2
        )
        trackLayer.path = CGPath(ellipseIn: rect, transform: nil)
        progressLayer.path = trackLayer.path
        needsLayerGeometryUpdate = false
        tick()   // 尺寸变化后立即对齐当前进度
    }

    /// 30Hz 时钟回调：只在**周期切换**时重设动画（否则零 layer 写入）。
    ///
    /// 同步关键（用户实测反馈：环与码刷新不同步）：动画的 `beginTime` 锚定到
    /// **绝对周期边界**（host time = 现在 − 已流逝秒数），CA 从边界时刻开始插值
    /// —— 无论 tick 因 Timer 合并延迟多少毫秒，环相位都与「换码时刻」（整秒边界）
    /// 严格同步，且永不漂移。进度插值在渲染服务端完成（T3 连续平滑，P-1 零 CPU）。
    func tick() {
        guard window != nil else { return }
        let date = Date()
        let effectivePeriod = period > 0 ? period : 30
        let state = TOTPTime.state(at: date, period: effectivePeriod)

        if state.counter != lastCounter {
            lastCounter = state.counter
            let elapsed = date.timeIntervalSince1970
                .truncatingRemainder(dividingBy: effectivePeriod)

            progressLayer.removeAnimation(forKey: "progress")
            progressLayer.strokeEnd = CGFloat(RingGeometry.strokeEnd(for: state.progress))

            let animation = CABasicAnimation(keyPath: "strokeEnd")
            animation.fromValue = 1.0   // 周期边界处进度恒为满环
            animation.toValue = 0.0
            animation.duration = effectivePeriod
            animation.beginTime = CACurrentMediaTime() - elapsed
            animation.isRemovedOnCompletion = false
            animation.fillMode = .forwards
            progressLayer.add(animation, forKey: "progress")
        }

        if state.isWarning != isWarning {
            isWarning = state.isWarning
            applyColors()
        }
    }

    private func applyColors() {
        trackLayer.strokeColor = (isWarning ? Token.Palette.ringTrackWarn : (heroTrack ? Token.Palette.ringTrackHero : Token.Palette.ringTrack)).cgColor
        progressLayer.strokeColor = (isWarning ? Token.Palette.dangerText : Token.Palette.accent).cgColor
    }
}

// MARK: - SwiftUI 接口

/// 倒计时环（PRD §7.1 行末 28/描边 3；§7.4 预览 28；§7.5 详情 168/描边 5）
///
/// T3：环内 30Hz 连续推进（RingClock 直驱 layer，非整秒跳变）。
/// T4：剩余 ≤5s 告警色，多环独立判定。详情大环轨道 `#3A3F45`（heroTrack）。
struct CountdownRing: View {
    /// 所属账户的刷新周期 —— 环自行按当前时刻换算进度
    let period: TimeInterval
    let size: CGFloat
    let strokeWidth: CGFloat
    /// 详情页大环轨道色不同（PRD §8.1）
    var heroTrack = false

    var body: some View {
        CountdownRingRepresentable(
            period: period,
            heroTrack: heroTrack,
            strokeWidth: strokeWidth
        )
        .frame(width: size, height: size)
    }
}

private struct CountdownRingRepresentable: NSViewRepresentable {
    let period: TimeInterval
    let heroTrack: Bool
    let strokeWidth: CGFloat

    func makeNSView(context: Context) -> RingLayerView {
        let view = RingLayerView()
        view.configure(period: period, heroTrack: heroTrack, strokeWidth: strokeWidth)
        return view
    }

    func updateNSView(_ nsView: RingLayerView, context: Context) {
        nsView.configure(period: period, heroTrack: heroTrack, strokeWidth: strokeWidth)
    }
}
