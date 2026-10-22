# 文档更新记录

每次提交涉及 `docs/`、`AGENTS.md` 或根目录 `README.md` 的修改时，在顶部新增一条记录。一个提交或一批相关修改写一条；日期使用本地日期，说明修改内容、原因和相关文件。Git 历史保留逐行差异，本文件方便按时间查找文档变更。

## 2026-10-22 — 实施 macOS 苹果离线翻译接入

- 按[接入开发文档](superpowers/plans/20261020151615_macOS苹果离线翻译接入开发文档.md)补齐原生协调器、可见系统准备宿主、Dart 服务与设置页、首页及截图链路；记录准备、取消、超时、错误与独立请求的契约。
- 同步[服务接口](03_specs/service_contracts.md)、[状态机](03_specs/state_machine.md)、[活跃执行计划](04_plans/current_plan.md)、[文档入口](README.md)、[截图方案](02_design/20261002225612_macOS截图翻译实施方案.md)和[原 Task 8](superpowers/plans/20261002225612_macOS截图翻译实施计划.md)。默认服务、百度凭据、最低 macOS 14、包名与签名保持现状。
- 原因：核对发现原生桥只有占位实现，Dart apple 分支仍回退默认服务；本轮根据用户授权继续完成开发，补齐禁止自动云端回退和取消竞态的回归保护。
- 验证：Flutter 全量测试 275 项通过，`flutter analyze` 无问题；macOS Debug 构建成功；RunnerTests 执行 40 项、1 项因语言包未安装跳过、0 失败。OnePlus 9（Android 14）已用 `adb install -r` 覆盖安装并完成启动回归，无崩溃。
- 未覆盖：真实语言包下载授权与取消、断网翻译、真实截图闭环、系统 sheet、全屏 Space、macOS 14 和 iOS 实机；均已登记为待验收。

## 2026-10-20 — 编写 macOS 苹果离线翻译接入开发文档

- 新增[接入开发文档](superpowers/plans/20261020151615_macOS苹果离线翻译接入开发文档.md)，供其他 agent 实现：记录当前禁用原因、公开 API 与版本限制、通道接口、可见 SwiftUI 宿主、语言包准备与取消、30 秒翻译超时边界、首页/截图共用服务、隐私与验收矩阵。
- 同步[文档入口](README.md)、[截图方案](02_design/20261002225612_macOS截图翻译实施方案.md)、[原计划 Task 8](superpowers/plans/20261002225612_macOS截图翻译实施计划.md#task-8增加-macos-15-苹果端侧翻译)和[活跃执行计划](04_plans/current_plan.md)，标明待实现；保持默认百度，收窄早期切换默认引擎的可选设想。
- 原因：用户反馈苹果选项无法选择，源码确认尚未接入；将开发范围与验收要求落为可交接文档。保留工作区已有并行修改，本批只修改文档。
- 验证范围：核对当前代码、Apple 官方资料及本机 Translation SDK 声明；文档相对链接、代码围栏和差异格式检查。未运行 Flutter 测试、构建、下载语言包或实机验收。

## 2026-10-20 — 补充三端构建包命令

- 更新 [项目 README](../README.md)：按 Android、iOS、macOS 分别补充 Debug 测试包与 Release 生产包命令，加入 iOS IPA 和 macOS 固定安装脚本说明。
- 原因：统一三端构建入口，明确测试包与生产包的区别，减少误用未签名包或 macOS 临时构建产物的情况。
- 验证：使用 Flutter 3.44.9 检查所列构建参数，`git diff --check` 通过。

## 2026-10-20 — 截图翻译改造为原位覆盖面板

- 更新 [实施方案](02_design/20261002225612_macOS截图翻译实施方案.md)、[文档入口](README.md) 与 [活跃执行计划](04_plans/current_plan.md)。
- 原因：用户需求在触发截图翻译时自由拖动框选区域，并在截图区域原位直接覆盖显示对应翻译内容；废弃原独立结果窗口及第二个 FlutterEngine 实例（`screenshotWindowMain` 改为空实现兼容），由纯原生 AppKit 组件（`OverlayResultPanel` 与 `OverlayResultView`）负责就地展示，提供自适应字号、向下自动扩展、长按/点击查看原文 Peek 模式、底部浮动工具条（复制、重截、关闭）以及点击外部/Esc/3分钟超时自动淡出，消除额外引擎开销与启动延迟。
- 验证：Flutter 静态分析 `flutter analyze lib/ test/` 0 问题；全量自动化测试 `flutter test` 172 项全部通过；原生构建 `flutter build macos --debug` 编译通过。

## 2026-10-12 — 截图翻译改为独立结果窗口

- 更新 [实施方案](02_design/20261002225612_macOS截图翻译实施方案.md) 的窗口及快照通道契约，更新 [文档入口](README.md) 与 [活跃执行计划](04_plans/current_plan.md)。
- 原因：结果路由占用主页，Dock 无法回到主页，系统关窗会隐藏唯一窗口。改为独立结果窗口，业务仍由主引擎处理，关闭结果恢复主页，Dock 可随时打开主页；移动端保留原流程。
- 验证：Flutter 全量回归 165 项、原生回归 15 项通过，静态检查无问题；Release 已按安装脚本覆盖安装并从固定位置启动，签名验证通过。Android 真机未连接，完整截图及全屏、多屏场景仍待实际验收。

## 2026-10-05 — 固定 macOS 应用安装位置，避免出现两个 APP

- 新增 `scripts/install_macos.sh`：构建 Release 后覆盖安装到 `~/Applications/xiaoan_tsl.app` 单一位置并启动。
- 更新 `AGENTS.md`：新增 macOS 桌面运行与打包规则，调试统一用 `flutter run -d macos`，分发验收用安装脚本，禁止直接从 `build/` 目录打开或拷贝多份 `.app`。
- 原因：VSCode 运行（Debug）与 Agent 执行的 `flutter build macos --release`（Release）分别在 `build/macos/Build/Products/` 的 `Debug/`、`Release/` 目录各生成一个同名 `.app`，被误认为每次生成临时包名；经核实 bundle identifier 始终为 `com.example.xiaoanTsl`，且 Debug/Release 均由同一 Apple Development 证书签名，包名与签名均未随机变化。

## 2026-10-05 — 刷新失效录屏授权并补回系统正式申请

- 更新 [活跃执行计划](04_plans/current_plan.md)：记录本应用录屏授权的精准重置结果，以及捕获服务无法代为提示授权的实际日志。
- 修复：原生截图入口正式调用 `CGRequestScreenCaptureAccess()`，同时保留按实际 ScreenCaptureKit 结果判断授权的行为，避免申请成功仍被提前拒绝。
- 验证：修复版构建成功，原生回归 14 项通过；旧签名授权不匹配日志已消失，新的系统授权确认与完整捕获/翻译验收仍待完成。

## 2026-10-05 — 设置主页截图快捷键与后台框选交互

- 更新 [活跃执行计划](04_plans/current_plan.md)：记录快捷键入口位置调整、后台首次点击与键盘焦点、最小化恢复、框选提示、回调安装时序及 Retina 快照尺寸修复。
- 原因：用户需要最小化后按全局快捷键截图翻译，并核实 OCR 是否实现；原生选区面板缺少焦点和首次点击处理，屏幕 point 尺寸也被误用于像素快照。
- 验证：完整 Flutter 回归 145 项、原生回归 14 项通过，静态检查无问题；macOS 构建、稳定签名、格式和差异核验通过。真实 Vision OCR 成功识别 `Hello world`；真实屏幕捕获仍返回 `-3801`，系统旧授权未匹配稳定证书，完整翻译实机验收保持未完成。

## 2026-10-05 — 记录 macOS 录屏授权不生效的根因与修复

- 更新 [活跃执行计划](04_plans/current_plan.md)：记录 IDE 权限归属、临时签名与旧授权不匹配的系统日志证据，说明原生权限判断修复和本机稳定开发签名配置。
- 原因：系统设置显示应用已授权，实际截图仍被拒绝；区分代码回归验证与需要重新关联旧授权的实机验收。
- 验证：Flutter 测试 144 项、RunnerTests 11 项通过，`flutter analyze` 无问题；稳定开发证书签名的 Debug 构建成功，签名要求已核验；实际捕获已确认系统授权拒绝，完整截图/OCR/翻译验收待旧授权重新关联。

## 2026-10-03 — 登记 macOS 截图翻译实施进度（Task 0～6 实现完成）

- 更新 [macOS 截图翻译实施计划](superpowers/plans/20261002225612_macOS截图翻译实施计划.md)：按用户要求在 dev 分支开始代码实施，勾选 Task 0～6 中实际完成的复选框；百度账号类型未确认，智能云分支与凭据产品名称确认保持未勾选并注明原因；Task 4～6 的实机验收完成条件保持未勾选、留待 Task 7。
- 更新 [活跃执行计划](04_plans/current_plan.md)：登记环境基线、变更文件、验证结果与未完成项。
- 原因：用户要求“每完成一步在文档中打勾”，未完成项不得勾选；为后续交接代理提供可追溯进度。
- 验证：`flutter analyze` 0 问题；全量 `flutter test` 139 项通过（截图控制器 13 项 + 结果页 10 项为 Task 6 新增）；桌面通道 Dart 测试 15 项通过；`flutter build macos --debug` 成功；RunnerTests 原生单测 9 项通过（含快捷键解析与坐标换算）。

## 2026-10-02 — 保存 macOS 截图翻译调研、实施方案与实施计划

- 新增 [需求与选型调研](01_prd/20261002225612_macOS截图翻译需求与选型调研.md)：整理快捷键截图翻译需求、现有 ML Kit 平台限制、开源参考及免费/低价 API 费用快照，说明百度两类产品与真实调用尚未验证的边界。
- 新增 [实施方案](02_design/20261002225612_macOS截图翻译实施方案.md) 与 [实施计划](superpowers/plans/20261002225612_macOS截图翻译实施计划.md)：定义单 Flutter 窗口、本地 OCR、可选百度 API、移动端 ML Kit 保留与 macOS 15+ 苹果端侧扩展，列出 P0～P4 任务、文件、测试和实机验收要求。
- 更新 [文档索引](README.md) 增加专项入口；保留其他未提交工作。原因：将讨论落地为可审阅、可执行的本地文档；本批不修改应用代码、不安装依赖、不调用 API、不发布应用。
- 验证：执行本批 Markdown 本地链接、围栏、占位标记及范围检查，git diff --check 通过；未运行 Flutter 测试、构建或设备验收。

## 2026-09-27 — 编写 iPad 与 Android 平板端界面适配技术方案与设计指南

- 新增 [平板端适配指南](02_design/tablet_adaptation_guide.md) 并更新 [文档索引](README.md)：系统梳理从移动端到平板（iPadOS / Android 平板 / 折叠屏大屏）的完整适配方案，涵盖基于 Window Size Classes 的三级断点体系（Compact / Medium / Expanded）、自适应导航外壳（NavigationBar 切换为 NavigationRail）、翻译首页左右并排双面板对照重塑、历史记录 Master-Detail 主从分栏、设置页最大宽度居中约束、iPad 原生分享崩溃防御（sharePositionOrigin 锚点传参）及外设键盘快捷键交互体系。
- 原因与范围：响应大屏多任务与平板适配演进需求，提供无破坏性的设计规范与三阶段实施路线图，暂不改动现有实现代码。

## 2026-09-27 — 首页缺模型时确认下载并允许移动网络

- 更新 [产品需求](01_prd/prd_v1.0.md)、[状态机规格](03_specs/state_machine.md) 与 [活跃执行计划](04_plans/current_plan.md)：首页检测到缺少翻译模型时先征求确认，确认后允许本次使用移动网络，下载完成自动续译；修正原先默认 Wi-Fi 与拒绝下载转错误状态的旧描述。
- 原因与验证：避免首次使用需等待 Wi-Fi 或前往设置页；`flutter analyze` 无问题，69 项 Flutter 测试通过，OnePlus 6 已在 Wi-Fi 下验证提示、下载与续译，蜂窝网络未实测。

## 2026-09-26 — 外观模式的显示和选择调整为和应用语言一致

- 交互对齐与视觉一致性：修改 [SettingsPage](../lib/features/settings/settings_page.dart)，将外观模式从行内下拉菜单（DropdownButton）重构为与应用语言完全一致的标准 ListTile（显示当前模式副标题与右侧箭头），点击整行呼出包含跟随系统、浅色、深色并带选中对勾标记（`Icons.check`）的 SimpleDialog 单选弹窗，调用 `AppController.setThemeMode` 进行即时响应与本地持久化。
- 自动化测试与质量保障：在 [test/widget_test.dart](../test/widget_test.dart) 中适配已有测试中的主题切换交互，并新增设置中外观模式副标题与弹窗切换勾选的组件测试用例；全量 66 项测试全部通过，`flutter analyze` 零告警零错误。

## 2026-09-26 — 完成隐私政策、关于页面与第三方开源库路由集成及兼容层改造

- 路由注册与解耦：更新 [app_router.dart](../lib/core/router/app_router.dart)，将 `/privacy` 映射到 [PrivacyPolicyPage](../lib/features/settings/privacy_policy_page.dart)，`/about` 映射到 [AboutPage](../lib/features/settings/about_page.dart)，新增 `/about/dependencies` 映射到 [OpenSourceLicensesPage](../lib/features/settings/open_source_licenses_page.dart)。
- 兼容层平滑过渡：改造 [info_page.dart](../lib/features/settings/info_page.dart) 为透明转发与类型导出兼容层，保留 `InfoKind` 与 `InfoPage` 类，保障已有调用方与深链无破坏。
- 自动化测试与质量保障：全量 65 项自动化测试全部通过，包括新增的针对隐私政策结构化卡片、品牌关于页特性、第三方库镜像跳转、兼容转发层及路由配置的测试，`dart format lib test` 格式化规范，`flutter analyze` 零警告零错误。

## 2026-09-26 — 编写隐私政策与关于小安翻译重构及第三方库跳转设计规范与实现计划

- 设计规范与实现计划：编写 [隐私政策与关于小安翻译重构及第三方库跳转设计规范](superpowers/specs/2026-09-26-privacy-and-about-page-design.md) 与 [实现计划](superpowers/plans/2026-09-26-privacy-and-about-page.md)，将隐私政策升级为结构化卡片与清晰章节排版，重构关于小安翻译突出品牌与核心离线特性，并新增独立的第三方开源依赖展示页，支持点击跳转至 `https://pub-web.flutter-io.cn/packages/<name>`。
- 规范化任务抽取契约：为实现计划中的 5 个任务补充 Task 编号标题，方便 SDD 子智能体驱动开发自动化提取。
- 验证：完成规格与计划自检，划分 5 个 TDD 步骤任务，核对路由规划、组件解耦、国际化契约及既有测试用例兼容性。

## 2026-09-26 — 编写外观模式设置交互与应用语言对齐设计规范

- 设计规范定义：编写 [外观模式设置交互与应用语言对齐设计规范](superpowers/specs/2026-09-26-theme-mode-settings-consistency-design.md)，将设置页中外观模式的显示与选择从行内 DropdownButton 改造为与应用语言一致的 ListTile（含副标题、右箭头）及 SimpleDialog 单选勾选弹窗，并制定自动化测试与验收标准。
- 验证：完成规格自检，覆盖组件结构、状态流、文案契约与测试用例适配计划。

## 2026-09-26 — 支持中文与英文国际化多语言及跟随系统语言

- 架构设计与状态持久化：引入 `flutter_localizations` 与 `intl`，定义 [AppLocalizations](file:///Users/jiabaokang/AndroidDeveloper/FlutterProject/xiaoan_tsl/lib/l10n/app_localizations.dart) 契约及中英文实现；在 `AppState` / `AppController` 中增加 `localeMode` 支持跟随系统（`system`）、简体中文（`zh`）和英文（`en`），并通过本地轻量存储持久化偏好。
- 全量页面硬编码抽取与国际化适配：在 `MaterialApp.router` 配置中英文委托与智能系统语种解析；底部导航栏、翻译首页、设置页、历史记录与收藏、离线语言包、语言选择列表及关于/隐私政策页面全量接入 `context.l10n`。设置页新增应用语言切换弹窗，支持即时动态切换。
- 验证：全量 42 项自动化测试通过（覆盖系统跟随、手动切换、持久化和返回导航适配），`flutter analyze` 零警告零错误。

## 2026-09-25 — 补充隐私政策外链与 Google Play AAB 构建说明

- 更新 [README](../README.md) 的 Android 打包说明：补充 AAB 构建命令，说明默认架构与 Google Play 按设备分发方式，避免将 APK 的 `--split-per-abi` 参数用于 AAB。
- 更新隐私政策：在设置页与说明页提供完整外部隐私政策链接，支持浏览器跳转。
- 验证：39 项测试及 `flutter analyze` 全部通过。

## 2026-09-25 — 校准构建说明与真机验收记录

- 更新 [README](../README.md) 中的覆盖安装命令，移除重复且与当前工程不符的 NDK 步骤。
- 更新 [活跃执行计划](04_plans/current_plan.md) 的签名模板、测试数量和 Release 真机验收状态，记录短文本与 R8 问题的修复证据。
- 说明 [文档索引](README.md) 中本地 Git 钩子的分发范围，避免新克隆工作区误以为已包含钩子。
- 验证：全量 39 项 Flutter 测试通过，`flutter analyze` 无问题；Release APK 在 OnePlus 9 覆盖安装后通过翻译与语言列表检查。

## 2026-09-24 — 整理文档入口与更新规则

- 统一文档索引，明确固定需求、设计、契约、活跃计划与 superpowers 实施计划的职责，方便从 [文档索引](README.md) 找到当前版本。
- 移除核心框架计划的重复副本，为历史计划标明状态，并修复归档文档中的相对链接，避免旧路径影响追溯。
- 更新 [仓库协作说明](../AGENTS.md) 和 [项目 README](../README.md) 中过时的项目状态；加入本记录及提交检查，使后续文档修改有更新条目。
- 验证：本地 Markdown 相对链接检查无失效项；`git diff --check` 通过；提交检查分别验证了遗漏记录时拒绝、加入记录后通过。

## 后续记录格式

```text
## YYYY-MM-DD — 简短主题

- 修改：具体变更与原因；涉及的文档链接。
- 验证：实际运行的文档检查或测试及结果。
```
