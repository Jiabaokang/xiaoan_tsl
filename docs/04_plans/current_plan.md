# 小安翻译 v1.0 活跃执行计划 (Current Execution Plan)

> **当前阶段**：v1.0 冲刺收官与 Google Play 准入就绪阶段  
> **当前验证**：核心框架、本地 SQLite 数据库、ML Kit 翻译和多语种选择已实现；39 项测试通过，`flutter analyze` 无问题。
> **执行依据**：严格遵循 `docs/01_prd/prd_v1.0.md` 与 `docs/03_specs/` 各专项规格。
> **历史步骤**：[核心框架实施计划](../superpowers/plans/2026-09-24-core-framework.md)与[v1 剩余功能实施计划](../superpowers/plans/2026-09-24-v1-completion.md)保留编写时的任务快照；本文件记录当前进度。

---

## 任务拆解与进度检查清单

### 阶段一：朗读能力接线与生命周期测试（V1-05）
- [x] 1.1 `TtsService` 基础实现与单测（已通过 `test/services/speech/tts_service_test.dart`）
- [x] 1.2 首页原文与译文朗读按钮接入与状态控制
  - **目标文件**：`lib/features/translate/translation_home_page.dart`
  - **验收结果**：原文与译文已配置独立朗读按钮、`_speaking` 状态控制，支持主动停止，退出时释放资源。`test/widget_test.dart` 朗读用例与异常提示全量通过。

### 阶段二：离线模型管理完善（V1-04）
- [x] 2.1 离线模型列表查询、手动下载与删除实现（已通过基础单测）
- [x] 2.2 完善模型删除保护与蜂窝网络下载确认
  - **目标文件**：`lib/features/language/offline_models_page.dart`
  - **验收结果**：翻译进行中（`state.phase.isBusy`）禁用模型删除；非 Wi-Fi 环境下载弹出流量提示确认对话框。Android 实体机已验证真实模型查询与下载状态（中/英已就绪）。

### 阶段三：应用合规、关于与隐私信息真实化（V1-07）
- [x] 3.1 动态读取真实版本与构建号
  - **目标文件**：`lib/features/settings/info_page.dart`
  - **验收结果**：成功接入 `package_info_plus`，实体机实测动态显示 `版本 1.0.0 (1)`。
- [x] 3.2 隐私政策文案与合规声明
  - **目标文件**：`lib/features/settings/info_page.dart`、`docs/01_prd/compliance/privacy_policy.md`
  - **验收结果**：应用内声明离线翻译特性、零服务器上传、关闭系统备份，通过 Widget 测试与实体机浏览。

### 阶段四：Android Release 签名与 AAB 构建（V1-08）
- [x] 4.1 分离 Release 签名配置
  - **目标文件**：`android/app/build.gradle.kts`、`android/app/proguard-rules.pro`
  - **验收结果**：`key.properties` 与签名证书保留在本地并被 Git 忽略；Release 保留 ML Kit 反射创建所需的组件注册器构造函数。
- [x] 4.2 执行 Release AAB 构建
  - **验收结果**：成功构建生产级安装包 `build/app/outputs/bundle/release/app-release.aab`（93.9MB），无 ProGuard/R8 符号丢失错误。

### 阶段五：Android 实体设备验收与 Play 轨道发布（V1-09）
- [x] 5.1 真机覆盖安装验证（严格遵守 `AGENTS.md`，仅覆盖安装）
  - **已连接设备**：`M2002J9E (android-arm64, Android 12, API 31, ID: d5bf1745)`
  - **执行命令**：`adb -s d5bf1745 install -r build/app/outputs/flutter-apk/app-debug.apk`
  - **验证成果（附截图证据）**：
    1. 首页正常启动无崩溃；
    2. 点击示例 "Hello, world!" 自动识别 English 并成功在端侧离线翻译为 "你好，世界！"；
    3. 翻译结果自动写入本地 SQLite 历史，支持去重防抖；
    4. “我的收藏”列表正常过滤已收藏条目；
    5. “离线语言包”页面通过 ML Kit Model Manager 成功读取中/英已下载状态；
    6. “关于”页面动态显示应用版本；
    7. 目标语言选择器屏蔽“自动检测”项，仅允许选择明确语种。
- [ ] 5.2 Google Play Closed Testing 测试配置（需开发者账号拥有者配合）
  - **待办**：在 Play Console 配置 Closed Testing 轨道，邀请 12 名测试人员开始 14 天测试流程。

### 2026-09-25 真机问题修复

- [x] OnePlus 9（Android 14）上短文本 `Hello` 曾被五字符识别门槛拦截；已选原文语言时识别不确定会使用所选语言。修复后的 debug 与 Release 均自动译出“你好”。
- [x] Release 离线语言包曾因 R8 移除 ML Kit 组件注册器构造函数而无法查询；加入保留规则后，覆盖安装的 Release 能显示语言选择列表及离线模型状态。
- [x] 全量 `flutter test` 39 项通过，`flutter analyze` 无问题；两次安装均使用 `adb install -r`，未卸载或清除应用数据。

---

## 质量验证红线（Hard Gates）

当前工程已通过以下验证：
1. `dart format lib test`：代码格式规范；
2. `flutter analyze`：**0 warning, 0 error**；
3. `flutter test`：**全量 39 项单元/组件/状态机测试通过**；
4. `flutter build apk --debug`：构建成功，并在真实 Android 实体机覆盖安装验证；
5. `flutter build apk --release`：构建成功，并在 OnePlus 9 覆盖安装验证短文本翻译及两种语言列表；先前构建的 AAB 尚未按本次修复重新验证。
