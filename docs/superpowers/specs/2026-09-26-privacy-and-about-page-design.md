# 隐私政策与关于小安翻译重构及第三方库跳转设计规范

## 1. 目标与背景

当前设置模块中的“隐私政策”与“关于小安翻译”共用单一 `InfoPage`，以纯文本简单平铺段落，视觉体验与层次结构较为简陋，缺乏现代移动应用的精致度与品牌辨识度；且未提供应用所依赖的第三方开源生态声明与包索引。

本设计基于主流移动应用最佳实践与小安翻译“设备端离线推理、零数据上传、权限最小化”的核心定位，进行以下改造：
1. **重构隐私政策（`PrivacyPolicyPage`）**：采用模块化结构化卡片排版，清晰展示生效日期、数据存储边界、本地模型推理、语音与分享安全、零敏感权限声明及诊断数据，底部提供醒目的外部完整政策直达入口；
2. **重构关于小安翻译（`AboutPage`）**：突出品牌图标与中英文名称、版本徽章、产品核心定位与三大核心特性，并提供技术支持入口与版权归属声明；
3. **新增第三方开源库专属页面（`OpenSourceLicensesPage`）**：收录项目 `pubspec.yaml` 中使用的 13 个核心运行时依赖，展示包名、版本、职责说明，并支持点击调用外部浏览器直达国内镜像地址 `https://pub-web.flutter-io.cn/packages/<package_name>`；
4. **全面适配暗色模式与中英双语国际化**，严格遵循仓库代码规范与中文注释要求。

---

## 2. 架构设计与路由规划

### 2.1 模块组织与职责划分

所有页面按应用规范组织在 `lib/features/settings/` 目录下：
- `lib/features/settings/privacy_policy_page.dart`：定义 `PrivacyPolicyPage`，负责结构化隐私条款呈现与外部政策跳转；
- `lib/features/settings/about_page.dart`：定义 `AboutPage`，负责品牌标识、版本展示、特性卡片及各二级入口引导；
- `lib/features/settings/open_source_licenses_page.dart`：定义 `OpenSourceLicensesPage`，负责开源依赖模型声明与 pub-web 镜像跳转；
- `lib/features/settings/info_page.dart`：保留作为兼容层，重新导出新页面并提供原有类型别名与 `privacyPolicyUrl` 常量，避免破坏旧有代码和测试用例。

### 2.2 路由配置（`lib/core/router/app_router.dart`）

- `/privacy` $\rightarrow$ `PrivacyPolicyPage`
- `/about` $\rightarrow$ `AboutPage`
- `/about/dependencies` $\rightarrow$ `OpenSourceLicensesPage`

---

## 3. 详细页面交互与组件设计

### 3.1 隐私政策页面（`PrivacyPolicyPage`）

- **顶部信息卡片**：
  - 生效日期徽章：`生效日期：2026年9月`（英文 `Effective Date: September 2026`）；
  - 核心承诺：强调应用完全无需注册登录、所有翻译与存储仅在本地执行。
- **五大结构化卡片（基于 `AppPanel`）**：
  1. 📱 **数据存储与设备边界**：文本输入、翻译历史、收藏与偏好设置均保存在本地 SQLite 数据库中；Android 版本已显式关闭系统级云端自动备份（`allowBackup=false`）。
  2. 🧠 **离线模型与网络隔离**：语言识别与机器翻译均通过 Google ML Kit 离线模型在设备本地芯片推理完成；翻译文本绝不上传自有或第三方服务器；模型下载消耗网络流量均有明确提示。
  3. 🔊 **语音与系统分享安全**：语音朗读仅调用系统底层已安装的 TTS 语音引擎；复制与分享仅调用系统原生剪贴板及分享面板。
  4. 🛡️ **权限最小化声明**：严格遵循最小必要权限，不申请麦克风、相机、地理位置、通讯录等任何敏感权限。
  5. 📊 **诊断数据与第三方说明**：说明 Google ML Kit 可能会上报设备及性能指标等基础诊断数据，并附带公开隐私政策说明。
- **底部外链卡片**：
  - 包含图标、地址预览与操作按钮：“查看完整在线隐私政策”，点击使用外部应用调用 `launchUrl(..., mode: LaunchMode.externalApplication)` 打开 `https://jbksy.cn/xiaoan-privacy.html`，遇到异常时显示 SnackBar 友好提示。

### 3.2 关于小安翻译（`AboutPage`）

- **顶部品牌 Header**：
  - 应用 Logo：圆角磨砂卡片容器内置 `assets/branding/app_icon_128.png`，高宽 72×72 pt；
  - 应用名称：大号粗体标题 `小安翻译`（英文 `Xiaoan Translate`）；
  - 属性标签：`测试版 · 设备端离线` / `Beta · On-Device`；
  - 动态版本：通过 `PackageInfo.fromPlatform()` 读取并渲染 `版本 1.0.0 (2003)`。
- **产品简介卡片（`AppPanel`）**：
  - 描述“轻量、私密、纯粹的设备端离线翻译工具”，阐明产品定位。
- **核心特性卡片组（`AppPanel`）**：
  - ⚡ **离线双向翻译**：Google ML Kit 离线多语种模型；
  - 🔒 **隐私无痕存储**：本地 SQLite 隔离，关闭云备份；
  - 🔊 **本地语音朗读**：系统级语音合成引擎直连。
- **技术支持与扩展入口（`AppPanel`）**：
  - `ListTile`：“第三方开源库与组件”，显示副标题“查看本应用使用的 13 个核心开源依赖”，点击导航至 `/about/dependencies`；
  - `ListTile`：“隐私政策”，点击导航至 `/privacy`。
- **底部版权 Footer**：
  - 标注文案：`Copyright © 2026 小安翻译 Team. All rights reserved.`

### 3.3 第三方开源库专属页面（`OpenSourceLicensesPage`）

- **数据模型定义**：
  ```dart
  class PackageDependency {
    final String name;
    final String version;
    final String descriptionZh;
    final String descriptionEn;
  }
  ```
- **收录的核心依赖列表（13 个）**：
  1. `flutter_riverpod` (^3.4.3) — 响应式状态管理与依赖注入
  2. `go_router` (^18.0.1) — 声明式路由导航
  3. `google_mlkit_translation` (^0.15.1) — 设备端离线语言机器翻译
  4. `google_mlkit_language_id` (^0.15.1) — 设备端语言自动识别
  5. `sqflite` (^2.4.4) — 设备端 SQLite 关系数据库
  6. `flutter_tts` (^4.2.5) — 设备端文字转语音合成
  7. `dio` (^5.11.1) — 网络传输与模型下载管理
  8. `path_provider` (^2.1.5) — 本地文件系统沙盒路径
  9. `package_info_plus` (^8.3.0) — 原生包信息与版本读取
  10. `url_launcher` (^6.3.1) — 外部应用与网页链接跳转
  11. `share_plus` (^11.1.0) — 系统级分享面板
  12. `flutter_native_splash` (^2.4.8) — 原生冷启动闪屏管理
  13. `cupertino_icons` (^1.0.8) — 辅助界面图标
- **交互与跳转**：
  - 每个依赖卡片展示包名、版本号标签、功能描述与外部链接图标；
  - 点击卡片或右侧链接按钮，自动打开对应镜像：
    `https://pub-web.flutter-io.cn/packages/<name>`
  - 链接打开失败时，以 SnackBar 提示用户。

---

## 4. 国际化与文案契约（`AppLocalizations`）

在 `AppLocalizations` 中新增以下字段，并在 `AppLocalizationsZh` 与 `AppLocalizationsEn` 中对齐实现：
- 隐私政策相关：
  - `privacyEffectiveDate`
  - `privacySubtitle`
  - `privacySection1Title` / `privacySection1Content`
  - `privacySection2Title` / `privacySection2Content`
  - `privacySection3Title` / `privacySection3Content`
  - `privacySection4Title` / `privacySection4Content`
  - `privacySection5Title` / `privacySection5Content`
  - `viewFullPrivacyPolicy`
- 关于页面相关：
  - `aboutTagline`
  - `aboutFeatureOfflineTitle` / `aboutFeatureOfflineDesc`
  - `aboutFeaturePrivacyTitle` / `aboutFeaturePrivacyDesc`
  - `aboutFeatureTtsTitle` / `aboutFeatureTtsDesc`
  - `openSourceDependenciesLabel`
  - `openSourceDependenciesSubtitle`
  - `openSourceDependenciesTitle`
  - `openSourcePageNotice`
  - `copyrightNotice`

---

## 5. 测试与验证策略

1. **向下兼容保证**：
   - 保留 `test/widget_test.dart` 中现有对隐私政策文本（如“关闭系统备份”、“不申请麦克风”、“https://jbksy.cn/xiaoan-privacy.html”）和关于页面文本（如“版本 1.0.0 (1)”、“Google ML Kit”）的断言测试，确保无缝通过；
2. **新增针对性测试**：
   - 验证从关于页面点击“第三方开源库与组件”成功导航至 `/about/dependencies` 并渲染 13 个库列表；
   - 验证第三方库点击能正确构造镜像跳转链接；
   - 验证深浅色模式下的正确渲染与中英文文案显示；
3. **验证基线**：全量单元与组件测试通过，`flutter analyze` 零警告零错误。
