# 隐私政策、关于页面与第三方开源库跳转实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 参考主流移动应用设计，重构小安翻译的隐私政策页面与关于页面，采用结构化卡片排版呈现核心离线能力与隐私保障，并新增独立的第三方开源依赖列表页，支持点击跳转至 `https://pub-web.flutter-io.cn/packages/<name>`。

**架构：** 在 `lib/features/settings/` 目录下将原 `info_page.dart` 单一类解耦为 `PrivacyPolicyPage`、`AboutPage` 与 `OpenSourceLicensesPage`，保留 `info_page.dart` 作为兼容层；在 `app_router.dart` 中注册独立路由 `/privacy`、`/about`、`/about/dependencies`；并在 `AppLocalizations` 中新增中英双语国际化文案契约。

**技术栈：** Flutter SDK, Material 3, Riverpod, GoRouter, url_launcher, package_info_plus, flutter_test.

---

### 文件变更清单
- `lib/l10n/app_localizations.dart`：扩展隐私政策、关于特性卡片与第三方开源库文案契约及中英文实现；
- `lib/features/settings/open_source_licenses_page.dart`：新建第三方依赖展示与 pub-web 镜像跳转页面；
- `lib/features/settings/privacy_policy_page.dart`：新建结构化卡片式隐私政策页面；
- `lib/features/settings/about_page.dart`：新建品牌化关于小安翻译主页面；
- `lib/features/settings/info_page.dart`：改造为重导出与兼容垫片；
- `lib/core/router/app_router.dart`：注册 `/about/dependencies` 及独立页面路由；
- `test/features/settings/info_pages_test.dart`：针对关于、第三方库及隐私政策页面的单元与组件测试；
- `test/widget_test.dart`：确保全局既有设置流与文本断言回归通过；
- `docs/CHANGELOG.md`：记录实现过程与验证结果。

---

### 任务 1：扩展国际化文案契约与中英双语支持

**文件：**
- 修改：`lib/l10n/app_localizations.dart`
- 测试：`test/features/settings/info_pages_test.dart`

- [ ] **步骤 1：编写国际化文案断言测试**

在 `test/features/settings/info_pages_test.dart` 中添加测试用例，验证中英文本地化实例包含新增的关于、特性和第三方开源库等字段：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaoan_tsl/l10n/app_localizations.dart';

void main() {
  test('AppLocalizations 包含新增的关于和第三方库文案', () {
    const zh = AppLocalizationsZh();
    const en = AppLocalizationsEn();

    expect(zh.aboutTagline, isNotEmpty);
    expect(en.aboutTagline, isNotEmpty);
    expect(zh.openSourceDependenciesLabel, '第三方开源库与组件');
    expect(en.openSourceDependenciesLabel, 'Open Source Licenses & Dependencies');
    expect(zh.privacyEffectiveDate, contains('2026'));
    expect(en.privacyEffectiveDate, contains('2026'));
  });
}
```

- [ ] **步骤 2：运行测试验证失败**

运行：`flutter test test/features/settings/info_pages_test.dart`
预期：编译失败，提示 `aboutTagline`、`openSourceDependenciesLabel` 等 getter 未定义。

- [ ] **步骤 3：在 `AppLocalizations` 中添加字段并在中英文子类中实现**

在 `lib/l10n/app_localizations.dart` 抽象类中声明：
```dart
  String get privacyEffectiveDate;
  String get privacySubtitle;
  String get privacySection1Title;
  String get privacySection1Content;
  String get privacySection2Title;
  String get privacySection2Content;
  String get privacySection3Title;
  String get privacySection3Content;
  String get privacySection4Title;
  String get privacySection4Content;
  String get privacySection5Title;
  String get privacySection5Content;
  String get viewFullPrivacyPolicy;

  String get aboutTagline;
  String get aboutFeatureOfflineTitle;
  String get aboutFeatureOfflineDesc;
  String get aboutFeaturePrivacyTitle;
  String get aboutFeaturePrivacyDesc;
  String get aboutFeatureTtsTitle;
  String get aboutFeatureTtsDesc;
  String get openSourceDependenciesLabel;
  String get openSourceDependenciesSubtitle;
  String get openSourceDependenciesTitle;
  String get openSourcePageNotice;
  String get copyrightNotice;
```

在 `AppLocalizationsZh` 与 `AppLocalizationsEn` 中分别提供对应的中英文文案实现。

- [ ] **步骤 4：运行测试验证通过**

运行：`flutter test test/features/settings/info_pages_test.dart`
预期：PASS。

- [ ] **步骤 5：提交代码**

```bash
git add lib/l10n/app_localizations.dart test/features/settings/info_pages_test.dart
git commit -m "feat(l10n): 增加关于页面与第三方开源库国际化文案"
```

---

### 任务 2：实现第三方开源库专属页面 `OpenSourceLicensesPage`

**文件：**
- 创建：`lib/features/settings/open_source_licenses_page.dart`
- 测试：`test/features/settings/info_pages_test.dart`

- [ ] **步骤 1：编写第三方开源库页面组件与链接生成测试**

在 `test/features/settings/info_pages_test.dart` 中追加测试用例，验证 13 个包正常渲染，且镜像 URL 符合 `https://pub-web.flutter-io.cn/packages/<name>`：

```dart
  testWidgets('OpenSourceLicensesPage 渲染 13 个核心依赖且具备镜像跳转属性', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        localizationsDelegates: [AppLocalizations.delegate],
        supportedLocales: AppLocalizations.supportedLocales,
        home: OpenSourceLicensesPage(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('flutter_riverpod'), findsOneWidget);
    expect(find.text('go_router'), findsOneWidget);
    expect(find.text('google_mlkit_translation'), findsOneWidget);
    expect(find.text('google_mlkit_language_id'), findsOneWidget);
    expect(find.text('sqflite'), findsOneWidget);
    expect(find.text('flutter_tts'), findsOneWidget);
    expect(find.byType(ListTile), findsNWidgets(13));
  });
```

- [ ] **步骤 2：运行测试验证失败**

运行：`flutter test test/features/settings/info_pages_test.dart`
预期：FAIL，提示 `OpenSourceLicensesPage` 未定义。

- [ ] **步骤 3：编写 `OpenSourceLicensesPage` 及其元数据模型**

在 `lib/features/settings/open_source_licenses_page.dart` 中：
- 定义 `PackageDependency` 实体包含包名、版本、中英文职责简介；
- 列出 13 个核心库元数据；
- 编写 `OpenSourceLicensesPage` StatelessWidget，基于 `ListView.separated` 或 `AppPanel` 渲染；
- 点击条目时构造 `https://pub-web.flutter-io.cn/packages/${pkg.name}` 并通过 `launchUrl` 打开；
- 包含完备中文注释与暗色模式适配。

- [ ] **步骤 4：运行测试验证通过**

运行：`flutter test test/features/settings/info_pages_test.dart`
预期：PASS。

- [ ] **步骤 5：提交代码**

```bash
git add lib/features/settings/open_source_licenses_page.dart test/features/settings/info_pages_test.dart
git commit -m "feat(settings): 实现第三方开源依赖列表与 pub-web 镜像跳转页"
```

---

### 任务 3：实现结构化卡片式隐私政策页面 `PrivacyPolicyPage`

**文件：**
- 创建：`lib/features/settings/privacy_policy_page.dart`
- 测试：`test/features/settings/info_pages_test.dart`

- [ ] **步骤 1：编写隐私政策卡片渲染与外部链接测试**

在 `test/features/settings/info_pages_test.dart` 中追加测试用例，验证 5 个分段卡片、生效日期与完整在线政策外链按钮：

```dart
  testWidgets('PrivacyPolicyPage 渲染 5 个结构化卡片和外链按钮', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        localizationsDelegates: [AppLocalizations.delegate],
        supportedLocales: AppLocalizations.supportedLocales,
        home: PrivacyPolicyPage(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('关闭系统备份'), findsOneWidget);
    expect(find.textContaining('不申请麦克风'), findsOneWidget);
    expect(find.text('https://jbksy.cn/xiaoan-privacy.html'), findsOneWidget);
  });
```

- [ ] **步骤 2：运行测试验证失败**

运行：`flutter test test/features/settings/info_pages_test.dart`
预期：FAIL，提示 `PrivacyPolicyPage` 未定义。

- [ ] **步骤 3：编写 `PrivacyPolicyPage` 实现**

在 `lib/features/settings/privacy_policy_page.dart` 中：
- 使用 `AppPanel` 分隔顶部概览、5 个核心章节卡片与底部外链操作卡片；
- 保留 `privacyPolicyUrl = 'https://jbksy.cn/xiaoan-privacy.html'`；
- 包含完备中文类/方法注释，适配浅色与深色模式。

- [ ] **步骤 4：运行测试验证通过**

运行：`flutter test test/features/settings/info_pages_test.dart`
预期：PASS。

- [ ] **步骤 5：提交代码**

```bash
git add lib/features/settings/privacy_policy_page.dart test/features/settings/info_pages_test.dart
git commit -m "feat(settings): 实现结构化卡片式隐私政策页面"
```

---

### 任务 4：实现品牌化关于小安翻译页面 `AboutPage`

**文件：**
- 创建：`lib/features/settings/about_page.dart`
- 测试：`test/features/settings/info_pages_test.dart`

- [ ] **步骤 1：编写关于页面品牌图标、特性卡片及跳转入口测试**

在 `test/features/settings/info_pages_test.dart` 中追加测试用例：

```dart
  testWidgets('AboutPage 展示应用图标、版本号及三大核心特性卡片', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        localizationsDelegates: [AppLocalizations.delegate],
        supportedLocales: AppLocalizations.supportedLocales,
        home: AboutPage(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(Image), findsOneWidget);
    expect(find.text('小安翻译'), findsOneWidget);
    expect(find.textContaining('Google ML Kit'), findsWidgets);
    expect(find.text('第三方开源库与组件'), findsOneWidget);
  });
```

- [ ] **步骤 2：运行测试验证失败**

运行：`flutter test test/features/settings/info_pages_test.dart`
预期：FAIL，提示 `AboutPage` 未定义。

- [ ] **步骤 3：编写 `AboutPage` 实现**

在 `lib/features/settings/about_page.dart` 中：
- Header 渲染应用图标 `assets/branding/app_icon_128.png`、版本号与类型 Chip；
- 核心特性卡片展示离线模型、隐私存储和系统语音朗读；
- 底部提供进入 `OpenSourceLicensesPage`（路由 `/about/dependencies`）与隐私政策的入口；
- 底部显示版权声明。

- [ ] **步骤 4：运行测试验证通过**

运行：`flutter test test/features/settings/info_pages_test.dart`
预期：PASS。

- [ ] **步骤 5：提交代码**

```bash
git add lib/features/settings/about_page.dart test/features/settings/info_pages_test.dart
git commit -m "feat(settings): 实现品牌化关于小安翻译主页面"
```

---

### 任务 5：路由集成、`InfoPage` 兼容层改造与全量回归验证

**文件：**
- 修改：`lib/features/settings/info_page.dart`
- 修改：`lib/core/router/app_router.dart`
- 验证：`test/widget_test.dart`
- 文档：`docs/CHANGELOG.md`

- [ ] **步骤 1：在 `app_router.dart` 中注册新路由与更新现有路由**

将 `/privacy` 映射到 `PrivacyPolicyPage`，`/about` 映射到 `AboutPage`，新增 `/about/dependencies` 映射到 `OpenSourceLicensesPage`。

- [ ] **步骤 2：改造 `lib/features/settings/info_page.dart` 为兼容层**

保留 `enum InfoKind`、`privacyPolicyUrl` 和 `InfoPage`，内部在 `build` 中根据 `kind` 转发到 `PrivacyPolicyPage` 或 `AboutPage`，保证任何旧调用方与深链无破坏。

- [ ] **步骤 3：运行全量自动化测试**

运行：`flutter test`
预期：全量测试（包括现有 `test/widget_test.dart` 中的关于与隐私页面断言）全部通过。

- [ ] **步骤 4：执行静态代码分析与格式化**

运行：`dart format lib test` 以及 `flutter analyze`
预期：零警告、零错误、代码格式规范。

- [ ] **步骤 5：更新 `docs/CHANGELOG.md` 并提交代码**

在 `docs/CHANGELOG.md` 顶部记录实施结果，并 commit。
