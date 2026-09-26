# 文档更新记录

每次提交涉及 `docs/`、`AGENTS.md` 或根目录 `README.md` 的修改时，在顶部新增一条记录。一个提交或一批相关修改写一条；日期使用本地日期，说明修改内容、原因和相关文件。Git 历史保留逐行差异，本文件方便按时间查找文档变更。

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
