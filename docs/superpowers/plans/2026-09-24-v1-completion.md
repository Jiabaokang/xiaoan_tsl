# 小安翻译 v1.0 剩余功能实现计划

> 面向当前工作区实施。每个任务完成后勾选；以 [剩余需求与任务清单](../../PRD/20260924100000_小安翻译v1剩余需求任务清单.md) 的 V1-01～V1-09 为验收依据。

**目标：** 将演示框架升级为 Android 真正可离线翻译、可朗读且具备 Release 和 Play 测试准备的 v1.0。

**架构：** 沿用现有 core/features/services 模块。TranslationService 提供真实设备端实现；语言识别与模型管理通过各自可注入的服务接入 ML Kit。AppController 编排状态与错误，Widget 只展示状态和发送操作。历史 SQLite 数据继续复用，旧模拟记录不丢失。

**技术栈：** Flutter 3.44.9 / Dart 3.12.2、Riverpod、go_router、sqflite；候选插件为 google_mlkit_translation 0.15.1、google_mlkit_language_id 0.15.1、flutter_tts 4.2.5。实际解析结果以 pubspec.lock 和原生构建为准。

**实施边界：** 当前工作区有未提交的核心框架和独立的 .gitignore 改动。保留这些文件和现有历史数据；不重置、清理或批量提交。Android 为发布目标，iOS 模拟器可辅助检查。Play Console 操作与最终密钥需要外部账号或文件。

## 文件职责

| 路径 | 计划职责 |
| --- | --- |
| lib/services/translation/translation_service.dart | 保留翻译接口；演示实现仅用于既有记录与测试 |
| lib/services/translation/mlkit_translation_service.dart | ML Kit Translator 创建、翻译与释放 |
| lib/services/translation/translate_language_code.dart | 应用语言代码与 ML Kit TranslateLanguage 映射 |
| lib/services/language/mlkit_language_detection_service.dart | ML Kit Language ID 与不确定结果处理 |
| lib/services/translation/mlkit_model_service.dart | 模型查询、下载与删除，默认 Wi-Fi |
| lib/features/translate/app_controller.dart | 检测、模型准备、翻译、重试和过期请求控制 |
| lib/features/translate/translation_home_page.dart | 实际阶段、结果与朗读按钮 |
| lib/features/language/offline_models_page.dart | 模型真实状态和手动操作 |
| lib/services/speech/tts_service.dart | 系统 TTS、语言可用性、播放和停止 |
| lib/features/settings/info_page.dart | 正式版本信息、隐私及归因入口 |
| lib/core/database/local_store.dart、lib/features/history/history_store.dart | 历史引擎标记与旧记录兼容 |
| android/app/build.gradle.kts、android/app/src/main/AndroidManifest.xml | Release 参数、TTS 查询和备份边界 |
| test/services/、test/features/、test/widget_test.dart | 新服务映射、控制器状态和页面流程测试 |

## 任务 1：SDK 兼容性与真实翻译服务（V1-01）

- [x] 1.1 写语言映射测试：en/zh 可映射为 ML Kit 语言，未知代码返回不可用；确认旧代码缺少此能力。
- [x] 1.2 在 pubspec.yaml 加入独立的 translation 与 language_id 插件，运行 flutter pub get；只同步相关依赖和 lockfile，不引入整个 google_ml_kit 聚合包。
- [x] 1.3 实现语言代码映射及 MlKitTranslationService：创建 OnDeviceTranslator、调用 translateText、在 finally 中 close；不执行模型下载，保持模型责任独立。
- [x] 1.4 适配器测试覆盖不支持语言和成功/异常路径资源释放；插件通道的真实翻译结果留给 Android 设备验收。
- [x] 1.5 flutter analyze --no-pub、3 项相关 flutter test 通过；flutter build apk --debug --no-pub 成功。当前仍有 share_plus 的未来 Kotlin 兼容警告。

## 任务 2：语言识别和模型服务（V1-02、V1-03）

- [x] 2.1 服务边界测试已写：覆盖短文本、不确定/不支持语言与手选绕过识别。
- [x] 2.2 已实现 MlKitLanguageDetectionService：调用 LanguageIdentifier，处理不确定结果，并释放资源。
- [x] 2.3 模型编排测试已写：覆盖已下载模型、缺失模型和下载失败重试。
- [x] 2.4 已实现 MlKitModelService：真实查询、下载、删除；默认仅 Wi-Fi。
- [ ] 2.5 运行服务测试和 Android Debug 构建；在可用 Android 设备上核查首次下载和已下载查询。没有设备结果时只勾选代码/构建证据。

## 任务 3：翻译状态和首页接线（V1-01、V1-02、V1-03、V1-06）

- [x] 3.1 控制器失败场景测试已写并验证实现。
- [x] 3.2 已扩展 TranslationPhase 和错误状态。
- [x] 3.3 已按识别、模型、翻译顺序接线；生产 provider 默认 ML Kit，测试显式注入 Demo。
- [x] 3.4 已按引擎写入历史，兼容旧模拟记录，结果和历史页显示来源。
- [ ] 3.5 首页阶段、重试和状态展示已接线；全量测试及 Android 设备闭环仍待验证。

## 任务 4：离线语言包页面（V1-04）

- [ ] 4.1 已有模型页下载/删除组件测试；失败后重试测试尚缺。
- [x] 4.2 已将说明页替换为可操作列表，共用 MlKitModelService。
- [ ] 4.3 下载默认仅 Wi-Fi；需要蜂窝网络时显示明确选择。对正在翻译的模型禁用删除。运行 widget 测试与 Android 设备检查。

## 任务 5：TTS 朗读（V1-05）

- [ ] 5.1 服务测试已通过；首页组件测试已写，目前因朗读按钮尚不存在而失败。不可用语言与引擎错误的页面提示测试待补。
- [ ] 5.2 已增加 flutter_tts 依赖、Android TTS_SERVICE queries 和 TtsService；页面退出时的资源释放待接线。
- [ ] 5.3 首页原文/译文增加朗读入口和状态；不增加麦克风或语音输入权限。运行测试、Android Debug 构建和设备朗读验收。

## 任务 6：正式信息、隐私与归因（V1-07）

- [ ] 6.1 用 package_info_plus 显示真实版本号/构建号，避免写死“演示框架”；widget 测试验证可见值。
- [ ] 6.2 根据最终 Manifest、依赖和模型网络行为更新应用内隐私说明，准备公开政策文本与 URL 入口；确认 Android 备份对历史/设置的处理并保持文案一致。
- [ ] 6.3 按 ML Kit 翻译使用指引增加所需归因或提示；审核复制分享文案和模型联网提示。正式政策 URL 由项目所有者确认后启用。
- [ ] 6.4 运行静态分析、widget 测试，并核对安装包 Manifest。

## 任务 7：Android Release 准备（V1-08）

- [ ] 7.1 核定 applicationId、应用名称、图标、versionCode/versionName、minSdk/compileSdk/targetSdk；用 Gradle 或 AAB Manifest 读取最终值，不仅看配置源码。
- [ ] 7.2 配置从本地密钥文件或 CI 秘密读取 Release 签名；项目不保存密码或 jks。无正式密钥时保留可复查的配置和明确阻塞项，不使用 Debug 签名冒充正式 Release。
- [ ] 7.3 运行 flutter build appbundle --release、安装/签名检查和必要的 ML Kit 混淆验证；构建失败时保留日志证据。
- [ ] 7.4 准备商店图文、隐私政策 URL、Data safety 与内容分级核对清单；所有内容以最终构建和真实行为为准。

## 任务 8：Android 真机与 Play 测试（V1-09）

- [ ] 8.1 真机走完整闭环：首次下载、英语↔中文、断网重启再翻译、弱网失败重试、手选语言、长文本、历史/收藏、复制分享、TTS 和深色模式。
- [ ] 8.2 核查 Crash/ANR、APK/AAB 安装与签名、发布版本 Manifest；修复阻断项后重复受影响场景。
- [ ] 8.3 由项目所有者使用 Play Console 发布 Internal Testing，记录安装与设备证据；再安排 Closed Testing、反馈修复、商店资料和 Production Access 材料。当前规则在执行当日复核。
- [ ] 8.4 将每项真实证据与未完成事项回填到需求清单；只有 V1-01～V1-09 全部完成才标记 v1.0 可发布。

## 完成门槛

每项任务通过后更新本计划和需求清单。每轮代码结束运行 dart format lib test、flutter analyze、flutter test；原生插件或发布配置变化时另运行 Android 构建/设备验证。若创建本地提交，先审查待提交差异并使用中文提交信息，不包含 .gitignore 之外的无关用户改动。

## 2026-09-24 交接点

- 用户要求暂停实现并移交其他 agent。以上勾选只代表已有代码和对应测试证据；未勾选项需继续处理，不可当作完成。
- 下一步从任务 5 开始：在 `lib/features/translate/translation_home_page.dart` 接入 `speechServiceProvider`，提供原文/译文朗读、停止、错误反馈和页面退出清理。`test/widget_test.dart` 的“原文和译文使用各自语言朗读并可停止”测试是当前已知红灯，实际报错为找不到“朗读原文”按钮。完成后补齐不可用语言、引擎错误测试。
- 随后完成任务 4.1 的失败重试测试、任务 4.3 的设备验证，再按任务 6→7→8 顺序完成正式信息、隐私、Release AAB 与 Android 真机/Play 测试。任务 2.5、3.5 也要以最新全量测试和真机结果收尾。
- 添加 `flutter_tts` 后尚未重跑 Android 原生构建；ML Kit 的 Android Debug APK 曾构建成功，但真实模型下载、翻译及 TTS 都未在 Android 真机验收。此前全量测试在模型页旧文案断言处失败，该断言已改但未重跑；最终 `dart format`、`flutter analyze`、`flutter test` 仍需执行并记录。
- 工作区保留已有未提交的核心框架和本轮代码；`.gitignore` 是既存的独立改动。当前没有为本轮代码创建提交，也没有推送。
