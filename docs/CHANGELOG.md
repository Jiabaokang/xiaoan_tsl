# 文档更新记录

每次提交涉及 `docs/`、`AGENTS.md` 或根目录 `README.md` 的修改时，在顶部新增一条记录。一个提交或一批相关修改写一条；日期使用本地日期，说明修改内容、原因和相关文件。Git 历史保留逐行差异，本文件方便按时间查找文档变更。

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
