# 小安翻译 (Xiaoan TSL) 项目文档库

欢迎查阅小安翻译开发文档。本项目采用 **规格驱动开发（Spec-Driven Development / SDD）** 与 **单一可信源（SSOT）** 架构组织文档，确保人类开发者与 AI Agent 拥有清晰、无歧义的上下文。

---

## 目录索引与职责

```text
docs/
├── README.md                   # [本文档] 文档库全局索引与导航
├── 01_prd/                     # 【需求层】WHAT & WHY：产品功能、用户场景与边界
│   ├── prd_v1.0.md             # v1.0 核心产品需求规范
│   └── compliance/             # 法律与合规文档
│       └── privacy_policy.md   # 隐私政策草案
├── 02_design/                  # 【架构层】HOW (Macro)：宏观系统架构与技术选型决策
│   ├── architecture.md         # 分层架构、依赖注入模型、技术选型矩阵与 ADR 决策记录
│   └── prototype.html          # 交互原型页面
├── 03_specs/                   # 【规格层】HOW (Micro 契约)：AI 执行编码必须遵循的严格契约
│   ├── state_machine.md        # 翻译核心流程状态转移与错误状态机
│   ├── database_schema.md      # SQLite DDL、索引、默认设置与 JSON 迁移契约
│   ├── service_contracts.md    # 核心 Service 抽象接口定义、异常模型与数据结构
│   └── routing_and_deeplink.md # 路由路径、Query 参数传递与深链回退规格
├── 04_plans/                   # 【计划层】EXECUTION：原子化、带验证命令的任务清单
│   ├── current_plan.md         # 当前活跃的实施计划（任务分解、验收命令、交接记录）
│   └── archive/                # 历史已完成计划归档
└── 99_archive/                 # 【历史归档】过往早期规划草案与各阶段原始记录
```

---

## AI Agent 与开发者协作规范

1. **查阅优先级**：
   - 了解“做什么”查阅 `01_prd/`；
   - 了解“整体架构与选型”查阅 `02_design/`；
   - **编写代码与实现功能前必须严格依据 `03_specs/` 的契约，不得自行凭空发明数据结构或状态值**；
   - 了解“当前任务与待办”查阅 `04_plans/current_plan.md`。
2. **严禁上下文污染**：
   - `99_archive/` 仅用于历史追溯，不得将其中的旧选型（如 Drift / SharedPreferences）引入当前代码。
3. **闭环验证原则**：
   - 所有代码修改必须经由 `flutter analyze` 与 `flutter test` 验证，真机调试需严格遵守 `AGENTS.md` 的覆盖安装要求。
