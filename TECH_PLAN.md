# MFA 验证器（macOS）技术方案 · v0.1

| 项目 | 内容 |
|---|---|
| 对应 PRD | `PRD.md` v1.0（2026-09-16） |
| 对应 Demo | `index.html`（单文件，内置真实 RFC 6238 计算，可作对照验收基准） |
| 方案版本 | v0.1 待评审 |
| 编制日期 | 2026-09-16 |

---

## 0. 决策冻结

| # | 决策项 | 结论 | 影响面 |
|---|---|---|---|
| D1 | 最低部署目标 | **macOS 14.0**（Sonoma） | 可用修饰符、状态层、测试矩阵 |
| D2 | 窗口与标题栏 | **方案 A**：`.windowStyle(.hiddenTitleBar)` + `NSWindow` 微调 | G-01/G-02/G-03 |
| D3 | 密钥存储 | **方案 A**：每账户一条 `kSecClassGenericPassword` item | S1、数据层全部 |
| D4 | 字体 | **等价替代**：`system(design:.monospaced)` + `monospacedDigit`，中文走系统 PingFang SC | G-06、§8.2 |
| D5 | 签名身份 | **自签 Code Signing 证书**（非 ad-hoc） | 密钥存储 S1 的可用性、全部构建流程，详见 §9 |
| D6 | 平台范围 | **仅 macOS 原生**，不做跨平台 | PRD §4 范围外条款维持；评估过程见 §10 |
| D7 | 二维码获取方式 | **仅图片导入**，移除摄像头扫码 | FR-04、页面 02、C2-6；PRD v1.1 |
| D8 | 窗口尺寸 | **接受 360×732**（高度：32pt 隐形标题栏让给列表区；宽度：v1.10 由 400 收窄到 360，20 一档比选后拍板），不自绘交通灯 | G-01/G-02/G-03；PRD v1.2 + v1.10；实测依据 §11 RK7 |

> D1 依据（v1.1 更新）：原依据 `AVCaptureMetadataOutput`（macOS 13.0+）随摄像头功能一并移除而作废；现依据为 `Observation` 框架 `@Observable` 的 **macOS 14.0** 下限（见 §2）。定 14.0 仍可无缺口覆盖 P0/P1/P2 全部需求。
> D5 依据：本机 A/B 实测证明 ad-hoc 的 DR 随 cdhash 变化，重建后读取已存密钥会弹密码框（§9.2）。
> D6 依据：跨平台无法同时满足逐像素验收与 S2，且性能目标无法承诺。详见 §10。

---

## 1. 需求基线

**产品定位**：macOS 原生 TOTP 验证器，360×732pt 竖向窄窗，仅深色，对标 Google Authenticator 的操作心智。

**P0 交付物（7 项）**
验证码列表 · 点按复制 · 左滑操作（**编辑｜删除**）· 添加账户（**图片导入** + 手动）· 删除确认（就地）· TOTP 引擎与倒计时 · 搜索

> v1.8 变更：原「账户详情」页移除（用户实测决策，PRD §7.5）；删除确认由「详情页内弹窗」改为**列表就地弹窗**（`DeleteConfirmDialog`）。

**P1**：触控板双指横滑、全局快捷键、编辑账户、导入导出/备份、剪贴板自动清除
**P2**：菜单栏常驻、iCloud 同步、生物识别锁定、多主题
**范围外**：HOTP、多租户/团队共享、非 macOS 平台

**三条硬约束（主导技术选型）**

| 编号 | 约束 | 技术含义 |
|---|---|---|
| 安全 S1–S3 | 密钥只进 Keychain；验证码不进日志/崩溃报告；进程信息不暴露密钥（`ps` 不可见） | 密钥全程 `Data`，不走 `String`/`UserDefaults`/命令行参数/环境变量；`os_log` 只允许出现账户 UUID |
| 性能 P-1 | 单实例 ≤7 个环同时动画，CPU < 1% | 单一时钟源，30Hz 上限；验证码文本不参与每帧重算 |
| 视觉 §8 | Design Tokens 全量逐像素对齐；左滑 R1–R11 十一条规则 | Tokens 集中常量；左滑独立成卡 + 手工回归清单 |

---

## 2. 环境实证结论

本机：macOS 27.0 (26A428) · Xcode 27 · Apple Swift 6.4 · xcodegen 2.46.0
工作区即本仓库根目录（已推送 GitHub，见 README）。

以下版本号来自本机 macOS SDK 的 `swiftinterface` / 头文件实测，非经验推断：

| API | 最低版本 | 对应需求 | 来源 |
|---|---|---|---|
| `.windowStyle(.hiddenTitleBar)` | macOS 11.0+ | G-03 自绘标题栏 | `SwiftUI.swiftinterface:12407` |
| `WindowResizability` / `.windowResizability` | macOS 13.0+ | G-01 固定窗口尺寸 | `SwiftUI.swiftinterface:604, 621` |
| `TimelineView` / `AnimationTimelineSchedule` | macOS 12.0+ | T3 连续平滑倒计环 | `SwiftUI.swiftinterface:29444, 11238` |
| `MenuBarExtra` | macOS 13.0+ | P2 菜单栏常驻 | `SwiftUI.swiftinterface:2106` |
| **`AVCaptureMetadataOutput`** | ~~macOS 13.0+~~ | ~~活体扫码~~ → **v1.1 起不再需要** | `AVCaptureMetadataOutput.h:26` |
| `AVMetadataObjectTypeQRCode` | macOS 10.15+ | ~~二维码类型~~ → 不再需要 | `AVMetadataObject.h:531` |
| `VNDetectBarcodesRequest`（Vision） | macOS 10.13+ | **图片导入解码 —— 现为唯一解码路径** | `VNDetectBarcodesRequest.h:20` |
| `AVCaptureSession` / `AVCaptureVideoDataOutput` | ~~macOS 10.7+~~ | ~~摄像头采集（兜底路线）~~ → **不再需要** | `AVCaptureSession.h:30` |
| `AVCaptureDevice.authorizationStatus/requestAccess` | ~~macOS 10.14+~~ | ~~摄像头权限~~ → **不再需要** | `AVCaptureDevice.h:2171` |
| **`Observation` / `@Observable`** | **macOS 14.0+** | 状态层 —— **D1 的现依据** | `Observation.swiftinterface:21` |
| `CryptoKit.Insecure.SHA1`（→ `HMAC<Insecure.SHA1>`） | macOS 10.15+ | TOTP 算法 | `CryptoKit.swiftinterface:561` |
| `LAContext` / `LAPolicyDeviceOwnerAuthenticationWithBiometrics` | macOS 10.12.2+ | P2 生物识别锁定 | `LAContext.h:34` |
| `NSWindow.titlebarAppearsTransparent` | macOS 10.10+ | 标题栏透明 | `NSWindow.h:309` |
| `.onKeyPress(_:action:)` | macOS 14.0+ | C3 键盘可达 | `SwiftUI.swiftinterface:25732` |
| `.onChange(of:initial:)` | macOS 14.0+ | 状态观察 | `SwiftUI.swiftinterface:15845` |

**必须记住的推论**

1. **v1.1 移除摄像头后，D1 的依据已更换（结论不变）**：原依据 `AVCaptureMetadataOutput`（macOS 13.0+）随功能一起作废；现依据是 `Observation` 框架的 `@Observable` 要求 **macOS 14.0**，以及 `UnitCurve`（在 14.0 部署目标下编译通过）。这两条更贴近架构核心，比原依据更硬。
2. `VNDetectBarcodesRequest`（macOS 10.13+）现在承担**唯一**解码路径的职责 —— 原先「摄像头 + 图片」双路径互为兜底的冗余设计消失了，因此这张卡的单测与异常用例覆盖度要求相应提高（见 §4.6）。
3. 移除摄像头同时消掉一整个风险面：不再需要 `NSCameraUsageDescription`、不再有摄像头 TCC 授权（也就没有「重建后授权失效」这条运维负担）、沙盒化时的 `com.apple.security.device.camera` entitlement 也一并取消。

---

## 3. 架构

```
窗口外壳        NSWindow 360×732 (固定)  │  自绘标题栏 52pt (hiddenTitleBar + 交通灯)
                      ↓
功能屏 · P0     验证码列表  │  添加账户(导入图片/手动)  │  编辑 / 删除确认(覆盖列表)
                      ↓
状态与时钟      AccountStore (@Observable)  │  单一时钟源 30Hz  │  行展开状态(单值→互斥)
                      ↓
服务层          TOTP 引擎  │  密钥存储(Keychain 唯一出口)  │  剪贴板  │  图片导入与解析
                      ↓
领域 / 设计     Account · OTPParameters  │  DesignSystem (§8 tokens + 基础组件)

安全硬约束：密钥只经 Keychain 出入 · 不落盘 · 不进日志 · 不暴露于 ps
```

**核心设计取舍**

| 取舍 | 决定 | 理由 |
|---|---|---|
| 时间源 | 全局**一个**时钟源，`progress` 向下传参 | 每行自持 Timer → 7 个 Timer 漂移 + 违反 P-1 |
| 状态管理 | `@Observable` 单一 `AccountStore` | 列表/编辑/弹窗共享同一份数据，避免多源不一致 |
| 行展开状态 | `openedRowID: Account.ID?`（单值） | R9「同时最多一行展开」由类型天然保证，无需手动收敛 |
| 密钥形态 | 全程 `Data`，不出 `KeychainStore` | 降低进入崩溃报告/日志的概率 |
| 切屏过渡 | **列表用 `.transition(.identity)`，子页才用 `.opacity`** | `.opacity` 过渡会把透明度**逐个施加到子树里的视图**：行底 alpha<1 时，左滑 ZStack 底层那张操作块（编辑｜删除）会透出来 → 「从子页回到主页时所有行闪现两个按钮」。取证：`--row-trace`（偏移恒 0，排除状态问题）+ `--slow-transition 3 --list-transition-opacity` A/B 连拍（旧行为 34/122 帧命中透出、最大 36671 偏红像素；改 `.identity` 后 0/123 帧） |
| 关闭窗口 | **⌘W 由 `CloseWindowMenu` 接管为 `close()`，不要依赖关闭按钮** | D10 把交通灯做成不可见后，AppKit 会**顺带把标准按钮置为 disabled**（`isHidden` 与 `alphaValue=0` 都如此，显式 enable 无效）；而系统 ⌘W 走 `performClose(_:)` = 「模拟点击关闭按钮」→ 空操作。凡「隐藏系统窗口按钮」的窗口，都要自行接管关闭菜单项（或改用 `close()`） |
| 滚动容器 | **一律 `.scrollIndicators(.never)`** | 铁律（源自《滚动条去除方法论》）：`.never` = 根本不创建 scroller（`has=0`/`scroller=nil`/占位 0）；`.hidden` = 只藏起来，**仍创建并占位 17px**，会让内容左右微移；两者叠加还会自相抵消。禁止 `showsIndicators:`（软废弃）。**踩坑成本**：本项目列表页正是这个写法，导致滚动条常驻 + 内容右移 17px |

---

## 4. 关键技术点详设

### 4.1 窗口与标题栏（D2 = 方案 A）

- `WindowGroup` + `.windowStyle(.hiddenTitleBar)` + `.windowResizability(.contentSize)`，`content` 固定 360×732pt
- `NSWindow` 后置微调（通过 `NSViewRepresentable` 拿 `window`）：`titlebarAppearsTransparent = true`、`titlebarSeparatorStyle = .none`、`isMovableByWindowBackground = true`
- 标题栏 52pt 自绘，左侧保留系统交通灯（`standardWindowButton(_:)` 可微调位置/间距），中间 13px Medium 标题，右侧上下文操作
- **待 spike 验证**：系统窗口圆角与 PRD 12px 的实际差值；内容裁切的实现方式（`contentView.layer.cornerRadius` + `masksToBounds` vs 内层容器圆角）
- 灰度顺序：先 spike 出截图与 A/B/C 对比，再决定是否追加无边框自绘的补齐工作

### 4.2 密钥存储 `KeychainStore`（D3 = 方案 A）

| 项 | 设计 |
|---|---|
| Item 类型 | `kSecClassGenericPassword` |
| 分组 | `kSecAttrService` = Bundle ID |
| 主键 | `kSecAttrAccount` = 账户 UUID（非名称，允许重名） |
| 密钥 | `kSecValueData` = Base32 解码后的原始字节 `Data`（落库前即解码，避免磁盘上残留可读 Base32） |
| 元数据 | `kSecAttrGeneric` = JSON（displayName / issuer / algorithm / digits / period / addedAt） |
| 可访问性 | `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`（不随备份迁移） |
| 读取 | 启动时一次 `SecItemCopyMatching`，`kSecMatchLimitAll` + `kSecReturnAttributes` + `kSecReturnData` 批量拉全量，内存缓存 |
| 写入 | 单账户 `SecItemAdd` / `SecItemUpdate` / `SecItemDelete`，账户生命周期独立 |

**必须实测确认的三点**（C1-1 已全部实证，见 `Tests/TwoWayTests/KeychainStoreTests.swift`）
1. ✅ `SecItemAdd` 用 `kSecUseKeychain` 指定目标钥匙串 —— 可行
2. ✅ 查询类调用（CopyMatching / Update / Delete）改用 `kSecMatchSearchList` 注入目标钥匙串 —— 可行。
   注意 `kSecUseKeychain` **不能**出现在查询字典里、`kSecMatchSearchList` **不能**出现在 Add 字典里，混用即 `errSecParam(-50)`
3. ⚠️ **原假设「启动时一次 `kSecMatchLimitAll` 批量拉全量（含 secret）」不成立**：
   `kSecMatchLimitAll` + `kSecReturnData` 被 macOS 拒绝（`-50`，系统不允许一次性批量倒出所有密码数据）。
   修正后的设计（也更安全）：
   - `readAllMetadata()` → `kSecMatchLimitAll` + `kSecReturnAttributes`，**只取元数据**，渲染列表不碰密钥
   - `read(id:)` → 默认 `kSecMatchLimitOne` + `kSecReturnData`，**取码时才逐条取密钥**
4. 是否启用 `kSecUseDataProtectionKeychain`：影响沙盒行为与钥匙串访问组。**本方案不启用**（见下），因此 `kSecAttrAccessible` / `kSecAttrAccessGroup` 在 legacy macOS 钥匙串上不生效，访问控制交由系统默认 ACL（「创建者应用」）—— 这正是 §9 依赖的 DR 绑定机制

**S1–S3 落地清单**
- [ ] 密钥不出现在任何 `print` / `os_log` / `Logger` 调用中（日志只允许账户 UUID）
- [ ] 密钥不经命令行参数、环境变量、`UserDefaults` 传递
- [ ] `Account` 实现 `CustomDebugStringConvertible`，调试输出显式脱敏
- [ ] 不把密钥写入 SwiftData / JSON / plist
- [ ] 验收：`ps aux | grep` 与 `lldb` 附加检查均无法从进程信息得到密钥

### 4.3 TOTP 引擎 `TOTPEngine`

- `CryptoKit.HMAC<Insecure.SHA1>`（macOS 10.15+），RFC 6238 默认 SHA-1 / 6 位 / 30 秒；高级选项可配 SHA-256 / SHA-512、6/8 位、周期
- 显示格式 `XXX XXX`（T2），**复制时去空格**
- Base32 解码需容忍清洗：去空白与连字符、转大写（E3）；非法字符在**提交时**拦截并提示（E4），不产出错误验证码
- **单测直接用 RFC 6238 附录 B 标准向量**，不靠手工比对：
  - secret `12345678901234567890`（ASCII），T = 59s → 8 位 `94287082`
  - 6 位场景取末 6 位 → `287082`
  - 覆盖：周期边界（T 为 30 的整数倍 ±1）、Base32 清洗、非法字符、算法/位数变体
- 注意：`Insecure.SHA1` 只是 CryptoKit 的命名空间划分，不是「劣化实现」；TOTP 生态默认 SHA-1，必须保留

### 4.4 单一时钟源与倒计环（T3 / T4 / T5 / P-1）

- 列表根节点挂 **一个** `TimelineView(.animation(minimumInterval: 1.0/30))`，`progress` 作为参数传给每一行
- 30Hz 而非屏幕刷新率：视觉上已足够平滑，且是满足 P-1（CPU < 1%）的主要手段
- 环用 `Circle().trim(from: 0, to: progress).stroke(...)`（替代 Demo 的 `strokeDashoffset` 换算），必要时下沉到 `Canvas`
- 验证码文本只在 `counter` 变化时（每 30s 一次）重算并更新，**不参与每帧重算** → 满足 T5「跨周期刷新无闪烁」
- T4 告警态：`remaining ≤ 5` 时，多行**各自独立**判定；环进度 `#F28B82`、轨道 `#3A2B2B`（v1.8 起仅剩列表小环；原详情大环 `#3A3F45` 随详情页移除，Token 保留备用）
- 性能验收：7 环稳态下用 Instruments（Time Profiler + Core Animation）出 CPU% / RSS / 线程数表格

### 4.5 左滑手势状态机（R1–R11 映射）

| 规则 | 原生实现要点 |
|---|---|
| R1 点按行 → 复制 | 复制 + 行底闪 `#2E3237` 650ms + toast「验证码已复制」；受 suppress 保护 |
| R2 左滑露出操作块 | 位移夹取 `[-160, 0]`；160 = 按钮 72×2 + 间距 8 + 右边距 8 |
| R3 释放吸附/回弹 | 阈值 `|x| ≥ 72`（0.45 × 160）吸附至 −160，否则回弹；动画 `.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.3)` |
| R4 拖拽判定 | `|dx| > 8 且 |dx| > |dy|` 才判定为横向拖拽，否则视为点按 |
| R5 已展开行点按 | 仅收起，**不复制、不跳转** |
| R6 吞掉拖拽后的 click | `suppressTap` 标志；**本卡最高风险项**，需回归验证 |
| R7 点「编辑」 | `store.selectedAccountID` 赋值 + 切屏 `.editAccount`；行复位 |
| R8 点「删除」 | 置 `router.pendingDeleteID`，**不切屏**、立即弹出就地确认（v1.8：原 260ms 延迟切屏弹窗取消） |
| R9 单行互斥 | `openedRowID` 单值天然互斥；切非列表屏时置 `nil` |
| R10 拖拽中 | 关闭位移过渡（跟手），释放后恢复；禁止文本选中；竖向滚动不受影响 |
| R11 悬停 | 行底 `#232528`，行末浮现 16px 复制图标；图标点击同样复制且不冒泡 |

**操作块样式**：高 76（与行同高）、宽 72、圆角 10、间距 8；「编辑」底 `#2E3237` 字 `#E9EBED`，「删除」底 `#E5484D` 字白。行底色**必须不透明**（`#1B1C1E`），否则操作块会透出。

**实现路线**：先用纯 SwiftUI（`DragGesture(minimumDistance: 8)` + 状态机 + suppress 标志）；若实测存在偶发误触，升级为 `NSViewRepresentable` 包 `NSPanGestureRecognizer`，把 tap 判定收回 AppKit 层，规避 SwiftUI 手势竞争。

### 4.6 图片导入与解析（v1.1：不再包含摄像头）

| 环节 | 实现 | 版本 |
|---|---|---|
| 图片获取 | 拖放区接收拖入的图片文件；点击唤起 `NSOpenPanel`，限定图片 UTI | macOS 10.11+ |
| 解码 | Vision `VNDetectBarcodesRequest`，symbology 限定 `.qr` | macOS 10.13+ |
| 解析 | `OTPAuthURI` 解析器，产出 secret / issuer / account / algorithm / digits / period | 自研 |
| 落库 | 先经 `KeychainStore` 写入，再刷新列表（复用 FR-04 手动输入的同一条路径） | 自研 |

**设计要点**

- 解码成功 → 切到「手动输入」分段并**预填**全部字段，由用户确认后提交。不直接入库 —— 用户需要看到解析结果，也避免解析偏差静默产生错误账户（PRD 7.4）
- 职责单一化：**Vision 现在是唯一解码路径**，原先「摄像头（`AVCaptureMetadataOutput`）+ 图片（Vision）」的双路径互为兜底没有了。因此这一卡必须把异常路径测全：无二维码、图片损坏、非 otpauth 内容、含多个二维码（PRD E9/E10/E11）
- 拖放区沿用 v1.0 取景框的几何与渐变底（360 × 340 / 圆角 14 / `#0F121A → #212433`），仅把四角取景括号换成 1 px 虚线描边、扫描线动画删除，保持设计语言连续（PRD 7.4）
- **不申请摄像头权限**：App 的 Info.plist 中不得出现 `NSCameraUsageDescription`。这条列入 C2-6 验收判据（见 PRD 7.4 AC 末条）

### 4.7 剪贴板

- P0：`NSPasteboard.general.clearContents()` + `setString(_:forType:.string)`；返回值判空 → 失败时 toast「复制失败，请手动复制」（E1），**不静默失败**
- P0：`remaining ≤ 5` 时照常复制、正常 toast，不做二次确认（E6）
- P1（S4）：复制后 N 秒自动清除。**必须先记录写入后的 `changeCount`，仅在自己仍是当前持有者时才清除**，否则会误清用户后续复制的内容

### 4.8 字体与 Design Tokens（D4 = 等价替代）

| 用途 | PRD 规格 | 原生实现 |
|---|---|---|
| 窗口标题 | Noto Sans SC 13 / Medium | `.system(size: 13, weight: .medium)` |
| 账户名（列表） | Noto Sans SC 15 / SemiBold | `.system(size: 15, weight: .semibold)` |
| 验证码（列表） | JetBrains Mono 22 / Medium，字距 1.5 | `.system(size: 22, weight: .medium, design: .monospaced)` + `.monospacedDigit()` |
| ~~验证码（详情）~~ | ~~JetBrains Mono 28 / Medium~~ | v1.8 随详情页移除 |
| 验证码（预览） | JetBrains Mono 20 / Medium，字距 1.5 | 同上，size 20 |

- `.monospacedDigit()` 是 AC「数字变化时列宽不跳动」的直接保障，不能只靠等宽字体
- §8 全量颜色 / 圆角 / 尺寸落在 `DesignSystem/Tokens.swift`，**只此一处**，禁止散落硬编码
- 分隔线 `#26282C`、窗口描边 `#33363B`、弹窗底 `#24272B`、弹窗描边 `#36383D` 这几项在 PRD §8.1 表里没列全，但 Demo 的 `:root` 里有——**以 Demo 实测值为准**（PRD 修订记录已声明「交互参数以可交互原型实测值为准」）

---

## 5. 工程结构（建议）

```
2way/
├─ project.yml                  # xcodegen 2.46.0
├─ PRD.md
├─ index.html                   # 对照验收基准
├─ TECH_PLAN.md
├─ TASK_BOARD.md
├─ Sources/
│  ├─ App/                      # @main、Scene、WindowConfigurator
│  ├─ Features/
│  │  ├─ AccountList/           # 列表 + 行 + 左滑
│  │  ├─ AddAccount/            # 导入图片 + 手动 + 编辑（复用表单）
│  │  └─ Backup/                # 备份导出/导入 + GA 迁移码导出
│  │      （详情页 v1.8 移除；删除确认弹窗为 DesignSystem/Components/ConfirmDialog）
│  ├─ State/                    # AccountStore、ClockTicker、RowExpansionState
│  ├─ Services/                 # TOTPEngine、KeychainStore、Clipboard、QRImageDecoder、OTPAuthURI
│  ├─ Domain/                   # Account、OTPParameters
│  └─ DesignSystem/             # Tokens、Component/*
└─ Tests/                       # 只覆盖 Services / Domain
```

---

## 6. 分卡计划

| 卡 | 内容 | 完成判据 |
|---|---|---|
| **阶段 0 · 骨架** | | |
| C0-1 | `project.yml` → App target，最低 macOS 14.0，Bundle ID 待定 | `xcodegen generate` 成功、空窗可跑 |
| **C0-1b** | **创建自签代码签名证书并接入构建（§9.3）** | `codesign -d -r- App.app` 输出中**不含 `cdhash H"..."`** |
| C0-2 | `Tokens.swift`（§8 全量）+ 基础组件（TitleBar 52 / PrimaryButton / SecondaryButton / Segmented / Ring / Toast / TextField） | 组件可独立预览，取值与 §8 逐项对齐 |
| C0-3 | `spike-window`：窗口 400×700 + hiddenTitleBar + 圆角/交通灯实测 | 出截图 + A/B/C 结论，锁定圆角实现方式 |
| **阶段 1 · 引擎（纯逻辑，可单测）** | | |
| C1-1 | `KeychainStore`（方案 A）+ 往返单测 + §4.2 两项实测确认 | 加/查/删/批量拉取全通过 |
| C1-2 | `TOTPEngine` + RFC 6238 标准向量单测 | 向量全绿，含边界与清洗用例 |
| C1-3 | `OTPAuthURI` 解析器 + URL 单测 | 覆盖 otpauth 合法/非法/缺参 |
| C1-4 | `ClockTicker` 单一时钟源 | 7 订阅者同一 tick，无漂移 |
| **阶段 2 · P0 主流程** | | |
| C2-1 | 列表页：搜索（FR-03）、计数、悬停、空态（E2/E7） | 输入即过滤，计数同步 |
| **C2-2** | **`spike-swipe`：R1–R11 全量 + 手工回归清单** | **11 条规则逐条通过，含 R6 吞 click** |
| C2-3 | 复制 + toast + E1 失败路径 | 点按 1 步完成，失败有提示 |
| C2-4 | 倒计环 + 告警态（T4）+ 跨周期无闪烁（T5） | 与 Demo 并排比对逐秒一致 |
| C2-5 | 手动输入页：校验 E3/E4 + 实时预览 + 高级选项折叠 | 密钥变更即刷新预览 |
| C2-6 | **导入图片页**：拖放 + 选择文件 + Vision 解码 + 预填（v1.1 已移除摄像头） | 能解码并预填到手动输入页；E9/E10/E11 异常路径均有提示；Info.plist 无 `NSCameraUsageDescription` |
| ~~C2-7~~ | ~~详情页：身份区 + 168 大环 + 参数卡 + 操作区~~ | **v1.8 移除**（用户实测决策；参数核对改由「左滑 → 编辑」承担） |
| C2-8 | 删除确认弹窗（FR-06，**就地覆盖列表**） | 必经二次确认；确认后留在列表、列表同步减少 |
| **阶段 3 · 验收与交付** | | |
| C3-1 | 逐像素比对（行高/字号/间距/圆角，对照 `index.html`） | 差异项列表 + 处置结论 |
| C3-2 | 性能实测（7 环 CPU / RSS / 线程） | 出对比表格，CPU < 1% |
| C3-3 | 安全自查（`ps`、日志、落盘） | §4.2 清单全勾 |
| C3-4 | Release：archive → ad-hoc 重签 → `hdiutil` UDZO → 校验 → 挂载实测 | `dist/*.dmg` 可挂载运行 |

**每卡纪律**：构建 + 单测 + 提交；新增文件走 `xcodegen generate` 收录；测试只覆盖 Services / Domain 层，UI 层走手工回归。

---

## 7. 未决项（需确认后才能开工）

| # | 事项 | 阻塞的卡 |
|---|---|---|
| U1 | 是否沙盒化（App Sandbox） | C1-1（Keychain 行为）、C2-6（选图 entitlement） |
| U2 | **Bundle ID 与应用名** —— 一旦开始存储密钥即不可再改（DR 的 identifier 子句锚定它，改动 = 已存密钥全部不可读） | C0-1、C0-1b |
| U3 | G-04 原型导航：删除 or 保留为开发期调试入口 | C0-2 |
| U4 | G-05 缩放策略：是否确认映射为「固定尺寸窗口 + 内部不响应式重排」 | C0-3 |
| U5 | 是否沿用既有工程纪律（xcodegen + `TASK_BOARD.md` + 每卡提交 + `release-package.sh`） | 全部 |
| U6 | 是否初始化 git 仓库（当前工作区不是 git repo） | 全部 |
| ~~U7~~ | ~~跨平台是否为确定需求~~ → 已定：**不做**，见 D6 | 已关闭 |
| ~~U8~~ | ~~是否接受 webview 路线两项代价~~ → 不适用 | 已关闭 |
| U9 | 自签证书的创建方式（Keychain Access 图形界面 or openssl 脚本化） | C0-1b、C3-4 |

---

## 8. 风险登记册

| # | 风险 | 等级 | 应对 |
|---|---|---|---|
| RK1 | R6「拖拽后补发的 click 被吞掉」在 SwiftUI 手势体系下可能偶发失效 | 高 | C2-2 独立成卡 + 手工回归清单；备选 NSPanGestureRecognizer 路线 |
| ~~RK2~~ | ~~`AVCaptureMetadataOutput` 运行时对 `.qr` 的支持依赖设备~~ | **已关闭** | v1.1 移除摄像头，不适用 |
| RK2b | Vision 成为**唯一**解码路径，无兜底；对低质量 / 畸变 / 缩放图片的识别率未知 | 中 | C2-6 用真实截图样本集实测（手机截图、器裁剪、含透视畸变）；必要时加 `CIFilter` 预处理 |
| RK3 | 系统窗口圆角与 PRD 12px 存在差值 | 中 | C0-3 spike 出实测差值，再决定是否追加无边框自绘 |
| RK4 | `SecItemCopyMatching` 批量返回行为与预期不符 | 中 | C1-1 内先写最小验证脚本，再封装 |
| RK5 | 等价字体与设计稿存在字距/字重差异，影响「逐像素」验收 | 低 | C3-1 列出差异项并给出处置结论（接受 / 调整数值 / 改打包字体） |
| RK6 | E5 系统时间不准导致验证码偏差 | 低 | P0 仅提示；P1 做时间偏移显示 |
| ~~RK7~~ | ~~窗口 400×732 vs PRD 400×700~~ | **已关闭** | 用户选 A：接受 732，32pt 归列表区 → 决策 D8 + PRD v1.2；免掉约 80 行自绘窗口链路 |
| RK8 | 交通灯几何与 PRD 有差：实测 close 中心 (15,15)pt、直径 ≈13pt、与 yellow 中心距 23pt（PRD 写 12px 灯 + 8px 间距 = 20pt） | 低 | 接受系统几何（差 ≤3pt）；自绘标题栏不重绘交通灯，只让位 |

---

## 9. 签名方式：ad-hoc 是本项目的陷阱

**约束**：项目自用、无 Apple 开发者账号。本机实测 `security find-identity -v -p codesigning` 返回 **0 个身份** → 只能走 ad-hoc（`codesign -s -`）或自建自签证书。

### 9.1 根因：ad-hoc 的 DR 就是 cdhash

Apple TN3127《Inside Code Signing: Requirements》原文：

> "Unsigned code has no DR. Ad hoc signed code, called Sign to Run Locally by Xcode, has a DR but it's tied to that specific version of the code. In both cases macOS can't reliably track the identity of the code. … If you tweak the code and run it again, macOS repeats that prompt."

`man codesign`：

> "Ad-hoc signing does not use an identity at all, and identifies exactly one instance of code."

本机真实产物 DR 对照：

| 二进制 | 签名方式 | designated requirement |
|---|---|---|
| `/opt/homebrew/bin/python3` | ad-hoc | `cdhash H"79a07d96…"` |
| `/opt/homebrew/bin/xcodegen` | ad-hoc | `cdhash H"5a3db21a…"` |
| `~/.local/bin/node` | 证书签名 | `identifier node and anchor apple generic …` |
| `/usr/bin/ssh` | Apple 系统 | `identifier "com.apple.ssh" and anchor apple` |

注意 ad-hoc 的 DR 里**完全没有 identifier 子句** —— bundle ID 根本不参与。

### 9.2 对 Keychain 的实际后果（本机 A/B 实测）

构造两个内容不同、Bundle ID 相同的 `.app`：A 写入密钥，B 是改过代码重建的版本，B 尝试读取 A 写入的密钥。

| 组 | A 的 DR | B 的 DR | B 读取结果 |
|---|---|---|---|
| **ad-hoc** | `cdhash H"ed978a42…"` | `cdhash H"bc8ddce6…"` | ❌ **超时 10s → 弹出系统密码授权框** |
| **自签证书** | `identifier "com.kimi.mfa.acltest" and certificate root = H"31ef4f33…"` | **与 A 完全相同** | ✅ `status=0`，成功取回 `JBSWY3DPEHPK3PXP` |

结论：
- **ad-hoc：密钥不会丢**，但每次改代码重建后，读取已存密钥都会弹系统密码框。对一个每次启动都要拉取全部密钥的验证器，这不可接受。
  （同类机制也作用于 TCC 授权：任何需要摄像头 / 麦克风 / 辅助功能 / 录屏的功能，ad-hoc 下授权都会随重建失效。**v1.1 移除摄像头后，本项目已无需要 TCC 授权的功能，风险面收敛到 Keychain 一项。**）
- **自签证书：DR 稳定，重建后静默读取。**

### 9.3 决策 D5：自签代码签名证书作为唯一签名身份

- 一次性创建自签 Code Signing 证书：Keychain Access → 证书助理 → 创建证书 → 身份类型「自签名根证书」+ 证书类型「代码签名」；或用 openssl 生成后 `security import`
- **openssl 3.x 必须用 `-legacy` 导出 p12**，否则 `security import` 报 `SecKeychainItemImport: MAC verification failed during PKCS12 import`
- 开发与自用发布统一用该证书签名，**禁止使用 `codesign -s -`**
- 排查注意：`security find-identity -v -p codesigning` 会隐藏自签根（`CSSMERR_TP_NOT_TRUSTED`），必须去掉 `-v` 才能看到
- **验收硬指标**：`codesign -d -r- <App>.app` 的输出中**不得出现 `cdhash H"..."`**
- **风险转移**：证书成为身份锚点，证书丢失/换机 = 所有 Keychain 项不可读 → PRD 中 P1 的「导入导出/备份」应提前到 P0 交付后立即实现，作为唯一逃生通道
- Gatekeeper：本机自建产物无 quarantine 属性，可直接运行；一旦经 AirDrop/DMG 传到另一台机器即被隔离，需右键打开或 `xattr -dr com.apple.quarantine`
- **沙盒与 `keychain-access-groups`**：该 entitlement 属受限类型，需要 provisioning profile，自签不可用 → 设计上**不得依赖访问组**

---

## 10. 跨平台可行性评估（已评估 · 已否决 — 决策记录）

> **决策 D6（2026-09-16）：不做跨平台，仅实现 macOS 原生。** PRD §4「范围外：非 macOS 平台」维持不变。
> 本节完整保留实证证据作为决策依据存档。若将来重提跨平台，可直接复用，不必重做验证。

评估环境：macOS 27 / Xcode 27 / Swift 6.4 / **Go 1.26.5 已装** / **Rust 未装**。

### 10.1 框架现状

| | Wails | Tauri |
|---|---|---|
| 稳定版 | v2.14.0（2026-08-10） | v2（稳定） |
| 下一代 | v3.0.0-beta.8（2026-08-12，10 天内 9 个 beta tag） | — |
| 后端语言 | Go（v3 要求 Go 1.24+） | Rust |
| 渲染引擎 | WKWebView / WebView2 / WebKitGTK | 同 |
| 安装包量级 | ~10–30 MB | ~3–15 MB |

选型要点：**Wails 要用 v2（稳定），v3 的权限/托盘 API 虽好但仍是 Beta**，不适合作为本项目的地基。

### 10.2 关键可行性结论

**① 扫码可行，且此前的悲观说法在本机不成立。**
本机三点隔离实验：

| 环境 | `NSCameraUsageDescription` | `typeof navigator.mediaDevices` | `getUserMedia` |
|---|---|---|---|
| 裸 CLI | 缺失 | `undefined` | ❌ |
| .app 包 | **有** | `object` | ✅ |
| .app 包 | 缺失 | `undefined` | ❌ |

**真正的开关是宿主 app 的 Info.plist 是否声明 `NSCameraUsageDescription`**，与打包方式无关。Apple 开发者论坛、Dynamsoft 与 Tauri issue 中「WKWebView 不支持摄像头」的结论在 macOS 27 上不成立。
其余平台：Windows WebView2 完整支持并有原生权限提示；Linux WebKitGTK 默认静默拒绝，Wails v3 已内建处理，Tauri 侧需自行接 `onPermissionRequest`。
**图片文件导入二维码**在 webview 方案里反而更简单 —— 一份 JS/WASM 解码库三平台通用。

**② 密钥存储。** Rust `keyring` crate 三平台原生后端齐全（macOS Keychain / Windows Credential Manager / Linux Secret Service），Tauri 有成熟插件。Go 侧库较薄，且访问 macOS 专有框架通常要走 cgo。**Windows 与 Linux 的凭据库不绑二进制**，所以 §9 的 DR 问题只在 macOS 存在。
风险：Linux 无 D-Bus 会话（headless）时部分库会**静默回退到明文存储**，这直接违反 S1，必须在代码层显式禁止回退。

**③ 两条需要正视的代价。**
- **逐像素验收（PRD §8）在跨平台下无法同时成立** —— 三个渲染引擎（WKWebView / WebView2 / WebKitGTK）在字体渲染、CSS 特性、动画时序上都有差异。跨平台意味着验收标准要按平台拆开。
- **S2「验证码不写入日志/崩溃报告」被削弱** —— webview 方案下验证码必然进入 JS 堆，而 WKWebView 的 WebContent 是独立进程，崩溃转储可能包含它；开发期若开启 Tauri `devtools` feature，本机任意进程可通过 Web Inspector 读取 JS 内存，release 构建必须确认关闭。

### 10.3 需要先回答的前置问题

**TunnelManager 是从 Vue 3 + Tauri + Rust v1.4.3 重写为原生 Swift 的。** 本项目若重新选 Tauri，必须先明确当时重写的驱动因素（性能 / 体积 / 原生手感 / 安全 / 其他）。否则等于走回头路。

### 10.4 三条候选路线

| 路线 | 做法 | 适用前提 |
|---|---|---|
| **A（当前方案）** | macOS 原生 SwiftUI，但把 TOTP 引擎、`otpauth://` 解析、账户模型抽成**平台无关的逻辑层** | 跨平台只是「以后可能」 |
| **B** | Rust 核心 + Tauri v2 外壳，前端直接复用 `index.html` | 跨平台是确定需求；接受 §10.2③ 两项代价 |
| **C** | Go + Wails v2 | 团队 Go 熟练度高；接受 Go 侧原生 API 需 cgo 自写 |

**当前建议**：~~先按路线 A 推进~~ → **已采纳路线 A，路线 B/C 归档不再评估。**

代码组织上仍保留一项**零成本的对冲**：`Services/`（TOTP 引擎、`otpauth://` 解析、Keychain 封装、时钟源）与 `Domain/`（账户模型、参数值类型）**保持平台无关** —— 不含任何 SwiftUI / AppKit 类型。这不增加任何工作量，但让逻辑层可被单元测试完整覆盖（符合本项目「测试只覆盖 Service/Domain 层」的纪律），并为将来任何形式的复用留出可能。

**否决跨平台的依据摘要**

| # | 依据 |
|---|---|
| 1 | 逐像素验收（PRD §8）在跨平台下无法同时成立 —— 三套渲染引擎（WKWebView / WebView2 / WebKitGTK）在字体渲染、CSS 特性、动画时序上均有差异 |
| 2 | S2「验证码不写入日志/崩溃报告」被削弱 —— webview 方案下验证码必然进入 JS 堆，WKWebView 的 WebContent 是独立进程，崩溃转储可能包含它 |
| 3 | 性能 P-1（7 个环 CPU < 1%）在 webview 下无法承诺 —— rAF 受合成器驱动，通常跑满 60/120Hz，需实测才敢下结论 |
| 4 | Wails v3 仍是 Beta（不适合做地基），v2 生态薄；Tauri 需新增 Rust 工具链 |
| 5 | 跨平台动因未确认为刚性需求，而代价是确定的 |

---

## 附：与 Demo 的对照方式

`index.html` 内置真实 RFC 6238 计算（非截图），可作为**并排逐秒比对基准**：同一 secret 下，原生 App 与浏览器 Demo 的验证码应逐秒一致、倒计环同相位。这是 T6「与标准实现逐秒一致」最省事的验证手段，建议 C2-4 与 C3-1 都用它。
