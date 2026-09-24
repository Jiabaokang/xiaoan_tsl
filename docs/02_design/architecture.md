# 小安翻译 (Xiaoan TSL) 基础架构与系统设计

> **状态**：Active / SSOT  
> **适用版本**：v1.0  
> **技术栈**：Flutter (Dart ^3.12.2) / Android (API 23+)  

---

## 1. 架构原则与分层模型

小安翻译遵循 **清晰分层（Layered Clean Architecture）** 与 **单向数据流（Unidirectional Data Flow）** 原则：

```text
┌────────────────────────────────────────────────────────┐
│             UI 层 (Presentation Layer)                 │
│      lib/features/*_page.dart, widgets                 │
│   - 仅负责接收 UI 事件与观察 Riverpod 状态渲染界面       │
└───────────────────────────┬────────────────────────────┘
                            │ 发送意图 (User Intents)
                            ▼
┌────────────────────────────────────────────────────────┐
│           应用状态层 (State / Controller Layer)        │
│      lib/features/translate/app_controller.dart        │
│   - 维护业务状态机 (TranslationState)                  │
│   - 编排下层服务，处理并发取消、防抖与请求过期机制     │
└───────────────┬───────────────────────────┬────────────┘
                │ 依赖抽象服务               │ 依赖存储仓库
                ▼                           ▼
┌───────────────────────────────┐ ┌──────────────────────┐
│  核心服务层 (Services Layer)  │ │ 本地存储层 (Store)   │
│  lib/services/                │ │ lib/core/database/   │
│  - TranslationService (MLKit) │ │ - LocalStore         │
│  - LanguageDetectionService   │ │ - SQLite (sqflite)   │
│  - ModelManagementService     │ └──────────────────────┘
│  - SpeechService (TTS)        │
│  - SharingService             │
└───────────────────────────────┘
```

---

## 2. 代码组织目录结构

```text
lib/
├── main.dart                          # 顶层入口：初始化数据库、挂载 ProviderScope
├── app.dart                           # MaterialApp.router 挂载、全局主题绑定
├── core/                              # 跨特性通用基础设施
│   ├── database/                      # SQLite 数据库包装与注入
│   │   ├── database_provider.dart
│   │   └── local_store.dart
│   ├── network/                       # 受控网络客户端 (Dio)
│   │   └── dio_provider.dart
│   ├── router/                        # go_router 配置与导航守卫
│   │   └── app_router.dart
│   ├── theme/                         # 浅色/深色主题定义
│   │   └── app_theme.dart
│   └── widgets/                       # 全局共用视觉组件 (如 AppPanel)
│       └── app_panel.dart
├── features/                          # 垂直业务能力划分
│   ├── translate/                     # 翻译首页、Controller、状态
│   ├── language/                      # 语言选择、离线模型下载管理
│   ├── history/                       # 历史记录列表、搜索与删除
│   ├── favorites/                     # 收藏列表 (复用历史基础能力)
│   └── settings/                      # 设置中心、关于与隐私
└── services/                          # 外部平台能力与 SDK 适配层
    ├── translation/                   # ML Kit 翻译实现与 Provider
    ├── language/                      # ML Kit 语种识别实现
    ├── speech/                        # 系统 TTS 朗读实现
    └── sharing/                       # 剪贴板与原生分享面板封装
```

---

## 3. 技术选型矩阵

| 责任领域 | 选型组件 | 选型考量与使用规范 |
|---|---|---|
| **跨平台框架** | Flutter SDK (Dart ^3.12.2) | 官方推荐稳定工具链，支持 Material 3 |
| **状态管理** | `flutter_riverpod: ^3.4.3` | 采用 `Notifier` / `AsyncNotifier`，首版不引入代码生成器以简化构建 |
| **路由导航** | `go_router: ^18.0.1` | 声明式路由，支持 Query 参数传递与深链接（DeepLink）无缝恢复 |
| **本地存储** | `sqflite: ^2.4.4` + `path` | 兼顾 Android SDK 23 最低支持与关系型历史搜索、收藏标记过滤需求 |
| **离线翻译** | `google_mlkit_translation: ^0.15.1` | Google 原生设备端模型，零服务器依赖，高准确度 |
| **语言识别** | `google_mlkit_language_id: ^0.15.1` | 原生端侧识别，支持主流语种自动辨析 |
| **语音合成** | `flutter_tts: ^4.2.5` | 纯调用系统 TTS 引擎，不申请麦克风权限 |
| **系统分享** | `share_plus: ^11.1.0` / Clipboard | 调起原生分享 Intent，复制使用 Flutter 原生 Clipboard |
| **信息读取** | `package_info_plus: ^10.2.1` | 动态读取编译期的真实版本号与构建号 |
| **受控网络** | `dio: ^5.11.1` | 预置统一 HTTP 拦截与超时控制；v1.0 不发起业务翻译网络请求 |

---

## 4. 关键架构决策记录 (ADR)

### ADR-01：选用独立 ML Kit 插件而非聚合全家桶
* **背景**：pub.dev 提供了聚合包 `google_ml_kit` 以及各个能力独立的子插件。
* **决策**：严格使用 `google_mlkit_translation` 与 `google_mlkit_language_id` 独立子插件。
* **原因**：聚合包会打包视觉、人脸、条码等所有原生 C++ 动态库，导致 APK 体积激增 40MB+，并向应用清单强行插入相机等敏感权限声明，对纯翻译工具造成极高的 Google Play 审核风险。

### ADR-02：统一采用 SQLite (sqflite) 放弃 SharedPreferences / Drift
* **背景**：早期规划同时提到了 `shared_preferences` 与 `drift`。
* **决策**：统一使用原生的 `sqflite` 建立一个单库 `xiaoan_tsl.db`。历史记录表存储文本历史，配置表 `app_settings` 以 Key-Value 方式存储用户偏好（主题模式、默认语言）。
* **原因**：
  1. `shared_preferences` 最新版要求 Android SDK 24+，打破了 `minSdk 23` 约束；
  2. 避免同时维护两套持久化引擎，保证数据库备份、迁移和状态更新的事务一致性。

### ADR-03：受控网络客户端与离线翻译绝对隔离
* **背景**：工程中引入了 `dio` 作为基础设施。
* **决策**：v1.0 的所有翻译和模型下载由 ML Kit 原生平台接管，**禁止**在 Dio 中配置任何自建的后端翻译接口或伪造的健康检查请求。
* **原因**：遵守“零服务器投入、零隐私泄露风险”的纯离线定位，避免因虚构接口产生网络超时或审核质询。

---

## 5. 安全与隐私架构

1. **零数据外流**：用户输入的任何字符均不经过 HTTP 传输，只写入应用沙盒内的 SQLite 数据库文件。
2. **Android 备份保护**：在 `AndroidManifest.xml` 中将本地数据库与设置列入受控备份清单，保障换机或升级时的数据一致性。
3. **敏感凭据脱敏**：正式签名证书（Keystore）、发布密码严禁硬编码或直接提交至 Git 仓库，统一通过本地 `key.properties` 或 CI 密钥注入。
