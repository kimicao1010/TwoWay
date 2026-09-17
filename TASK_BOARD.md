# 2way 任务板

> 卡粒度与验收判据以 `TECH_PLAN.md` §6 为准。**每卡必须完成：构建 + 单测 + Git 提交**，才推进下一卡。
> 新增文件后执行 `xcodegen generate` 收录。
>
> 需求版本：**PRD v1.9**（v1.1 移除摄像头扫码；v1.2 窗口 400×732；v1.3 裁剪 P1；v1.5 列表交互精简；v1.6/v1.7 导出范围与多选；v1.8 移除详情页 + 删除就地确认；**v1.9 状态栏常驻 + 下拉快速取码**）

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
- [x] 截图不入库（仓库只留可复跑脚本）：`scripts/measure-window.swift` / `fit-corner.swift` / `bbox.swift` 随时可复现 C0-3 的全部实测

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
| **C2-2** | `[x]` | **`spike-swipe`：R1–R11 全量 + 手工回归清单** —— 状态机 `SwipeRowModel`（State 层，8 个单测）+ `SwipeableAccountRow`（手势 + 操作块） | **逻辑级单测全绿 + 手工回归已通过（用户 2026-09-17 确认「功能测试没有问题」）** |
| C2-3 | `[x]` | 复制 + toast + E1 失败路径 | 随 C2-1 落地；R1 闪烁 650ms 补齐于 C2-2 |
| C2-5 | `[x]` | 手动输入页：校验 E3/E4 + 实时预览 + 高级选项折叠 —— `AddAccountView`（分段外壳）+ `ManualEntryView` + `ManualEntryModel`（9 单测） | 手工回归已通过（用户 2026-09-17 确认） |
| C2-6 | `[x]` | **导入图片页**：拖放 + 选择文件 + Vision 解码 + 预填 —— `QRImageDecoder`（Vision，面积降序）+ `QRImport.resolve`（E9/E10/无效 otpauth）+ `ImportImageView`；114 测试全绿 | 手工回归已通过（用户 2026-09-17 确认，含 GA 迁移码真实截图端到端）；**Info.plist 无 `NSCameraUsageDescription` ✅** |
| ~~C2-7~~ | `[-]` | ~~详情页：身份区 + 168 大环 + 参数卡 + 操作区~~ —— **v1.8 用户实测决策移除**（`AccountDetailView` 已删除，PRD §7.5 标注废弃） | 不适用（参数核对改由左滑「编辑」承担） |
| C2-8 | `[x]` | 删除确认弹窗（FR-06）—— **v1.8 改为就地覆盖列表**：`DeleteConfirmDialog`（遮罩 0.65 / 304 宽 / 标题明示账户名 / 文案明示不可恢复 / 取消+红底删除 / Esc 与遮罩关闭）；左滑「删除」直接弹窗，确认后留在列表 + toast | 必经二次确认 ✅ 截图验证；无切屏 ✅ |
| C2-4 | `[x]` | 倒计环 + 告警态（T4）+ 跨周期无闪烁（T5）—— **用户实测：与 GA 并排比对逐秒一致（T6 ✅）**；列表环与 T4 告警态截图确认（详情大环随 v1.8 详情页移除） | 与 \`index.html\` 并排逐秒一致 ✅（用户 2026-09-16 确认） |

**C2-2 明细（R1–R11 → 实现映射）**

| 规则 | 实现 |
|---|---|
| R1 点按复制 + 底色闪 `#2E3237` 650ms | `AccountRowView.flashCopied()`；复制失败不闪烁（E1 仅 toast） |
| R2 左滑露出操作块，位移 `[-160, 0]` | `SwipeLogic.clamp`；右滑归 0，不错位 |
| R3 释放吸附/回弹（阈值 72 = 0.45×160） | `SwipeLogic.settle`；曲线 `timingCurve(.2,.8,.2,1, 0.3s)` |
| R4 横向 >8px 且大于纵向才拖拽 | `SwipeLogic.isHorizontalDrag`；竖向滚动不受影响 |
| R5 展开行点按仅收起 | `SwipeableAccountRow.handleTap` |
| R6 拖拽后 click 被吞 | `SwipeRowModel.shouldSuppressTap()`（0.15s 抑制窗口）+ SwiftUI DragGesture minimumDistance 天然不触发 tap，双保险 |
| R7 点「编辑」→ 编辑页 | `onEdit` → `store.selectedAccountID` + `show(.editAccount)`（v1.8：原「详情」改为「编辑」） |
| R8 点「删除」→ 就地弹确认 | `onDelete` → `router.pendingDeleteID`（不切屏）；确认走 `AccountStore.delete` + toast（v1.8） |
| R9 同时最多一行展开 | `store.openedRowID` 单值互斥；本行确认拖拽即收起其他行（对齐 Demo pointerdown 行为） |
| R10 拖拽中关过渡跟手、禁止文本选中 | `.animation(isDragging ? nil : settle)`；`textSelection(.disabled)` |
| ~~R11 悬停浮现复制图标~~ | **v1.5 已移除**：复制唯一入口 = 单击整行；悬停仅保留行底 `#232528`（用户结论：图标是多余的第二入口） |

**C2-2 手工回归清单（已通过 · 用户 2026-09-17 确认「功能测试没有问题」）**

- [x] 鼠标左滑拖拽跟手，释放按阈值吸附/回弹，动画曲线无跳变
- [x] 拖拽后立即点按，不触发复制（R6，RK1 高风险项）
- [x] 竖向滚动列表时不触发行位移；右滑不错位
- [x] 展开行 A 后再拖行 B：A 收起、B 可展开；展开行点按仅收起不复制
- [x] 点「编辑」「删除」行复位；删除弹窗可在列表上直接取消/确认（不跳转）；悬停行底 `#232528` 可点击提示
- [x] 复制后行闪 `#2E3237` 650ms；告警态（≤5s）下复制照常（E6）

---

## 阶段 5 · 状态栏与系统集成

| 卡 | 状态 | 内容 | 完成判据 |
|---|---|---|---|
| C5-1 | `[x]` | **状态栏常驻 + 下拉快速取码（P2 提前交付）** —— `TwoWayApp` 挂 `MenuBarExtra`（`.menuBarExtraStyle(.window)`，原生 `.menu` 放不下搜索框）+ `MenuBarView`（搜索框自动聚焦 / 回车复制首条 / **默认最多 5 条** + 「还有 N 个账户 —— 输入关键词搜索」/ 输入即全量过滤不受 5 条限制 / 行内「已复制」反馈 / 倒计环 / 底部「打开主窗口 + 账户数 + 退出」）；图标用用户提供的 `status-bar/StatusLockTemplate-16/32.png` → Asset Catalog `StatusBarIcon`（template 渲染，深浅菜单栏自适应）；`MenuBarSelection` 纯逻辑 + 7 单测；`AppBootstrap` 幂等引导（主窗口与状态栏共用同一 store，加载只做一次） | 菜单栏图标出现 ✅ 截图 / 默认态 5 条 + 隐藏数提示 ✅ 截图 / 搜索态突破 5 条 ✅ 截图 / 162 测试全绿 |
| ~~C5-2~~ | `[-]` | ~~系统级搜索（Spotlight）直接取码~~ —— **用户 2026-09-17 决策放弃**。调研结论留档（见 PRD §12 备注）：技术上可行（App Intents + App Shortcuts），但收益是「少点两下」而成本是新增意图/实体/索引面与分发依赖，与「缩小权限面与攻击面」的既定方向不一致 | 不适用 |

---

## 阶段 6 · 界面与偏好调整（2026-09-17 用户反馈）

| 卡 | 状态 | 内容 | 完成判据 |
|---|---|---|---|
| C6-1 | `[x]` | **窗口宽度 400 → 360**（用户 2026-09-17 拍板）—— `WindowMetrics`（DEBUG `--width` 运行时覆盖，260–420，非法值回落）+ 弹窗宽度自适应（`sheetWidth`）+ **导入页拖放区改宽度自适应**（原固定 360 宽，在 360 窗口下内容区仅 320 会溢出）+ 5 档对比图（`build/width-preview.png`） | 逐屏复核 360 下无溢出/截断异常 ✅（列表 / 导入图片 / 手动输入 / 导出弹窗）；PRD G-01 与 TECH_PLAN D8 已同步；170 测试全绿 |
| C6-3 | `[x]` | **列表拖动排序（DR-01 / R12，PRD v1.11）** —— `ReorderLogic`（方向分流 / 落点 / 数组重排，纯逻辑）+ `ListReorderModel`（拖动会话：让位位移、落点、是否提交）+ `Account.sortIndex` 持久化 + `SecretStoring.updateMetadata`（只改元数据不碰密钥）；手势与左滑**共用同一个 DragGesture** 按方向分流（竖直 24pt / 水平 8pt）；拖动行「抬起」+ 其余行让位 + 落点指示线；搜索过滤时禁用 | 27 个新单测（方向分流 + 落点/插入位 + 重排 + 会话让位 + 滞回防抖 + store 落盘与重载）；**跨实例 load 顺序保持 ✅**；截图验证拖动中视觉 ✅；`--debug-drag-script` 取证「落点单调、零回翻」✅；198 测试全绿 |
| C6-2 | `[x]` | **隐藏 Dock 图标设置** —— `AppSettings`（UserDefaults 持久化，键 `hideDockIcon`，非敏感信息）+ `Settings` scene（⌘, / 主窗口「⋯」→「偏好设置…」）+ 开关即时生效（`setActivationPolicy(.accessory / .regular)`，macOS 不支持运行时改 `LSUIElement`，这是官方等价手段）；4 个单测（默认值 / 持久化 / 策略映射 / 键名） | 实测：关闭时 `background only = false` 且 Dock 有挂锁图标；开启时 `background only = true`、Dock 无图标、菜单栏图标仍在 ✅ 截图；截图验证设置界面 ✅ |

**C5-1 附带修复（重要）**：加状态栏后 App **启动即崩**（`AG::precondition_failure` → SIGABRT）。根因：`AccountStore` 在**视图 body 求值期间**写 `codeCache` / `secretCache` / `secretUnavailable` / `lastRetryTime` 这四个观察属性 —— 单 scene 时侥幸不崩，多 scene（主窗口 + 状态栏面板 + 预览窗各自一个 graph）后 Observation 在更新事务中途触发失效即 abort。修复：四个缓存全部标 `@ObservationIgnored`（刷新语义本来就由 `CodePulse` / `RingClock` 驱动，不依赖缓存的观察通知）。**教训：`@Observable` 类型里凡是「渲染路径上会被写」的缓存，必须 `@ObservationIgnored`。**

---

## 阶段 4 · P1 迭代（PRD v1.3 收敛后范围）

### C4-10 · 导出范围选择（PRD v1.6，2026-09-16 用户反馈）

| 项 | 实现 | 状态 |
|---|---|---|
| 范围选择器 | 新增 `ExportScopePicker`（分段「全部账户（N）/ **选择账户**」+ **多选清单**：复选框 / 全选 / 清空 / 已选计数 / 未选时危险色提示），**两个导出弹窗共用** | ✅ 截图验证 |
| 加密备份导出 | `exportBackup(password:onlyIDs:)` 按所选集合过滤（一次导出覆盖多个账户）；文件名：单个 = `2way-<账户名>-<时间>`、多个 = `2way-backup-<N>keys-<时间>`（安全化 + 限长 32） | ✅ 单测 |
| GA 迁移码导出 | `exportGAMigration(onlyIDs:)` 同集合过滤（一张二维码可含多个所选账户） | ✅ 单测（编码→解析） |
| toast 回执 | 单账户：已导出「名称」/ 已导出「名称」的迁移码；多账户 / 全部：已导出 N 个账户 | ✅ |
| 校验 | 无账户 / **未选任何账户** / 口令过短 / 两次不一致 均有就地报错 | ✅ |
| 版本历史 | v1.6 单选 → **v1.7 多选**（用户反馈：选 2 个账户需导出 2 次不合理） | ✅ |

### C4-8 · 复制无提示修复（2026-09-16 用户反馈）

| 项 | 根因 | 修复 |
|---|---|---|
| 单击复制成功但**无 toast** | `ToastCenter` 是 `ObservableObject` + `@Published`，而持有它的 `RootView` 用 `@State` 保存 —— **`@State` 不会订阅 `ObservableObject` 的变化**，状态变了界面不刷新（此前所有截图里从未出现 toast，即此因） | `ToastCenter` 改为 `@Observable`（与项目其余状态层一致）；DEBUG 新增 `--debug-toast` 便于回归验证 | ✅ 截图验证「已复制」渲染 |

### C4-7 · 列表交互与样式调整（PRD v1.5，2026-09-16 用户反馈）

| # | 变更 | 实现 | 状态 |
|---|---|---|---|
| 1 | 窗口标题 | 「验证器」→「**TwoWay 密钥生成器**」 | ✅ 截图验证 |
| 2 | 复制入口 | 移除行末悬停复制图标（原 R11）；**左键单击整行即复制**，底部 toast 文案简化为「已复制」；行底色闪 650ms 与悬停底色保留 | ✅ 截图验证（逻辑未变，仅入口收敛） |
| 3 | 行标题样式 | 单行 **「发行方：账户名」**（发行方 15pt 次要色 + 全角冒号 + 账户名 15pt SemiBold 主色；发行方缺失/与名称相同时只显示名称） | ✅ 截图验证 |

### C4-6 · D10 移除系统窗口 chrome（2026-09-16 用户决策）

| 项 | 内容 | 状态 |
|---|---|---|
| 三个系统按钮 | `WindowConfigurator` 隐藏 close / miniaturize / zoom（`isHidden + alphaValue 0 + isEnabled false` 三重保险），`titleVisibility = .hidden` | ✅ 截图验证（左上角干净） |
| 退出入口 | 「⋯」菜单新增「退出 2way」（另保留 Cmd+W / Cmd+Q） | ✅ 截图验证（菜单可见） |
| 窗口拖动 | 新增 `WindowDragArea`（NSView `performDrag(with:)`）挂在自绘标题栏背景层，不阻挡按钮/菜单点击 | 待手工验证（拖拽无法程序化测试） |
| 布局调整 | 标题栏不再为交通灯预留 52pt；废弃 `trafficLight*` token | ✅ |
| 保持不变 | 系统窗口圆角、32pt 隐形标题栏（G-01 的 732 来源） | ✅ 窗口实测 400×732 |

### C4-5 · 用户实测反馈的 5 个 UI/交互问题（2026-09-16）

| # | 问题 | 根因与修复 | 状态 |
|---|---|---|---|
| 1 | 详情页无法退出 | 标题栏无前导操作 → `WindowTitlebar` 增加 leading 插槽 + `TitlebarBackButton`；详情页 Esc 也返回（弹窗打开时 Esc 先关弹窗） | ✅ 截图验证 |
| 2 | 详情页参数卡覆盖倒计时环 | **子 layer 未设 frame（零尺寸）→ anchorPoint=(0,0)，而「起点 12 点钟」的 -90° 旋转绕 anchorPoint 进行 → 整圆被平移出视图**（表现为直径数百 pt 的巨圆压住参数卡）；修复：`updateLayerGeometry()` 把两个 shape layer 的 frame 设为视图 bounds，并改为按 `ringSize` 精确算径（不再依赖 bounds 更新时机），`configure(size:)` 显式传尺寸 + `intrinsicContentSize` | ✅ 截图验证 |
| 3 | 列表环垂直位置偏（列底） | 与 #2 同源（巨圆位移）；修复后环居中于行 | ✅ 截图验证 |
| 4 | 列表不显示发行方 | 行内增加发行方小字（11/t3），三行布局：发行方 / 账户名 / 验证码（发行方=名称时不重复）；仍在 76pt 行高内 | ✅ 截图验证 |
| 5 | 导出缺 GA 兼容方式 | 新增 `OTPMigration.migrationURI(entries:)` 编码器（反向 protobuf）+ `QRCodeImage`（CIQRCodeGenerator → PNG）+「导出 GA 迁移码（PNG）」菜单项与弹窗（**明示未加密风险**，提示用完即删）；单测含「编码→解析往返」与「生成 PNG → Vision 扫回」端到端 | ✅ 150 测试全绿 |


| 卡 | 状态 | 内容 | 完成判据 |
|---|---|---|---|
| C4-1 | `[x]` | **剪贴板自动清除（S4，v1.3 由 P1 提前）** —— `ClipboardGuard`：记录写入时 `changeCount`，仅当仍归本应用所有才清除（**绝不误清用户后来复制的内容**）；默认 30s；`Pasteboard` 协议抽象出可注入实现供单测（7 个单测） | 到期清除 ✅ / 他方写入不误清 ✅ / 开关与失败路径 ✅ |
| C4-2 | `[x]` | **编辑账户**（名称 / 发行方 / 密钥 / 高级参数）—— `AccountStore.update`（E3/E4 重校验 + 清取码缓存）+ `ManualEntryModel.editingAccountID` + 编辑模式复用表单（隐藏分段、按钮「保存」）；**入口：左滑操作块「编辑」**（v1.8，原为详情页标题栏铅笔）；3 单测 | 预填现值 ✅ 截图验证 / 不新增账户、id 不变 ✅ / 换密钥后取码变化 ✅ |
| C4-3 | `[x]` | **导入导出/备份** —— `BackupArchive`（自描述格式 `2WBA`+版本+PBKDF2 参数+盐+AES-GCM；**口令派生 PBKDF2-HMAC-SHA256 210k 轮**，不依赖 `master.key`）+ `AccountStore.backupEntries()/importBackup()`（同 id 幂等跳过）+ 列表标题栏「更多」菜单（PRD §7.1）+ 导出/导入弹窗（口令二次确认 / 就地报错）；9 个单测（往返/头格式/随机性/错口令/篡改/坏文件/弱口令/**导入幂等**/**灾难恢复端到端**） | **导出 → 全新空存储 → 导入 → 取码一致 ✅**（单测）|
| — | `[x]` | ~~触控板双指横滑~~ | **不做（PRD v1.3，用户决策）** |
| — | `[x]` | ~~全局快捷键~~ | **不做（PRD v1.3，用户决策）** |
| — | `[x]` | GA 迁移码 `otpauth-migration://` 导入（原属 P1「从其他验证器迁移」） | 已随 C2-6b 交付 ✅ |

---

## 阶段 3 · 验收与交付

| 卡 | 状态 | 内容 | 完成判据 |
|---|---|---|---|
| C3-1 | `[x]` | 逐像素比对（对照 `index.html`）—— 处置结论：**接受等价替代清单**（RK3/RK5/RK8/D8 已闭环）：系统圆角 ≈13 vs 12、交通灯 13pt vs 12px、SF Mono vs JetBrains Mono、PingFang SC vs Noto Sans SC、窗口 732（32pt 归列表区）。U12：Demo 第 02 屏仍是 v1.0 摄像头形态，逐像素比对仅覆盖 01/03/04/05 屏语义 | 差异项已列出并全部有决策 ✅ |
| C3-2b | `[x]` | **性能复核（C4-9）**：区分「窗口可见 / 被遮挡」后重测 —— **可见 ≈ 1–2.6%（4 环），被遮挡 ≈ 0.2%**（此前 0.4% 实为遮挡节流值）。对策：新增 `CodePulse`（换码脉冲）替代列表的 1Hz 刷新（列表不显示秒数，只需在换码时刷新），并把环的 layer 几何改为「无变化不重设」。残余成本主要为**持续动画的每帧合成**，属 T3「连续平滑」的固有代价；P-1「<1%」仅在遮挡态成立，已在 C3-2b 如实记录 |
| C3-2 | `[x]` | 性能实测（M1 Pro，Release，5 环稳态）—— **初测 36% → 优化后 0.4-0.7%**。根因：SwiftUI `TimelineView(.animation)` 30Hz 全列表失效 + AppKit 全窗口 `layoutIfNeeded`（sample 实测主线程 2/3 在布局引擎）。修复：环改 `CAShapeLayer` + `RingClock` 30Hz 直驱 + 周期级 `CABasicAnimation`（GPU 插值）；码文本秒对齐 1Hz。RSS ≈ 92MB / 4 线程 | CPU < 1% ✅ |
| C3-3 | `[x]` | 安全自查（D9 修订版）—— wallet.bin 密文无明文特征 ✅ / master.key+wallet.bin 0600、目录 0700（含单测）✅ / Sources 零 print·os_log·Logger·NSLog ✅ / 进程参数无密钥 ✅ / Account.debugDescription 脱敏（单测）✅ | ✅（§4.2 清单按 D9 修订后全勾） |
| C3-4 | `[x]` | Release：archive → 全组件重签 → DR 校验 → UDZO → 校验 → 挂载实测 —— `dist/2way-0.1.0.dmg`（≈1.26MB，含 App 图标），DR = `identifier "com.kimi.2way" and certificate root H"88f7f892…"`，挂载后签名校验通过 | `dist/2way-*.dmg` 可挂载运行 ✅ |

---

## 阻塞项（见 TECH_PLAN §7）

| # | 事项 | 状态 |
|---|---|---|
| U1 | 是否沙盒化 | **已定：先不沙盒** |
| U10 | ~~密钥存储~~ → **D9：弃用 Keychain，改 EncryptedStore 加密文件**（2026-09-16 用户决策）——本机 login 钥匙串条目 ACL 不自动信任创建者，每条密钥首次读取都弹一次授权框（逐条弹、实测 `open` / 直接执行、同构建均复现），体验不可接受。`wallet.bin`（AES-256-GCM，0600）+ `master.key`（随机 32B，0600，目录 0700）。**S1 显式降级已获用户确认**：防磁盘扫描/他应用读取，不防同用户本地攻击者。遗留：钥匙串里 10 条孤儿条目待用户同意后用 `security delete-generic-password` 清理 |
| U2 | Bundle ID 与应用名 | **暂定 `com.kimi.2way` / 2way** —— C1-1 存储首个密钥前可改 |
| U3 | G-04 原型导航处理 | 假定：原生不需要，仅 `#if DEBUG` 保留切屏入口 |
| U4 | G-05 缩放策略映射 | 假定：固定尺寸窗口 + 内部不响应式重排 |
| U5 | 工程纪律 | **已定：沿用 TunnelManager 那套** |
| U6 | git 仓库 | **已完成** |
| U9 | 证书创建方式 | **已完成**：脚本 `scripts/create-signing-cert.sh` 已创建并接入构建（C0-1b 校验 DR 通过） |
| U13 | ~~D9 逃生通道缺口~~ | **已闭环（C4-3）**：加密备份文件用**用户口令**派生密钥（PBKDF2-HMAC-SHA256，210k 轮），不依赖 `master.key` —— 主密钥丢失时仍可从备份恢复 |
| U12 | `index.html` 与 Ardot 设计稿的第 02 屏仍是 v1.0 摄像头形态（取景框/取景括号/扫描线），需按 PRD §7.4 改版为「导入图片」拖放区。**另：Demo 画布仍是 400×700（`index.html` 第 33 行），App 已收窄到 360×732，作视觉基准时须按宽度差换算**（列表列宽/截断位置会不同） | **C3-1 逐像素比对、C2-6** |

---

## 变更记录

| 日期 | 变更 |
|---|---|
| 2026-09-17 | **发布 v1.0（首个正式版本）**：`MARKETING_VERSION` 0.1.0 → **1.0**（唯一版本源在 `project.yml`，打包脚本自动读取，产物名随之变为 `dist/2way-1.0.dmg`；App 内的版本显示走 `Bundle` 动态读取，无需改码）。发布前门禁：`xcodegen generate` 后 Info.plist 注入 1.0 ✅ → 198 测试全绿 ✅ → 7 步打包流水线（重签 / DR 锚定 / UDZO / checksum VALID / 挂载实测）✅ → **独立复核 DMG 内 App 版本 = 1.0、签名 identifier = com.kimi.2way** ✅。旧产物 `2way-0.1.0.dmg` 已清理（dist 不入库） |
| 2026-09-17 | **C6-3c 拖动抖动真正根因（PRD v1.13，用户录屏反馈）**：先解析用户录屏（AVFoundation 抽帧 + 逐帧差分）确认抖动是**局部**的（仅拖动行所在两行带反复变化，非整列滚动），幅度 20–35px、约 10–20Hz。再用 CGEvent **合成真实鼠标拖动复现**（注意：脚本化注入模型不经过手势层，因此复现不出来 —— 这是上一次误判的原因）。从手势上报值定位根因：`startY` 恒定而 `locY` 在两值间跳（11↔35）→ 手势用默认 `.local` 坐标系，**而该坐标系原点就是行自己被 offset 后的位置** → 自指反馈回路 → 每帧锯齿（`dy`=-26,-2,-28,-4,-28…）。修法：位移测量改到**稳定的命名坐标系** `AccountListCoordinateSpace`（挂滚动容器；左滑同受益）。取证：同一合成拖动下 `dy` 单调（-25,-27,-29,-31,-34,-37,-42,-48,-54…）、**零回退**（83~111 样本）、落定与持久化正确、左滑回归正常。新增调试项 `--debug-drag-trace`（逐事件 start/location）与 `--debug-drag-script`（脚本化拖动自报落点/tick） |\n| 2026-09-17 | **C6-3b 拖动排序加固（当时误判为抖动根因，PRD v1.12）**：现象「按住拖动时被选中的那一条严重抖动」。根因三条回路叠加（跟手位移与让位动画共用同一 offset + 同一 `.animation(value: insertionIndex)`；`round` 跨格判定在边界处来回翻转并反复重触发动画；`offsetY` 在列表容器读取导致整表每像素重算）。修法：拖动行位移**绝不动画**且 offsetY 只在行内部读（观察范围收敛）、落点加 **±4pt 滞回**、让位动画只包住让位偏移。取证：新增 `--debug-drag-script`（1.6s 平滑下拖 + ±3pt 边界抖动）自报 `transitions=[0>1,1>2,2>3] backFlips=0`，稳态 tick 14.4ms（尖峰 65ms 出现在启动 192ms 处，与拖动无关）；新增 4 个滞回单测；198 测试全绿 |\n| 2026-09-17 | **C6-3 列表拖动排序（PRD v1.11，用户新需求）**：按住某条 key 竖直拖动即可放到任意一条前/后。① **手势分流**：与左滑共用同一个 `DragGesture`（两个独立手势会互相截胡），竖直 ≥ 24pt 且大于水平位移 → 排序，水平 > 8pt → 左滑；macOS 鼠标拖动不滚动 `NSScrollView`，故不设长按门槛。② **持久化**：顺序落在 `Account.sortIndex`（`SecretStoring.updateMetadata` 只改元数据、不碰密钥，S1）；老钱包无 sortIndex 时沿用添加时间倒序（**升级不变序**）；新增账户仍置顶、导入备份追加末尾。③ **落点纯算术推导**（行高 76 + 间距 2 = 78），不读几何。④ **搜索过滤时禁用**排序（过滤视图里「插到哪条前后」对应的全量位置不明确，宁可禁用也不猜）。⑤ 过程记录：截图发现「拖满一整行才跨过第一条」的**首格死区**（插入位算法把落点与缝隙混为一谈）→ 拆成 `landingIndex`（落点槽位）+ `insertionIndex`（移除前数组的缝隙），指示线也随之改画在落点槽位上沿；另发现**未真正移动过的会话也会被手势结束事件当作落定提交**（会悄悄改掉用户顺序）→ 加防线「位移未达激活阈值不提交」。⑥ 调试项 `--debug-reorder-drag`（注入拖动中状态，供截图核对视觉）。测试 170 → 195 全绿 |
| 2026-09-17 | **C4-16 ⌘W 无法关闭窗口（用户实测反馈）**：D10 移除系统 chrome 时把关闭按钮设为不可见，**AppKit 会把不可见的标准按钮同时置为 disabled**（探针实测：`isHidden=true` 与 `alphaValue=0` 两种做法都会，且显式 `isEnabled = true` 也压不住 —— 读数恒为 `closeBtnHidden=false/false closeBtnEnabled=false`），而系统 File ▸ Close（⌘W）的 action 是 **`NSWindow.performClose(_:)` = 「模拟点击关闭按钮」**，按钮 disabled 时它是**空操作** → ⌘W 毫无反应。修复：新增 `CloseWindowMenu`（NSObject 单例，持有强引用因为菜单 target 是弱引用），启动时把主菜单里「⌘W 且 action == performClose:」的项**接管为 `close()`**（不查按钮状态），幂等安装（SwiftUI 可能重建菜单，onAppear + 800ms 各装一次）；「⋯」菜单补「关闭窗口」图形入口。验证（探针走**真实菜单项动作**，与按 ⌘W 同一链路）：`patched=true` → 调用后 `isVisible=false`、窗口列表为空、**进程存活**（只剩菜单栏）→ `open` 唤回窗口成功。调试项 `--debug-close-window` 保留 |
| 2026-09-17 | **诊断方法论要点（写进文档避免重踩）**：① 「未激活窗口的标准按钮会被 AppKit 灰掉」是干扰项 —— 一开始探针读到的 `enabled=false` 有两种解释（我们禁用了 / 系统灰化了），必须先 `NSApp.activate()` 再量；② 判定「按钮是否只是隐藏」必须把 `nil / isHidden / alphaValue / isEnabled` 四个量**分开打印**（`?? false` 会把 nil 与 false 混为一谈，误导了一轮）；③ `performClose` 与 `close` 语义不同 —— 前者是「模拟点击」、会被 UI 状态拦住，后者直接关闭 |
| 2026-09-17 | **代码推送 GitHub 远端 + README 交付**：远端 `git@github.com:kimicao1010/2way.git`（`origin`），SSH 用本机专用 key（路径不入库，推送时经 `GIT_SSH_COMMAND` 注入）。新增 `README.md`（功能清单 / 安全模型与已知降级 / 安装与构建 / 目录结构 / **DEBUG 调试参数一览** / 文档索引 / 已知限制）+ `docs/`（主界面截图、状态栏面板截图、图标）。入库体检：107 个文件，无 `*.p12` / `*.keychain` / `Secrets.swift` / wallet / master.key / ssh key ✅（`.gitignore` 已排除构建产物、生成物与凭据）。`dist/2way-0.1.0.dmg`（1.3MB）已构建并通过 7 步流水线（DR 锚定自签证书、checksum VALID、挂载实测）；**DMG 按约定不入库**（tag 与 GitHub Release 用户已明确不做） |
| 2026-09-17 | **C6-1 落定：窗口宽度 400 → 360**（用户拍板）。`Token.Metrics.windowWidth = 360`；**连带修掉一处溢出**：导入页拖放区原为固定 360×340，在 360 宽窗口下内容区仅 320pt 会顶出窗口 → 改 `scannerHeight: 340` + 宽度自适应（`maxWidth: .infinity`）；三个弹窗宽度此前已改 `sheetWidth` 自适应。逐屏复核（按窗口 ID 截图）：列表 / 导入图片（拖放区虚线框完整、引导卡换行正常）/ 手动输入（提示文案单行不换行、高级选项与预览卡正常）/ 导出弹窗（336 宽自适应，多项清单与口令字段不挤）。文档同步：PRD G-01 → **360×732**（§11 与 v1.10 修订记录）、TECH_PLAN D8 与架构图/定位描述 |
| 2026-09-17 | **C6-2 隐藏 Dock 图标设置落地**：新增 `AppSettings`（UserDefaults 键 `hideDockIcon`）+ `SettingsView`（SwiftUI `Settings` scene → ⌘, 与主窗口「⋯」菜单入口）+ `AppBootstrap` 启动时应用激活策略。**实现要点：macOS 无法运行时改 Info.plist 的 `LSUIElement`，等价手段是 `NSApp.setActivationPolicy(.accessory / .regular)`**，切换即时生效无需重启。实测两种状态（`background only` true/false、Dock 图标有无、菜单栏图标仍在）+ 设置界面截图；测试 162 → 170 全绿 |
| 2026-09-17 | **C6-1 窗口宽度比选（进行中）**：用户反馈 400 太宽。新增 `WindowMetrics`（DEBUG `--width <pt>` 运行时覆盖 + 纯函数解析含 4 个单测：无参/合法/非法（非数字、越界、缺值））+ 三个弹窗宽度改 `WindowMetrics.sheetWidth(...)` 自适应（否则 380 宽的 sheet 在窄窗口下会顶出去）；按 20 一档出 5 档实测对比图（400/380/360/340/320，同数据同状态，裁掉阴影后横向拼接），320 下布局未破（行标题按需截断、码与环位置正常）。**待用户拍板后落定 `Token.Metrics.windowWidth`** |
| 2026-09-17 | **C5-2 放弃（用户决策）**：系统级搜索（Spotlight / Siri / 快捷指令）直接取码的调研结论保留在 PRD §12 备注（可行路径 = App Intents + App Shortcuts；红线 = 密钥与验证码绝不进任何明文索引），但用户决定不做 —— 收益（少点两下）与新增的意图/索引面、分发依赖不成比例 |
| 2026-09-17 | **功能验收通过（用户确认）**：用户 2026-09-17「当前版本，功能测试目前没有问题了」→ **C2-2 / C2-5 / C2-6 由 `[~]` 转 `[x]`，RK1（R6 拖拽补发 click）关闭**；同步清理陈旧条目（R11 悬停复制图标已于 v1.5 移除、C2-4 不再含详情环、C3-4 的 DMG 体积更新为含图标后的 ≈1.26MB、C0-3「截图存档」明确为「不入库、脚本可复跑」）；RK3/RK4/RK5 一并关闭 |
| 2026-09-17 | **C5-1 状态栏常驻 + 下拉快速取码（P2 提前交付，PRD v1.9）**：`TwoWayApp` 挂 `MenuBarExtra`（`.menuBarExtraStyle(.window)` —— 原生 `.menu` 承载不了搜索框）；新增 `MenuBarView`：搜索框打开即聚焦、**默认最多列 5 条**（`MenuBarSelection` 纯逻辑 + 7 单测）、超出时提示「还有 N 个账户 —— 输入关键词搜索」、**输入关键词后不再受 5 条限制**、点行即复制（走 `ClipboardGuard`，S4 30s 自动清除）、行内「已复制/复制失败」反馈 + 倒计环、回车复制首条、底部「打开主窗口 / N 个账户 / 退出」；状态栏图标用用户提供的 `status-bar/` 素材（16/32 → Asset Catalog `StatusBarIcon`，template 渲染，深浅菜单栏自适应）；`AppBootstrap` 幂等引导 + `store` 所有权上移到 `TwoWayApp`（主窗口与状态栏共用同一数据源）；调试项 `--debug-menubar`（面板预览窗，菜单栏面板无法按窗口 ID 截取）+ `--debug-menubar-query`（搜索态截图）；测试 155 → 162 全绿 |
| 2026-09-17 | **C4-15 多 scene 崩溃修复（加状态栏后暴露的隐患）**：现象「启动即 SIGABRT」；崩溃栈 `AG::precondition_failure` ← `AccountStore.codeCache.modify` ← `formattedCode` ← `AccountRows.body`。根因：`AccountStore` 在**视图 body 求值期间写观察属性**（取码缓存 / 密钥缓存 / 失败集合 / 重试时间），单 scene 时侥幸不崩，多 scene 后 Observation 在更新事务中途失效 → abort。修复：四个缓存全部 `@ObservationIgnored`（刷新由 `CodePulse`/`RingClock` 驱动，不依赖观察通知）；顺带把 `Account` 的「发行方：账户名」口径抽成 `issuerQualifiedName` 供列表 / 状态栏 / 导出选择器共用 |
| 2026-09-16 | 项目立项；阶段 0 启动；PRD v1.0 |
| 2026-09-16 | **C2-1 列表页落地**：\`AccountStore\`（加载/搜索/计数/置顶/取码缓存）+ \`AccountListView\`（搜索/行/悬停/点按复制/Toast）；\`SecretStoring\` 协议抽象出可注入的存储层；窗口四角圆角由 \`clipShape\` 兜底（SwiftUI 恒定给窗口加 32pt 隐形标题栏，底边落在窗口中部、系统不在那里画圆角）
| 2026-09-16 | **PRD v1.1：移除摄像头扫码，添加账户改为仅「图片导入 + 手动输入」**。页面 02 由「扫描二维码」改为「导入图片」；取景框/取景括号/扫描线动画废弃；不再申请摄像头权限。影响：C2-6 重定义、RK2 关闭并新增 RK2b、D1 依据更换（结论不变）、D7 新增 |
| 2026-09-16 | **C2-2 左滑实现落地**：\`SwipeRowState\`（R2/R3/R4/R6 纯逻辑 + 8 个单测）+ \`SwipeableAccountRow\`（操作块/互斥/复制闪烁）；R1 闪烁 650ms 补齐；R7/R8 回调接至 RootView（切屏分别等 C2-7/C2-8）；测试 89 → 97 全绿。**R1–R11 手工回归清单待执行** |
| 2026-09-16 | **窗口 400×732 修复（G-01）**：根视图由固定 732 改为 minHeight 700 可伸缩 —— 原实现窗口实测 764（内容 732 + 32 隐形标题栏），底部 32pt 透明透壁纸；修复后窗口 732、32pt 归列表区，实测无透明带 |
| 2026-09-16 | **C2-5 手动输入页落地**：\`AppRouter\`（list ↔ addAccount）+ \`AddAccountView\`（分段外壳，导入图片为 C2-6 视觉占位）+ \`ManualEntryView\`（名称/密钥字段 + E4 实时报错 + 高级选项折叠 Picker + 30Hz 实时预览卡）+ \`ManualEntryModel\`（E3/E4/提交，9 单测）；ToastCenter 上移 RootView 共享（添加成功 toast 在列表页显示）；DEBUG 支持 \`--debug-add\` 切屏（U3）；测试 97 → 106 全绿 |
| 2026-09-16 | **C2-6 导入图片页落地**：\`QRImageDecoder\`（Vision 唯一路径，symbologies=.qr，按包围盒面积降序 = E11 取最大者）+ \`QRImport.resolve\`（noQRCode / account / notOTPAuth / invalidOTPAuth 四态）+ \`ImportImageView\`（fileURL/图片双通道拖放 + 悬停态描边转强调色 + 底色提亮 + 缩略图保留 + NSOpenPanel 仅图片类型）+ \`ManualEntryModel\` 增加 issuer 字段与 \`prefill(from:)\`；手动表单新增「发行方（可选）」字段（预填发行方需要）；单测用 CIQRCodeGenerator 生成真实二维码 + 双码合成图覆盖往返/E9/E10/E11；Info.plist 无 NSCameraUsageDescription 实测确认；测试 106 → 114 全绿 |
| 2026-09-16 | **GA 导出迁移码支持（C2-6b，用户实测反馈驱动）**：用户拿 GA「导出二维码」（\`otpauth-migration://offline?data=...\`）被 E10 误拦。新增 \`OTPMigration\` 手写 protobuf wire 解码（secret/name/issuer/algorithm/digits/type，HOTP 跳过并计数知情）；\`QRImport\` 增加 migrated 路径 —— **多账户批量直接入库 + toast「已导入 N 个账户」（含 HOTP 跳过提示），单账户仍走预填确认流**；PRD P1「从其他验证器迁移」的 GA 导出部分提前落地；用用户真实截图端到端验证（5 个 TOTP 全部识别）；测试 114 → 121 全绿 |
| 2026-09-16 | **C2-7 详情页 + C2-8 删除确认弹窗实现落地**：\`AccountDetailView\`（身份区渐变头像 / 168 大环 heroTrack / 参数卡 / 复制+删除操作区 / 标题栏编辑占位）+ FR-06 删除确认弹窗（遮罩 0.65 / 304 宽 / 文案明示不可恢复 / Esc=取消）；R7/R8 接通（切详情 + 260ms 自动弹窗）；测试 121 全绿 |
| 2026-09-16 | **D9：弃用 Keychain → EncryptedStore 加密文件（用户决策）**：本机 login 钥匙串条目 ACL 不信任创建者，同构建读取也逐条弹授权框（实测 \`open\`/直接执行均复现），且 \`load()\` 单条失败曾导致全列表消失（已改为单条容错）。新存储：\`wallet.bin\`（AES-256-GCM 认证加密 + 原子替换 + 0600）+ \`master.key\`（随机 32B + 0600，目录 0700）；6 个单测覆盖往返/跨实例持久化/CRUD/篡改检测/主密钥丢失/文件权限；实测零弹窗 + 跨启动持久化 ✅；测试 121 → 127 全绿。**S1 降级已获用户确认**（见 U10） |
| 2026-09-16 | **C3-2 性能修复（P-1 达成）**：初测 5 环稳态 CPU 36%（SwiftUI 30Hz TimelineView 全列表失效 + AppKit 全窗口布局 churn，sample 定位）。重构：环改 \`RingLayerView\`（CAShapeLayer ×2）+ \`RingClock\` 单一 30Hz 时钟直驱 layer；进度用 CABasicAnimation 按剩余时长 GPU 插值，tick 仅在换周期/告警切换时写 layer；码文本改秒对齐 1Hz \`TimelineView(.periodic)\`。**36% → 0.4-0.7%**，RSS ≈ 92MB，4 线程 |
| 2026-09-16 | **阶段 3 验收交付完成**：C3-1 差异清单全部有决策（等价替代接受）；C3-3 安全自查按 D9 修订全勾（wallet 密文/0600 权限含单测/零日志/进程参数干净）；C3-4 \`dist/2way-0.1.0.dmg\` 打包 + 挂载实测通过，DR 锚定自签证书 |
| 2026-09-16 | **T5/T6 修复：码文本刷新链路（用户实测反馈）**。现象：环在动、码文本冻结。定位过程：① 单元测试证明 store 真时钟与取码缓存正常（新增 \`AccountStoreRealtimeClockTests\`，period=1s 跨周期必变）；② \`TimelineView(.periodic)\` 与 \`onReceive\`+通知两条刷新路径在真机未触发重算。方案：新增 \`SecondPulse\`（@Observable 全局秒脉冲，由 RingClock 整秒推进），视图读取脉冲建立原生观察依赖 → 整秒重算码文本；环动画 \`beginTime\` 锚定绝对周期边界 → **换码与环重置同刻**。验证：35 秒跨周期截图，4 个码全部刷新 ✅。**方法论教训：验证码刷新必须跨周期（>30s）比对，7 秒间隔的对比结论无效** |
| 2026-09-16 | **PRD v1.3 + P1 范围收敛（用户决策）**：触控板双指横滑、全局快捷键**不做**（代价/风险与收益不成比例，且全局快捷键的辅助功能授权与 v1.1「缩小权限面」相悖）；P1 收敛为「编辑账户 / 导入导出备份 / 剪贴板自动清除」；S1 条款按 D9 重写为「加密落盘」，S4 提前到本期 |
| 2026-09-16 | **C4-10b 导出范围改多选（PRD v1.7，用户反馈）**：单选 → 多选复选框清单（全选/清空/已选计数/未选禁用），`exportBackup(password:onlyIDs:)` 与 `exportGAMigration(onlyIDs:)` 按集合过滤 —— 一条备份文件 / 一张迁移码二维码可覆盖任意多个所选账户；多账户文件名 `2way-backup-<N>keys-<时间>.2wbackup`；测试 154 → 155 全绿（新增「多选一次导出」用例） |
| 2026-09-16 | **C4-10 导出范围选择（PRD v1.6）**：两条导出路径（加密备份 / GA 迁移码）均支持「全部账户 / 指定账户」；新增共用 `ExportScopePicker`；单账户导出文件名带账户名；4 个单测（范围解析 / 标签 / 过滤 / 单账户往返）；测试 150 → 154 全绿 |
| 2026-09-16 | **C4-9 刷新频率优化 + 性能数据复核**：① 新增 `CodePulse`（环换码时触发）替代列表的 `SecondPulse` 1Hz 刷新 —— 列表只显示码不显示秒数，只需在换码时重算；② `RingLayerView.updateLayerGeometry()` 加「无变化不重设」守卫，避免每次 SwiftUI 刷新都重设 layer path/frame；③ 复核性能并如实记录：**可见 1–2.6% / 遮挡 0.2%**（此前 0.4% 是遮挡态），残余成本为环持续动画的每帧合成。换码刷新经 34 秒跨周期截图验证仍正确 |
| 2026-09-16 | **C4-8 复制无提示修复**：`ToastCenter` 由 `ObservableObject + @Published` 改为 `@Observable` —— 根因是 `@State` 持有 `ObservableObject` 不建立订阅，导致 toast 状态变化不触发重绘（此前从未渲染过 toast）。修复后复制即时弹出「已复制」。应用名/Bundle ID 按用户要求保持不变 |
| 2026-09-16 | **C4-7 列表交互与样式（PRD v1.5）**：标题「TwoWay 密钥生成器」；移除悬停复制图标（复制唯一入口 = 单击整行，toast「已复制」）；行标题改为「发行方：账户名」单行（次要色发行方 + 主色账户名） |
| 2026-09-16 | **D10 移除系统窗口 chrome + C4-5 五项修复**：窗口不再显示关闭/最小化/缩放按钮（`isHidden + alpha 0 + disabled`，标题栏透明、无系统标题文字），「⋯」菜单加「退出 2way」，窗口拖动改由自绘标题栏 `WindowDragArea`（`performDrag`）承担，标题栏回收 52pt 交通灯预留位；PRD → v1.4（G-03 改写）。同轮修复：详情页返回按钮/Esc、环尺寸 bug（shape layer 零 frame 致旋转平移出视图）、列表环归位、行内显示发行方、GA 兼容导出（迁移码 PNG） |
| 2026-09-16 | **C4-5 用户实测 5 项修复（UI/交互）**：① 详情页返回按钮 + Esc（原先完全无退出路径）；② 环尺寸 bug（shape layer 零 frame 导致旋转把圆平移出视图 → 巨圆压住参数卡）；③ 同源修复后列表环回到行中心；④ 列表行显示发行方（三行布局）；⑤ GA 兼容导出（迁移码 PNG，含明文风险提示）。150 测试全绿 |
| 2026-09-16 | **C4-3 导入导出/备份落地（兼 U13 逃生通道闭环）**：`BackupArchive` 自描述格式（magic `2WBA` / 版本 / PBKDF2 轮数与盐 / AES-GCM combined）；口令派生用 **PBKDF2-HMAC-SHA256 + 随机盐 + 210k 轮**（CommonCrypto），加密用 **AES-256-GCM** 认证加密（口令错误与文件篡改都明确失败，不解出脏数据）；`AccountStore.backupEntries()/importBackup()`（同 id 幂等跳过、不覆盖本地改动、按 addedAt 重排）；列表标题栏「更多」菜单（PRD §7.1 的三点图标）+ 导出/导入弹窗（口令二次确认、就地报错）；导出文件 0600；9 个单测含**灾难恢复端到端**（导出 → 全新空存储 → 导入 → 取码一致）；测试 139 → 148 全绿 |
| 2026-09-16 | **C4-2 编辑账户落地**：`AccountStore.update`（名称/发行方/密钥/参数；E3 清洗 + E4 校验；清该账户取码缓存）+ `secretBase32(for:)`（预填用，密钥不出内存）+ `ManualEntryModel` 编辑模式（`editingAccountID` 路由 add/update）+ 表单复用（编辑时隐藏分段控件、主按钮文案「保存」）+ `AppRouter.Screen.editAccount`；详情页铅笔图标从「占位 toast」改为真入口；3 个单测（预填/不新增且 id 不变/换密钥取码变化/空名兜底）；截图验证编辑页；测试 136 → 139 全绿 |
| 2026-09-16 | **C4-1 剪贴板自动清除（S4）落地**：\`ClipboardGuard\`（记录写入时 changeCount，仅当仍归本应用所有才清除，**绝不误清用户后续复制的内容** —— PRD §4.7 关键约束）；默认 30s；\`Pasteboard\` 协议 + \`SystemPasteboard\` 抽象出可注入实现；7 个单测（到期清除 / 他方写入不误清 / 手动触发 / 失败路径 / 开关 / 连续复制重置 / 默认延迟）；列表与详情两处复制路径接入；测试 129 → 136 全绿 |
| 2026-09-17 | **C4-14 App 图标接入（用户提供图标）**：源图为根目录 `2way.iconset/`（10 个尺寸 16→512 含 @2x，蓝底圆角 + 挂锁）。接入方式：拷入 `Sources/Resources/Assets.xcassets/AppIcon.appiconset/`（mac idiom 全尺寸 Contents.json）+ `project.yml` 设 `ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon`、Info.plist 加 `CFBundleIconName: AppIcon`（xcodegen 生成静态 plist，不会像 Xcode 那样由 actool 自动注入该键，必须显式写）。验证：产物 `Contents/Resources/` 出现 `AppIcon.icns` + `Assets.car`；把 App 拷到新路径（绕过 Finder 图标缓存）用 `NSWorkspace.icon(forFile:)` 渲染图标并肉眼比对 —— Debug 与 Release 渲染一致且就是源图（不再是通用空白图标）；Dock 已 `killall Dock` 刷新。另加 `scripts/sync-appicon.sh`（源图 → Asset Catalog 单向同步），避免「改了源图但 App 还是旧图标」的经典坑（actool 只读 Asset Catalog）。备注：目录内另有 `status-bar/`（菜单栏 template 图标，含 SVG/16/32/48/预览图），属 P2「菜单栏常驻」素材，本期未接入 |
| 2026-09-17 | **C4-13 回到主页时所有行闪现「编辑/删除」按钮（用户实测反馈）**：按《滚动条去除方法论》的「闪现类」流程排查 —— ① 先加行级取证探针 `--row-trace <path>`（自报每行 appear / offset 变化 / isOpen 变化 / 切屏时序）+ 自驱切屏 `--debug-flip-screens [--flip-interval]`（免辅助功能权限复现），日志显示**所有行 offset 恒为 0.0、无任何 offset 变化**→ 排除「行被程序化展开」的状态类原因；② 判定为**合成类**：`.opacity` 切屏过渡把透明度逐视图施加到子树，行底 alpha<1 时 ZStack 底层操作块透出；③ 为让 260ms 瞬态可被低采样率命中（纪律 6），新增 `--slow-transition <秒>` 把过渡放大到 3s，并加 `--list-transition-opacity` 保留旧行为做 A/B；④ 修复：**列表屏改 `.transition(.identity)`**（先就位、再让子页淡出），子页仍保留淡入淡出；⑤ 证据：按窗口 ID 连拍（纪律 3/5，全屏截图会误测别的窗口 —— 首轮就踩了一次），旧行为 **34/122 帧命中透出、最大 36671 个偏红像素**（删除按钮红 `#E5484D` 混在行底上），修复后 **0/123 帧、最大 0**；透出帧已目视确认（编辑/删除 按钮叠在全部行上）。测试 155 全绿 |
| 2026-09-17 | **C4-12 滚动条去除（用户实测反馈）**：主窗口列表一直显示垂直滚动条 —— 根因是 `.scrollIndicators(.hidden)`（只「藏起来」，仍**创建** scroller 并**占位 17px**）。按《滚动条去除方法论》执行：① 先审计全仓容器（共 3 个 SwiftUI `ScrollView`：主列表 / 添加-编辑页 / 导出弹窗多选清单，无 `TextEditor`·`List`·`Form`·`Table`、无 `showsIndicators:`）；② **先取证**：新增 DEBUG 探针 `--scroll-probe <path>`（自报视图树里每个 `NSScrollView` 的 `hasVerticalScroller` / `verticalScroller` 是否存在 / 滚动视图宽 vs 裁剪区宽 = 占位差），拿到基线**阳性对照**（`has=true`、scroller 存在、`scrollViewWidth 400 → clipViewWidth 383`、**占位差 17px**）；③ 三处统一 `.never`；④ 复测：主列表 / 添加页 / sheet 内清单全部 `has=false`、`scroller=nil`、**占位差 0**（裁剪区回到 400）；⑤ 像素级复核（窗口 ID 截图，避开多窗口误判与 23px 阴影边距）：修复前同一右边缘竖带里是**可见的灰色滚动条滑块**（滑块长度与 15 账户/视口比例一致 ≈200px），修复后只剩倒计环弧、环右边缘距窗口右 21px（= 列表 8 + 行 12 内边距）—— 即内容回收 17px 且不再左右微移。测试 155 全绿 |
| 2026-09-16 | **C4-11 移除详情页 + 删除就地确认（PRD v1.8，用户实测决策）**：① 删除不再中转详情页 —— 左滑「删除」→ `router.pendingDeleteID` → 新增 \`DeleteConfirmDialog\` **就地覆盖列表**（标题明示账户名 / 文案明示不可恢复 / Esc 与遮罩关闭 / 确认后留在列表 + toast）；② **详情页整体删除**（\`AccountDetailView.swift\` 移除、\`AppRouter.Screen.detail\` 与 \`deleteDialogDelay\` token 清理、\`AccountDetail/\` 目录删除）；③ 左滑操作块「详情｜删除」→「**编辑｜删除**」，编辑页由此获得常驻入口（C4-2 不再依赖详情页）；④ 顺带修复首帧展开态不一致（\`SwipeableAccountRow.onAppear\` 对齐 \`isOpen\`）；⑤ 调试参数 \`--debug-detail*\` 替换为 \`--debug-delete-dialog\`，新增 \`--debug-open-row\`；155 测试全绿；截图验证操作块与就地弹窗 |

---

## 风险登记

| # | 风险 | 等级 | 应对 |
|---|---|---|---|
| RK1 | ~~左滑 R6「拖拽后补发的 click 被吞掉」在 SwiftUI 下可能偶发失效~~ | **已关闭** | 双保险（DragGesture minimumDistance + 0.15s 抑制窗口）+ 8 单测；**用户 2026-09-17 手工回归通过**（未出现误复制），`NSPanGestureRecognizer` 备选不再需要 |
| RK2 | ~~`AVCaptureMetadataOutput` 运行时对 `.qr` 的支持依赖设备~~ | **已关闭** | v1.1 移除摄像头，不适用 |
| RK2b | Vision 成为**唯一**解码路径，无兜底；对低质量 / 畸变 / 缩放图片的识别率未知 | 中 | C2-6 用真实截图样本集实测（手机截图、裁剪、含透视畸变）；必要时加 `CIFilter` 预处理 |
| RK3 | ~~系统窗口圆角与 PRD 12px 存在差值~~ | **已关闭** | C0-3 实测 ≈12~13px（差 ≤1px，肉眼不可辨），按等价替代接受 |
| RK4 | ~~`SecItemCopyMatching` 批量返回行为与预期不符~~ | **已关闭** | 结论已被 D9 取代（弃用 Keychain，改加密文件）；C1-1 的实测结论仍保留在 TECH_PLAN §4.2 供参考 |
| RK5 | ~~等价字体与设计稿有字距/字重差异~~ | **已关闭** | C3-1 差异清单已列出并决策（PingFang SC / SF Mono 等价替代） |
| RK6 | E5 系统时间不准导致验证码偏差 | 低 | P0 仅提示；P1 做偏移显示 |
