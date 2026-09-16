# 2way 任务板

> 卡粒度与验收判据以 `TECH_PLAN.md` §6 为准。**每卡必须完成：构建 + 单测 + Git 提交**，才推进下一卡。
> 新增文件后执行 `xcodegen generate` 收录。
>
> 需求版本：**PRD v1.2**（2026-09-16：v1.1 移除摄像头扫码（D7）；v1.2 窗口 400×732（D8））

## 变更记录

图例：`[ ]` 待开始 · `[~]` 进行中 · `[x]` 已完成

---

## 阶段 0 · 工程骨架

| 卡 | 状态 | 内容 | 完成判据 | 提交 |
|---|---|---|---|---|
| C0-1 | `[x]` | `project.yml` → App target，最低 macOS 14.0 | `xcodegen generate` 成功、空窗可编译 | `8c3681d` |
| C0-1b | `[x]` | 创建自签代码签名证书并接入构建（§9.3） | `codesign -d -r- App.app` 输出**不含 `cdhash H"..."`** → 实测 DR = `identifier "com.kimi.2way" and certificate root = H"88f7f892…"` ✅ | 本次 |
| C0-2 | `[x]` | `Tokens.swift`（§8 全量）+ 基础组件 | 组件可独立预览，取值与 §8 逐项对齐 | `8c3681d`、`1d8bde2` |
| C0-3 | `[x]` | `spike-window`：窗口 400×700 + hiddenTitleBar + 圆角/交通灯实测 | 出截图 + 圆角实现方式结论 → RK7 已按 D8 关闭 | `6a69e99` |

**C0-2 明细**

- [x] `Tokens.swift` —— §8 全量颜色 / 尺寸 / 动效 / 字体（含 Demo `:root` 补充的 7 项）
- [x] `WindowTitlebar` + `Divider1px`
- [x] `PrimaryButton`（高 44 / 圆角 12 / 强调色底）
- [x] `SecondaryButton`（高 40 / 描边 `--border`）
- [x] `SegmentedControl`（容器 34 / 圆角 9 / 段 28 / 圆角 7 / 选中 `--seg-active`）
- [x] `CountdownRing`（小环 28/描边 3，大环 168/描边 5；告警态切换）
- [x] `Toast`（底部 44pt / 停留 1.8s）
- [x] `TokenTextField`（高 42 / 圆角 10）

**C0-3 结论（已实测）**

- [x] 系统窗口圆角 **r ≈ 12~13px**（左上/右上最小二乘拟合一致）vs PRD 12px → 差 ≤1px，可接受
- [x] 交通灯几何：close 中心 (15,15)pt、直径 ≈13pt、与 yellow 中心距 23pt（PRD 写 20pt，差 ≤3pt，可接受）
- [x] 交通灯让位：`standardWindowButton(.zoomButton)` 淡出禁用成功（固定尺寸窗口）
- [x] `.hiddenTitleBar` 必须补 `.fullSizeContentView`，否则内容下方空 32pt
- [x] `makeNSView` 里 async 取 `view.window` 拿不到 → 必须用 `viewDidMoveToWindow`
- [x] **已拍板：接受 400×732**（决策 D8 / PRD v1.2），32pt 归列表区
- [ ] 截图存档（脚本 `scripts/measure-window.swift` / `fit-corner.swift` / `bbox.swift` 可复跑）

---

## 阶段 1 · 引擎（已完成 ✅ 66 个测试全绿）

| 卡 | 状态 | 内容 | 完成判据 | 测试 |
|---|---|---|---|---|
| C1-1 | `[x]` | `KeychainStore`（D3 方案 A） | 加/查/删/批量全通过；§4.2 三项行为全部实证 | `KeychainStoreTests`（临时钥匙串，不碰登录钥匙串） |
| C1-2 | `[x]` | `TOTPEngine` + `Base32` | RFC 6238 附录 B 向量全绿（SHA1/SHA256/SHA512 × 6 时间点 × 2 位宽 = 36 条） | `TOTPEngineTests`、`Base32Tests` |
| C1-3 | `[x]` | `OTPAuthURI` 解析器 | 合法/缺参/非 otpauth（E10）/HOTP 拦截/percent-encode 全覆盖 | `OTPAuthURITests` |
| C1-4 | `[x]` | `TOTPTime` 单一换算源 | counter 边界、progress 单调、T4 阈值边界精确 | `TOTPTimeTests` |
| — | `[x]` | `Domain`：`Account` / `OTPParameters` | FR-03 匹配、参数校验、S1 调试脱敏 | `AccountTests` |

**测试基建**：`Tests/TwoWayTests/`，Swift Testing（`#expect` / `#require`）。
KeychainStore 测试用 `SecKeychainCreate` 注入**临时钥匙串**，全程不碰登录钥匙串。

**C1-1 过程中实证到的平台硬约束**（已回写 TECH_PLAN §4.2）：
`kSecUseKeychain` 只对 `SecItemAdd` 生效；`kSecMatchSearchList` 只对查询类调用生效；
**`kSecMatchLimitAll` + `kSecReturnData` 会被拒（-50）** —— 批量只能取属性，密钥必须逐条取。
由此把「启动一次拉全量含密钥」改为「启动拉元数据 + 取码时逐条取密钥」，安全形态更好。

---

## 阶段 2 · P0 主流程

| 卡 | 状态 | 内容 | 完成判据 |
|---|---|---|---|
| C2-1 | `[x]` | 列表页：搜索（FR-03）、计数、悬停、空态（E2/E7） | 输入即过滤，计数同步 |
| **C2-2** | `[~]` | **`spike-swipe`：R1–R11 全量 + 手工回归清单** —— 状态机 `SwipeRowModel`（State 层，8 个单测）+ `SwipeableAccountRow`（手势 + 操作块）已落地 | **逻辑级单测全绿；R1–R11 手工回归清单待执行（RK1 的真实手势验证）** |
| C2-3 | `[x]` | 复制 + toast + E1 失败路径 | 随 C2-1 落地；R1 闪烁 650ms 补齐于 C2-2 |
| C2-4 | `[~]` | 倒计环 + 告警态（T4）+ 跨周期无闪烁（T5）—— 列表小环 + 30Hz 单时钟源已随 C2-1 落地，T4 阈值有单测 | 剩：与 `index.html` 并排逐秒一致（手工） |
| C2-5 | `[~]` | 手动输入页：校验 E3/E4 + 实时预览 + 高级选项折叠 —— \`AddAccountView\`（分段外壳 + 导入占位）+ \`ManualEntryView\` + \`ManualEntryModel\`（9 单测）；106 测试全绿 | 剩：手工回归（输入密钥看预览刷新 / E4 报错 / 提交置顶 + toast） |
| C2-6 | `[ ]` | **导入图片页**：拖放 + 选择文件 + Vision 解码 + 预填（v1.1 已移除摄像头） | 能解码并预填到手动输入页；E9/E10/E11 异常路径均有提示；Info.plist 无 `NSCameraUsageDescription` |
| C2-7 | `[ ]` | 详情页：身份区 + 168 大环 + 参数卡 + 操作区 | 参数与账户一致 |
| C2-8 | `[ ]` | 删除确认弹窗（FR-06） | 必经二次确认；确认后回列表 |

**C2-2 明细（R1–R11 → 实现映射）**

| 规则 | 实现 |
|---|---|
| R1 点按复制 + 底色闪 `#2E3237` 650ms | `AccountRowView.flashCopied()`；复制失败不闪烁（E1 仅 toast） |
| R2 左滑露出操作块，位移 `[-160, 0]` | `SwipeLogic.clamp`；右滑归 0，不错位 |
| R3 释放吸附/回弹（阈值 72 = 0.45×160） | `SwipeLogic.settle`；曲线 `timingCurve(.2,.8,.2,1, 0.3s)` |
| R4 横向 >8px 且大于纵向才拖拽 | `SwipeLogic.isHorizontalDrag`；竖向滚动不受影响 |
| R5 展开行点按仅收起 | `SwipeableAccountRow.handleTap` |
| R6 拖拽后 click 被吞 | `SwipeRowModel.shouldSuppressTap()`（0.15s 抑制窗口）+ SwiftUI DragGesture minimumDistance 天然不触发 tap，双保险 |
| R7 点「详情」→ 详情页 | `onDetail` 回调已接 RootView（切屏在 C2-7 接入） |
| R8 点「删除」→ 详情页 + 自动弹确认 | `onDelete` 回调已接 RootView（260ms 弹窗在 C2-8 接入） |
| R9 同时最多一行展开 | `store.openedRowID` 单值互斥；本行确认拖拽即收起其他行（对齐 Demo pointerdown 行为） |
| R10 拖拽中关过渡跟手、禁止文本选中 | `.animation(isDragging ? nil : settle)`；`textSelection(.disabled)` |
| R11 悬停浮现复制图标、点击不冒泡 | 复制图标为独立 Button（吞掉点击），行底 hover `#232528` |

**C2-2 手工回归清单（待执行）**

- [ ] 鼠标左滑拖拽跟手，释放按阈值吸附/回弹，动画曲线无跳变
- [ ] 拖拽后立即点按，不触发复制（R6，RK1 高风险项）
- [ ] 竖向滚动列表时不触发行位移；右滑不错位
- [ ] 展开行 A 后再拖行 B：A 收起、B 可展开；展开行点按仅收起不复制
- [ ] 点「详情」「删除」行复位；悬停复制图标点击复制且不触发两次 toast
- [ ] 复制后行闪 `#2E3237` 650ms；告警态（≤5s）下复制照常（E6）

---

## 阶段 3 · 验收与交付

| 卡 | 状态 | 内容 | 完成判据 |
|---|---|---|---|
| C3-1 | `[ ]` | 逐像素比对（行高/字号/间距/圆角，对照 `index.html`） | 差异项列表 + 处置结论 |
| C3-2 | `[ ]` | 性能实测（7 环 CPU / RSS / 线程） | 出对比表格，CPU < 1% |
| C3-3 | `[ ]` | 安全自查（`ps`、日志、落盘） | §4.2 清单全勾 |
| C3-4 | `[ ]` | Release：archive → 全组件重签 → UDZO → 校验 → 挂载实测 | `dist/2way-*.dmg` 可挂载运行 |

---

## 阻塞项（见 TECH_PLAN §7）

| # | 事项 | 状态 |
|---|---|---|
| U1 | 是否沙盒化 | **已定：先不沙盒** |
| U2 | Bundle ID 与应用名 | **暂定 `com.kimi.2way` / 2way** —— C1-1 存储首个密钥前可改 |
| U3 | G-04 原型导航处理 | 假定：原生不需要，仅 `#if DEBUG` 保留切屏入口 |
| U4 | G-05 缩放策略映射 | 假定：固定尺寸窗口 + 内部不响应式重排 |
| U5 | 工程纪律 | **已定：沿用 TunnelManager 那套** |
| U6 | git 仓库 | **已完成** |
| U9 | 证书创建方式 | **已定：脚本代劳** —— 待执行 |
| U12 | `index.html` 与 Ardot 设计稿的第 02 屏仍是 v1.0 摄像头形态（取景框/取景括号/扫描线），需按 PRD §7.4 改版为「导入图片」拖放区 | **C3-1 逐像素比对、C2-6** |

---

## 变更记录

| 日期 | 变更 |
|---|---|
| 2026-09-16 | 项目立项；阶段 0 启动；PRD v1.0 |
| 2026-09-16 | **C2-1 列表页落地**：\`AccountStore\`（加载/搜索/计数/置顶/取码缓存）+ \`AccountListView\`（搜索/行/悬停/点按复制/Toast）；\`SecretStoring\` 协议抽象出可注入的存储层；窗口四角圆角由 \`clipShape\` 兜底（SwiftUI 恒定给窗口加 32pt 隐形标题栏，底边落在窗口中部、系统不在那里画圆角）
| 2026-09-16 | **PRD v1.1：移除摄像头扫码，添加账户改为仅「图片导入 + 手动输入」**。页面 02 由「扫描二维码」改为「导入图片」；取景框/取景括号/扫描线动画废弃；不再申请摄像头权限。影响：C2-6 重定义、RK2 关闭并新增 RK2b、D1 依据更换（结论不变）、D7 新增 |
| 2026-09-16 | **C2-2 左滑实现落地**：\`SwipeRowState\`（R2/R3/R4/R6 纯逻辑 + 8 个单测）+ \`SwipeableAccountRow\`（操作块/互斥/复制闪烁）；R1 闪烁 650ms 补齐；R7/R8 回调接至 RootView（切屏分别等 C2-7/C2-8）；测试 89 → 97 全绿。**R1–R11 手工回归清单待执行** |
| 2026-09-16 | **窗口 400×732 修复（G-01）**：根视图由固定 732 改为 minHeight 700 可伸缩 —— 原实现窗口实测 764（内容 732 + 32 隐形标题栏），底部 32pt 透明透壁纸；修复后窗口 732、32pt 归列表区，实测无透明带 |
| 2026-09-16 | **C2-5 手动输入页落地**：\`AppRouter\`（list ↔ addAccount）+ \`AddAccountView\`（分段外壳，导入图片为 C2-6 视觉占位）+ \`ManualEntryView\`（名称/密钥字段 + E4 实时报错 + 高级选项折叠 Picker + 30Hz 实时预览卡）+ \`ManualEntryModel\`（E3/E4/提交，9 单测）；ToastCenter 上移 RootView 共享（添加成功 toast 在列表页显示）；DEBUG 支持 \`--debug-add\` 切屏（U3）；测试 97 → 106 全绿 |

---

## 风险登记

| # | 风险 | 等级 | 应对 |
|---|---|---|---|
| RK1 | 左滑 R6「拖拽后补发的 click 被吞掉」在 SwiftUI 下可能偶发失效 | 高 | 已实现双保险（DragGesture minimumDistance + 0.15s 抑制窗口）+ 8 个单测；**待手工回归确认真实手势下行为**；仍保留 `NSPanGestureRecognizer` 备选 |
| RK2 | ~~`AVCaptureMetadataOutput` 运行时对 `.qr` 的支持依赖设备~~ | **已关闭** | v1.1 移除摄像头，不适用 |
| RK2b | Vision 成为**唯一**解码路径，无兜底；对低质量 / 畸变 / 缩放图片的识别率未知 | 中 | C2-6 用真实截图样本集实测（手机截图、裁剪、含透视畸变）；必要时加 `CIFilter` 预处理 |
| RK3 | 系统窗口圆角与 PRD 12px 存在差值 | 中 | C0-3 出实测差值 |
| RK4 | `SecItemCopyMatching` 批量返回行为与预期不符 | 中 | C1-1 先写最小验证脚本 |
| RK5 | 等价字体与设计稿有字距/字重差异 | 低 | C3-1 列差异项并处置 |
| RK6 | E5 系统时间不准导致验证码偏差 | 低 | P0 仅提示；P1 做偏移显示 |
