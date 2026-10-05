# 小安翻译文档索引

本目录记录 v1.0 的产品需求、设计、实现契约、执行状态和历史材料。文档描述的计划与实际完成情况可能不同；判断当前进度时，以[活跃执行计划](04_plans/current_plan.md)和当前代码、测试结果为准。

## 当前文档与职责

| 位置 | 职责 | 入口 |
| --- | --- | --- |
| `01_prd/` | 产品目标、功能范围和验收要求 | [v1.0 PRD](01_prd/prd_v1.0.md) |
| `01_prd/compliance/` | 与产品需求关联的合规草案，发布前仍需确认 | [隐私政策草案](01_prd/compliance/privacy_policy.md) |
| `02_design/` | 应用架构、技术选择、交互原型与大屏适配指南 | [架构设计](02_design/architecture.md) · [HTML 原型](02_design/prototype.html) · [平板端适配指南](02_design/tablet_adaptation_guide.md) |
| `03_specs/` | 实现时采用的细化契约 | [状态机](03_specs/state_machine.md) · [数据库](03_specs/database_schema.md) · [服务接口](03_specs/service_contracts.md) · [路由](03_specs/routing_and_deeplink.md) |
| `04_plans/` | 当前任务、验收结果与未完成事项 | [活跃执行计划](04_plans/current_plan.md) |
| `superpowers/plans/` | 按 superpowers 流程编写的、带日期的实施计划；完成后保留原记录 | [核心框架计划](superpowers/plans/2026-09-24-core-framework.md) · [v1 剩余功能计划](superpowers/plans/2026-09-24-v1-completion.md) |
| `99_archive/` | 早期草案、旧需求和阶段验收快照，仅用于追溯 | [核心框架验收记录](99_archive/20260924094609_小安翻译核心框架需求_验收记录.md) |
| `CHANGELOG.md` | 文档及协作说明的逐次更新记录 | [更新记录](CHANGELOG.md) |

## macOS 截图翻译专项文档

本专项当前仅完成需求调研、实施方案和计划，应用功能尚未实施。最低 macOS 14、截图在上译文在下及百度产品类型是方案中的前置约定；进度以实际代码和验收记录为准。

| 文档 | 职责 |
| --- | --- |
| [需求与选型调研](01_prd/20261002225612_macOS截图翻译需求与选型调研.md) | 用户需求、当前代码核对、开源参考、API 费用快照与验收边界 |
| [实施方案](02_design/20261002225612_macOS截图翻译实施方案.md) | 平台与引擎选择、原生截图/OCR、单窗口交互、安全存储和苹果翻译扩展 |
| [实施计划](superpowers/plans/20261002225612_macOS截图翻译实施计划.md) | P0～P4 分阶段任务、涉及文件、测试命令、首版与扩展的完成标准 |

## 与 superpowers 的对应关系

本项目已有的 `01_prd/`、`02_design/`、`03_specs/` 是当前产品需求和技术契约的固定入口。使用 superpowers 形成新设计时，可按其默认约定存入 `docs/superpowers/specs/YYYY-MM-DD-<topic>-design.md`；通过评审后，把需要长期遵循的内容同步到上述固定入口。实现计划存入 `docs/superpowers/plans/YYYY-MM-DD-<feature-name>.md`。`04_plans/current_plan.md` 只维护当前进度和验收结果，不复制整份实施计划。历史计划原地保留并标明状态；不再维护第二份副本。

固定入口使用稳定文件名；带日期的方案和历史记录使用创建日期及主题命名。已有的中文时间戳归档文件保留原名，避免为统一格式而破坏引用。

## 修改与验证

每批文档或仓库协作说明变更，都在 [CHANGELOG.md](CHANGELOG.md) 顶部新增一条记录，写明日期、修改内容、原因和相关文件。代码的逐次差异由 Git 提交历史记录；代码行为变化同时更新受影响的需求、契约或计划时，也应记录这批文档变化。提交检查会在 `docs/`、`AGENTS.md` 或根目录 `README.md` 有暂存改动时，要求同次暂存 `docs/CHANGELOG.md`。首次在本地启用：

```sh
git config --local core.hooksPath .githooks
```

这个检查只约束 Git 提交；提交前仍需检查记录是否准确。`.githooks/` 是当前机器的本地文件，不随仓库分发；新克隆的工作区如需同样的检查，应先自行安装钩子，再配置其路径。修改 Flutter 代码时运行 `flutter analyze` 与 `flutter test`；涉及实体设备验证时遵守 [AGENTS.md](../AGENTS.md) 的覆盖安装规则。
