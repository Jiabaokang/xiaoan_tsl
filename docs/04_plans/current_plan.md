# 小安翻译 v1.0 活跃执行计划 (Current Execution Plan)

> **当前阶段**：v1.0 发布冲刺阶段  
> **前序基线**：核心框架、本地 SQLite 数据库、ML Kit 独立服务、多语种选择及 33 项单元/组件测试已全部通过。`flutter analyze` 保持 0 问题。  
> **执行依据**：严格遵循 `docs/01_prd/prd_v1.0.md` 与 `docs/03_specs/` 各专项规格。

---

## 任务拆解与进度检查清单

### 阶段一：朗读能力接线与生命周期测试（V1-05）
- [x] 1.1 `TtsService` 基础实现与单测（已通过 `test/services/speech/tts_service_test.dart`）
- [ ] 1.2 首页原文与译文朗读按钮接入与状态控制
  - **目标文件**：`lib/features/translate/translation_home_page.dart`
  - **实现要求**：
    - 原文面板操作栏添加“朗读原文”按钮；
    - 译文卡片操作栏添加“朗读译文”按钮；
    - 接入 `speechServiceProvider`，朗读中显示“停止”状态并可点击中断；
    - 页面退出或销毁时调用 `stop()` 释放原生通道。
  - **验收命令**：`flutter test test/widget_test.dart`
  - **预期结果**：用例“原文和译文使用各自语言朗读并可停止”通过。

### 阶段二：离线模型管理完善（V1-04）
- [x] 2.1 离线模型列表查询、手动下载与删除实现（已通过基础单测）
- [ ] 2.2 完善模型删除保护与蜂窝网络下载确认
  - **目标文件**：`lib/features/language/offline_models_page.dart`
  - **实现要求**：
    - 当前翻译选中的源/目标语言模型，在模型管理页禁用“删除”按钮，防止误删导致翻译中断；
    - 检测到非 Wi-Fi 环境时，下载前弹出确认提示。
  - **验收命令**：`flutter test test/widget_test.dart`

### 阶段三：应用合规、关于与隐私信息真实化（V1-07）
- [ ] 3.1 动态读取真实版本与构建号
  - **目标文件**：`lib/features/settings/info_page.dart`
  - **实现要求**：集成 `package_info_plus`，去除写死的“演示框架”字样，显示真实 App 版本。
- [ ] 3.2 隐私政策文案与外部公开入口
  - **目标文件**：`lib/features/settings/info_page.dart`、`docs/01_prd/compliance/privacy_policy.md`
  - **实现要求**：声明本地离线翻译特性，确保 Android 备份配置与文案一致，配置外链跳转。
  - **验收命令**：`flutter test test/widget_test.dart`

### 阶段四：Android Release 签名与 AAB 构建（V1-08）
- [ ] 4.1 分离 Release 签名配置
  - **目标文件**：`android/app/build.gradle.kts`
  - **实现要求**：配置本地读取 `key.properties`，严禁签名证书及明文密码入库。
- [ ] 4.2 执行 Release AAB 构建
  - **验收命令**：`flutter build appbundle --release`
  - **门禁指标**：成功生成 `.aab` 安装包，无 R8/ProGuard 混淆异常与 ML Kit 符号丢失。

### 阶段五：Android 实体设备验收与 Play 轨道发布（V1-09）
- [ ] 5.1 真机覆盖安装验证（严格遵守 `AGENTS.md`，禁止卸载安装）
  - **验收命令**：`adb install -r <apk_path>` 或 `flutter run -d <device_id> --release`
  - **核心验证场景**：
    1. 首次启动离线模型自动下载；
    2. 开启飞行模式（完全断网），验证双向离线翻译与 TTS 朗读；
    3. 历史记录检索、收藏与恢复；
    4. 浅色/深色主题切换；
    5. 重启应用数据完整保留。
- [ ] 5.2 Google Play Closed Testing 测试配置
  - **交付材料**：准备好应用图文、隐私政策公开链接、Data Safety 表格填写材料。

---

## 质量验证红线（Hard Gates）

任何阶段代码交付前，必须无条件执行并全量通过以下门禁：
1. `dart format lib test` （代码格式化无脏改动）
2. `flutter analyze` （必须 0 warning, 0 error）
3. `flutter test` （全量测试绿灯）
