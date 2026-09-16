# 2way 任务板

> 卡粒度与验收判据以 `TECH_PLAN.md` §6 为准。**每卡必须完成：构建 + 单测 + Git 提交**，才推进下一卡。
> 新增文件后执行 `xcodegen generate` 收录。
>
> 需求版本：**PRD v1.1**（2026-09-16，移除摄像头扫码，改为仅图片导入 —— 见决策 D7）

图例：`[ ]` 待开始 · `[~]` 进行中 · `[x]` 已完成

---

## 阶段 0 · 工程骨架

| 卡 | 状态 | 内容 | 完成判据 | 提交 |
|---|---|---|---|---|
| C0-1 | `[x]` | `project.yml` → App target，最低 macOS 14.0 | `xcodegen generate` 成功、空窗可编译 | `8c3681d` |
| C0-1b | `[x]` | 创建自签代码签名证书并接入构建（§9.3） | `codesign -d -r- App.app` 输出**不含 `cdhash H"..."`** → 实测 DR = `identifier "com.kimi.2way" and certificate root = H"88f7f892…"` ✅ | 本次 |
| C0-2 | `[~]` | `Tokens.swift`（§8 全量）+ 基础组件 | 组件可独立预览，取值与 §8 逐项对齐 | `8c3681d` |
| C0-3 | `[ ]` | `spike-window`：窗口 400×700 + hiddenTitleBar + 圆角/交通灯实测 | 出截图 + 圆角实现方式结论 | — |

**C0-2 明细**

- [x] `Tokens.swift` —— §8 全量颜色 / 尺寸 / 动效 / 字体（含 Demo `:root` 补充的 7 项）
- [x] `WindowTitlebar` + `Divider1px`
- [ ] `PrimaryButton`（高 44 / 圆角 12 / 强调色底）
- [ ] `SecondaryButton`（高 40 / 描边 `--border`）
- [ ] `SegmentedControl`（容器 34 / 圆角 9 / 段 28 / 圆角 7 / 选中 `--seg-active`）
- [ ] `CountdownRing`（小环 28/描边 3，大环 168/描边 5；告警态切换）
- [ ] `Toast`（底部 44pt / 停留 1.8s）
- [ ] `TokenTextField`（高 42 / 圆角 10）

**C0-3 待办**

- [ ] 实测系统窗口圆角 vs PRD 12px 的实际差值
- [ ] 确认交通灯位置是否需用 `NSWindow.standardWindowButton(_:)` 微调
- [ ] 确认 `.ignoresSafeArea()` 下 52pt 标题栏与交通灯的垂直对齐
- [ ] 关闭 zoom 按钮（固定尺寸窗口）
- [ ] 出截图存档到 `docs/spike/window/`

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
| C2-1 | `[ ]` | 列表页：搜索（FR-03）、计数、悬停、空态（E2/E7） | 输入即过滤，计数同步 |
| **C2-2** | `[ ]` | **`spike-swipe`：R1–R11 全量 + 手工回归清单** | **11 条规则逐条通过，含 R6 吞 click** |
| C2-3 | `[ ]` | 复制 + toast + E1 失败路径 | 点按 1 步完成；失败有提示，不静默 |
| C2-4 | `[ ]` | 倒计环 + 告警态（T4）+ 跨周期无闪烁（T5） | 与 `index.html` 并排逐秒一致 |
| C2-5 | `[ ]` | 手动输入页：校验 E3/E4 + 实时预览 + 高级选项折叠 | 密钥变更即刷新预览 |
| C2-6 | `[ ]` | **导入图片页**：拖放 + 选择文件 + Vision 解码 + 预填（v1.1 已移除摄像头） | 能解码并预填到手动输入页；E9/E10/E11 异常路径均有提示；Info.plist 无 `NSCameraUsageDescription` |
| C2-7 | `[ ]` | 详情页：身份区 + 168 大环 + 参数卡 + 操作区 | 参数与账户一致 |
| C2-8 | `[ ]` | 删除确认弹窗（FR-06） | 必经二次确认；确认后回列表 |

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
| 2026-09-16 | **PRD v1.1：移除摄像头扫码，添加账户改为仅「图片导入 + 手动输入」**。页面 02 由「扫描二维码」改为「导入图片」；取景框/取景括号/扫描线动画废弃；不再申请摄像头权限。影响：C2-6 重定义、RK2 关闭并新增 RK2b、D1 依据更换（结论不变）、D7 新增 |

---

## 风险登记

| # | 风险 | 等级 | 应对 |
|---|---|---|---|
| RK1 | 左滑 R6「拖拽后补发的 click 被吞掉」在 SwiftUI 下可能偶发失效 | 高 | C2-2 独立成卡 + 手工回归清单；备选 `NSPanGestureRecognizer` |
| RK2 | ~~`AVCaptureMetadataOutput` 运行时对 `.qr` 的支持依赖设备~~ | **已关闭** | v1.1 移除摄像头，不适用 |
| RK2b | Vision 成为**唯一**解码路径，无兜底；对低质量 / 畸变 / 缩放图片的识别率未知 | 中 | C2-6 用真实截图样本集实测（手机截图、裁剪、含透视畸变）；必要时加 `CIFilter` 预处理 |
| RK3 | 系统窗口圆角与 PRD 12px 存在差值 | 中 | C0-3 出实测差值 |
| RK4 | `SecItemCopyMatching` 批量返回行为与预期不符 | 中 | C1-1 先写最小验证脚本 |
| RK5 | 等价字体与设计稿有字距/字重差异 | 低 | C3-1 列差异项并处置 |
| RK6 | E5 系统时间不准导致验证码偏差 | 低 | P0 仅提示；P1 做偏移显示 |
