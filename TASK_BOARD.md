# 2way 任务板

> 卡粒度与验收判据以 `TECH_PLAN.md` §6 为准。**每卡必须完成：构建 + 单测 + Git 提交**，才推进下一卡。
> 新增文件后执行 `xcodegen generate` 收录。
>
> 需求版本：**PRD v1.3**（2026-09-16：v1.1 移除摄像头扫码（D7）；v1.2 窗口 400×732（D8）；v1.3 裁剪 P1 —— 触控板双指横滑 / 全局快捷键不做，S1 按 D9 修订）

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
| C2-5 | `[~]` | 手动输入页：校验 E3/E4 + 实时预览 + 高级选项折叠 —— \`AddAccountView\`（分段外壳 + 导入占位）+ \`ManualEntryView\` + \`ManualEntryModel\`（9 单测）；106 测试全绿 | 剩：手工回归（输入密钥看预览刷新 / E4 报错 / 提交置顶 + toast） |
| C2-6 | `[~]` | **导入图片页**：拖放 + 选择文件 + Vision 解码 + 预填 —— \`QRImageDecoder\`（Vision，面积降序）+ \`QRImport.resolve\`（E9/E10/无效 otpauth）+ \`ImportImageView\`（拖放悬停态/缩略图/原地报错/NSOpenPanel）+ \`ManualEntryModel.prefill\`；114 测试全绿（含 CIQRCodeGenerator 真实二维码往返 + 双码合成图） | 剩：手工回归（Finder 拖入真实截图 / HEIC / 损坏图片）；**Info.plist 无 `NSCameraUsageDescription` 已验证 ✅** |
| C2-7 | `[x]` | 详情页：身份区 + 168 大环 + 参数卡 + 操作区 —— \`AccountDetailView\` 截图验证 ✅（渐变头像/heroTrack 大环/告警态/五行参数卡/编辑占位+删除图标） | 参数与账户一致 ✅ |
| C2-8 | `[x]` | 删除确认弹窗（FR-06）—— 遮罩 0.65 / 304 宽 / 文案明示不可恢复 / 取消+红底删除；R8 260ms 自动弹窗 ✅ | 必经二次确认 ✅；真实删除走手工回归 |
| C2-4 | `[x]` | 倒计环 + 告警态（T4）+ 跨周期无闪烁（T5）—— **用户实测：与 GA 并排比对逐秒一致（T6 ✅）**；列表/详情环、T4 告警态截图确认 | 与 \`index.html\` 并排逐秒一致 ✅（用户 2026-09-16 确认） |

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

## 阶段 4 · P1 迭代（PRD v1.3 收敛后范围）

### C4-10 · 导出范围选择（PRD v1.6，2026-09-16 用户反馈）

| 项 | 实现 | 状态 |
|---|---|---|
| 范围选择器 | 新增 `ExportScopePicker`（分段「全部账户（N）/ 指定账户」+ 指定时账户下拉，标签与列表行一致「发行方：账户名」），**两个导出弹窗共用** | ✅ 截图验证 |
| 加密备份导出 | `exportBackup(password:onlyID:)` 按范围过滤；单账户文件名 `2way-<账户名>-<时间>.2wbackup`（文件名安全化 + 限长 32） | ✅ 4 个单测 |
| GA 迁移码导出 | `exportGAMigration(onlyID:)` 同范围过滤（支持只把某一个账户迁到手机） | ✅ 单测（编码→解析） |
| toast 回执 | 单账户：已导出「名称」/ 已导出「名称」的迁移码；全部：已导出 N 个账户 | ✅ |
| 校验 | 无账户 / 指定账户未选 / 口令过短 / 两次不一致 均有就地报错 | ✅ |

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
| C4-2 | `[x]` | **编辑账户**（名称 / 发行方 / 密钥 / 高级参数）—— `AccountStore.update`（E3/E4 重校验 + 清取码缓存）+ `ManualEntryModel.editingAccountID` + 编辑模式复用表单（隐藏分段、按钮「保存」）；详情页标题栏铅笔图标进入；新增 3 单测 | 预填现值 ✅ 截图验证 / 不新增账户、id 不变 ✅ / 换密钥后取码变化 ✅ |
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
| C3-4 | `[x]` | Release：archive → 全组件重签 → DR 校验 → UDZO → 校验 → 挂载实测 —— `dist/2way-0.1.0.dmg`（908K），DR = `identifier "com.kimi.2way" and certificate root H"88f7f892…"`，挂载后签名校验通过 | `dist/2way-*.dmg` 可挂载运行 ✅ |

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
| 2026-09-16 | **C2-6 导入图片页落地**：\`QRImageDecoder\`（Vision 唯一路径，symbologies=.qr，按包围盒面积降序 = E11 取最大者）+ \`QRImport.resolve\`（noQRCode / account / notOTPAuth / invalidOTPAuth 四态）+ \`ImportImageView\`（fileURL/图片双通道拖放 + 悬停态描边转强调色 + 底色提亮 + 缩略图保留 + NSOpenPanel 仅图片类型）+ \`ManualEntryModel\` 增加 issuer 字段与 \`prefill(from:)\`；手动表单新增「发行方（可选）」字段（预填发行方需要）；单测用 CIQRCodeGenerator 生成真实二维码 + 双码合成图覆盖往返/E9/E10/E11；Info.plist 无 NSCameraUsageDescription 实测确认；测试 106 → 114 全绿 |
| 2026-09-16 | **GA 导出迁移码支持（C2-6b，用户实测反馈驱动）**：用户拿 GA「导出二维码」（\`otpauth-migration://offline?data=...\`）被 E10 误拦。新增 \`OTPMigration\` 手写 protobuf wire 解码（secret/name/issuer/algorithm/digits/type，HOTP 跳过并计数知情）；\`QRImport\` 增加 migrated 路径 —— **多账户批量直接入库 + toast「已导入 N 个账户」（含 HOTP 跳过提示），单账户仍走预填确认流**；PRD P1「从其他验证器迁移」的 GA 导出部分提前落地；用用户真实截图端到端验证（5 个 TOTP 全部识别）；测试 114 → 121 全绿 |
| 2026-09-16 | **C2-7 详情页 + C2-8 删除确认弹窗实现落地**：\`AccountDetailView\`（身份区渐变头像 / 168 大环 heroTrack / 参数卡 / 复制+删除操作区 / 标题栏编辑占位）+ FR-06 删除确认弹窗（遮罩 0.65 / 304 宽 / 文案明示不可恢复 / Esc=取消）；R7/R8 接通（切详情 + 260ms 自动弹窗）；测试 121 全绿 |
| 2026-09-16 | **D9：弃用 Keychain → EncryptedStore 加密文件（用户决策）**：本机 login 钥匙串条目 ACL 不信任创建者，同构建读取也逐条弹授权框（实测 \`open\`/直接执行均复现），且 \`load()\` 单条失败曾导致全列表消失（已改为单条容错）。新存储：\`wallet.bin\`（AES-256-GCM 认证加密 + 原子替换 + 0600）+ \`master.key\`（随机 32B + 0600，目录 0700）；6 个单测覆盖往返/跨实例持久化/CRUD/篡改检测/主密钥丢失/文件权限；实测零弹窗 + 跨启动持久化 ✅；测试 121 → 127 全绿。**S1 降级已获用户确认**（见 U10） |
| 2026-09-16 | **C3-2 性能修复（P-1 达成）**：初测 5 环稳态 CPU 36%（SwiftUI 30Hz TimelineView 全列表失效 + AppKit 全窗口布局 churn，sample 定位）。重构：环改 \`RingLayerView\`（CAShapeLayer ×2）+ \`RingClock\` 单一 30Hz 时钟直驱 layer；进度用 CABasicAnimation 按剩余时长 GPU 插值，tick 仅在换周期/告警切换时写 layer；码文本改秒对齐 1Hz \`TimelineView(.periodic)\`。**36% → 0.4-0.7%**，RSS ≈ 92MB，4 线程 |
| 2026-09-16 | **阶段 3 验收交付完成**：C3-1 差异清单全部有决策（等价替代接受）；C3-3 安全自查按 D9 修订全勾（wallet 密文/0600 权限含单测/零日志/进程参数干净）；C3-4 \`dist/2way-0.1.0.dmg\` 打包 + 挂载实测通过，DR 锚定自签证书 |
| 2026-09-16 | **T5/T6 修复：码文本刷新链路（用户实测反馈）**。现象：环在动、码文本冻结。定位过程：① 单元测试证明 store 真时钟与取码缓存正常（新增 \`AccountStoreRealtimeClockTests\`，period=1s 跨周期必变）；② \`TimelineView(.periodic)\` 与 \`onReceive\`+通知两条刷新路径在真机未触发重算。方案：新增 \`SecondPulse\`（@Observable 全局秒脉冲，由 RingClock 整秒推进），视图读取脉冲建立原生观察依赖 → 整秒重算码文本；环动画 \`beginTime\` 锚定绝对周期边界 → **换码与环重置同刻**。验证：35 秒跨周期截图，4 个码全部刷新 ✅。**方法论教训：验证码刷新必须跨周期（>30s）比对，7 秒间隔的对比结论无效** |
| 2026-09-16 | **PRD v1.3 + P1 范围收敛（用户决策）**：触控板双指横滑、全局快捷键**不做**（代价/风险与收益不成比例，且全局快捷键的辅助功能授权与 v1.1「缩小权限面」相悖）；P1 收敛为「编辑账户 / 导入导出备份 / 剪贴板自动清除」；S1 条款按 D9 重写为「加密落盘」，S4 提前到本期 |
| 2026-09-16 | **C4-10 导出范围选择（PRD v1.6）**：两条导出路径（加密备份 / GA 迁移码）均支持「全部账户 / 指定账户」；新增共用 `ExportScopePicker`；单账户导出文件名带账户名；4 个单测（范围解析 / 标签 / 过滤 / 单账户往返）；测试 150 → 154 全绿 |
| 2026-09-16 | **C4-9 刷新频率优化 + 性能数据复核**：① 新增 `CodePulse`（环换码时触发）替代列表的 `SecondPulse` 1Hz 刷新 —— 列表只显示码不显示秒数，只需在换码时重算；② `RingLayerView.updateLayerGeometry()` 加「无变化不重设」守卫，避免每次 SwiftUI 刷新都重设 layer path/frame；③ 复核性能并如实记录：**可见 1–2.6% / 遮挡 0.2%**（此前 0.4% 是遮挡态），残余成本为环持续动画的每帧合成。换码刷新经 34 秒跨周期截图验证仍正确 |
| 2026-09-16 | **C4-8 复制无提示修复**：`ToastCenter` 由 `ObservableObject + @Published` 改为 `@Observable` —— 根因是 `@State` 持有 `ObservableObject` 不建立订阅，导致 toast 状态变化不触发重绘（此前从未渲染过 toast）。修复后复制即时弹出「已复制」。应用名/Bundle ID 按用户要求保持不变 |
| 2026-09-16 | **C4-7 列表交互与样式（PRD v1.5）**：标题「TwoWay 密钥生成器」；移除悬停复制图标（复制唯一入口 = 单击整行，toast「已复制」）；行标题改为「发行方：账户名」单行（次要色发行方 + 主色账户名） |
| 2026-09-16 | **D10 移除系统窗口 chrome + C4-5 五项修复**：窗口不再显示关闭/最小化/缩放按钮（`isHidden + alpha 0 + disabled`，标题栏透明、无系统标题文字），「⋯」菜单加「退出 2way」，窗口拖动改由自绘标题栏 `WindowDragArea`（`performDrag`）承担，标题栏回收 52pt 交通灯预留位；PRD → v1.4（G-03 改写）。同轮修复：详情页返回按钮/Esc、环尺寸 bug（shape layer 零 frame 致旋转平移出视图）、列表环归位、行内显示发行方、GA 兼容导出（迁移码 PNG） |
| 2026-09-16 | **C4-5 用户实测 5 项修复（UI/交互）**：① 详情页返回按钮 + Esc（原先完全无退出路径）；② 环尺寸 bug（shape layer 零 frame 导致旋转把圆平移出视图 → 巨圆压住参数卡）；③ 同源修复后列表环回到行中心；④ 列表行显示发行方（三行布局）；⑤ GA 兼容导出（迁移码 PNG，含明文风险提示）。150 测试全绿 |
| 2026-09-16 | **C4-3 导入导出/备份落地（兼 U13 逃生通道闭环）**：`BackupArchive` 自描述格式（magic `2WBA` / 版本 / PBKDF2 轮数与盐 / AES-GCM combined）；口令派生用 **PBKDF2-HMAC-SHA256 + 随机盐 + 210k 轮**（CommonCrypto），加密用 **AES-256-GCM** 认证加密（口令错误与文件篡改都明确失败，不解出脏数据）；`AccountStore.backupEntries()/importBackup()`（同 id 幂等跳过、不覆盖本地改动、按 addedAt 重排）；列表标题栏「更多」菜单（PRD §7.1 的三点图标）+ 导出/导入弹窗（口令二次确认、就地报错）；导出文件 0600；9 个单测含**灾难恢复端到端**（导出 → 全新空存储 → 导入 → 取码一致）；测试 139 → 148 全绿 |
| 2026-09-16 | **C4-2 编辑账户落地**：`AccountStore.update`（名称/发行方/密钥/参数；E3 清洗 + E4 校验；清该账户取码缓存）+ `secretBase32(for:)`（预填用，密钥不出内存）+ `ManualEntryModel` 编辑模式（`editingAccountID` 路由 add/update）+ 表单复用（编辑时隐藏分段控件、主按钮文案「保存」）+ `AppRouter.Screen.editAccount`；详情页铅笔图标从「占位 toast」改为真入口；3 个单测（预填/不新增且 id 不变/换密钥取码变化/空名兜底）；截图验证编辑页；测试 136 → 139 全绿 |
| 2026-09-16 | **C4-1 剪贴板自动清除（S4）落地**：\`ClipboardGuard\`（记录写入时 changeCount，仅当仍归本应用所有才清除，**绝不误清用户后续复制的内容** —— PRD §4.7 关键约束）；默认 30s；\`Pasteboard\` 协议 + \`SystemPasteboard\` 抽象出可注入实现；7 个单测（到期清除 / 他方写入不误清 / 手动触发 / 失败路径 / 开关 / 连续复制重置 / 默认延迟）；列表与详情两处复制路径接入；测试 129 → 136 全绿 |

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
