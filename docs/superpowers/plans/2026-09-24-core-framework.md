# 小安翻译核心框架实现计划

> 面向当前工作区实施：任务按顺序执行，每项完成后勾选。依据 [核心框架需求](../../PRD/20260924094609_小安翻译核心框架需求.md)。

**目标：** 将已完成的模拟翻译首页接入可导航、可持久化、可替换服务的 Flutter 应用框架，同时保留既有 JSON 历史。

**架构：** `ProviderScope` 提供演示 `TranslationService`、统一控制器、SQLite 存储和受控 Dio；`MaterialApp.router` 使用 `StatefulShellRoute.indexedStack` 管理四个入口。页面只展示状态和发送操作，数据库负责记录与设置。旧 JSON 只读取一次并在事务中迁移。

**技术栈：** 当前官方 Flutter 3.44.9 / Dart 3.12.2、Material 3、`flutter_riverpod`、`go_router`、`sqflite`、`path`、`dio`、现有 `share_plus` 与 `path_provider`；测试用 `flutter_test` 和 `sqflite_common_ffi`。

## 文件职责

| 文件 | 职责 |
| --- | --- |
| `lib/main.dart` | 初始化数据库并挂载 `ProviderScope` |
| `lib/app.dart` | 主题和 `MaterialApp.router` |
| `lib/core/router/app_router.dart` | 四个底部入口、次级路由及未知地址 |
| `lib/core/database/` | SQLite、旧 JSON 迁移与数据库注入 |
| `lib/core/network/dio_provider.dart` | 受控 Dio 客户端 |
| `lib/core/theme/app_theme.dart`、`lib/core/widgets/app_panel.dart` | 共用主题和面板 |
| `lib/features/translate/` | 翻译首页、Riverpod 状态与用户操作 |
| `lib/features/language/` | 语言选择和离线模型现状 |
| `lib/features/history/` | 记录模型、旧 JSON 和共享列表搜索 |
| `lib/features/favorites/` | 复用历史列表的收藏入口 |
| `lib/features/settings/` | 默认语言、主题、数据、隐私与关于 |
| `lib/services/translation/`、`lib/services/sharing/` | 翻译接口及模拟实现、系统复制与分享 |
| `test/core/`、`test/features/`、`test/widget_test.dart` | 存储、控制器与页面行为测试 |

## 任务 1：依赖与本地数据库

- [x] 在 `pubspec.yaml` 增加 `flutter_riverpod`、`go_router`、`sqflite`、`path`、`dio`，测试依赖增加 `sqflite_common_ffi`；运行官方 SDK 的 `flutter pub get` 并同步 `pubspec.lock`。
- [x] 在 `test/core/database/local_store_test.dart` 检查：把一条带收藏的旧 JSON 导入数据库，重开后只有一条；损坏旧 JSON 时不覆盖旧文件；设置读写和原文/译文搜索返回正确记录。
- [x] 在 `lib/core/database/local_store.dart` 实现 SQLite：`translation_records` 与 `app_settings` 两张表；记录使用稳定 `id`，SQL 参数绑定；从 `lib/features/history/history_store.dart` 的旧 JSON 格式读取并在事务中迁移，旧文件保留。
- [x] 运行存储测试；迁移、重复导入、搜索、收藏、删除与设置检查通过。

## 任务 2：统一状态与服务依赖

- [x] 在 `core/database/`、`services/translation/`、`core/network/` 分别声明 `localStoreProvider`、`translationServiceProvider`、`dioProvider`。Dio 仅配置连接/接收超时，不设置 `baseUrl` 或日志拦截器。
- [x] 在 `test/features/translate/app_controller_test.dart` 检查：短文本自动检测提示手选、异步旧结果失效、翻译成功写历史、默认目标语言与主题重载后保持。
- [x] 在 `lib/features/translate/app_controller.dart` 实现单一 `AppState` 和 Riverpod `Notifier`。`translate()` 通过 `TranslationService`；输入变化使旧请求失效；记录和设置经本地存储操作。
- [x] 运行控制器测试，状态和持久化检查通过。

## 任务 3：路由与四个入口

- [x] 在 `lib/core/router/app_router.dart` 配置 `StatefulShellRoute.indexedStack`：`/translate`、`/history`、`/favorites`、`/settings`；增加 `/languages`、`/offline-models`、`/privacy`、`/about` 与未知地址页。
- [x] 在 `lib/main.dart` 和 `lib/app.dart` 挂载 `ProviderScope` 与 `MaterialApp.router`；主入口只初始化数据库和注入实例。
- [x] 在 `test/widget_test.dart` 检查：四个入口可切换、返回首页后输入仍在；直接打开 `/translate?record=<id>` 显示该记录；未知地址可回首页。
- [x] 运行 `flutter test test/widget_test.dart`，路由及状态保持检查通过。

## 任务 4：页面接线与设置

- [x] 将翻译记录和导航逻辑放入 `features/history/records_page.dart`；首页通过控制器显示输入、语言、状态与结果，保留复制、收藏、分享和示例短句。
- [x] 用 `features/language/language_page.dart` 取代原弹层；搜索现有语言代码，源语言允许 `auto`，目标和默认目标排除 `auto`。历史点击以 ID 打开翻译页。
- [x] 用 `features/settings/settings_page.dart` 保存默认目标语言、系统/浅/深主题并提供清空历史二次确认；语言模型现状、隐私说明和关于分属相应模块。
- [x] 扩展 `test/widget_test.dart`：翻译→收藏→历史搜索与清空、语言选择、设置重建持久化、浅深主题和次级页返回。运行测试。

## 任务 5：验收与文档回填

- [x] 运行 `dart format lib test`、`flutter analyze`、`flutter test`，记录每项真实结果。
- [x] 在 iPhone 17Pro-26.4 模拟器安装并启动应用，检查浅色/深色首页截图；四个入口及交互由 widget 测试验证；Android Debug APK 构建成功。
- [x] 更新需求文档状态与本计划复选框，只标记由代码、测试或设备证据证实的完成项；将模拟服务和真实 ML Kit 的边界明确留在文档。

## 任务 6：按基础架构文档归位模块

- [x] 将路由、数据库、网络、主题和共用面板归入 `lib/core/`；翻译、语言、历史、收藏、设置归入 `lib/features/`；翻译接口与系统分享归入 `lib/services/`。
- [x] 测试按数据库与翻译功能归位，更新所有导入、路由及文档目录树；未实现的语音模块不创建空目录。
- [x] 目录调整后运行 `dart format lib test`、`flutter analyze --no-pub`、`flutter test --no-pub`；11 项测试通过，静态分析无问题。

本计划不包含真实 ML Kit、TTS、正式隐私政策和发布签名。此前首页已作为 `37c70a2` 本地提交；本计划的框架改动留在工作区，等待后续提交指令。
