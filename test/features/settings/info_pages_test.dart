import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:xiaoan_tsl/core/router/app_router.dart';
import 'package:xiaoan_tsl/features/settings/about_page.dart';
import 'package:xiaoan_tsl/features/settings/info_page.dart'
    show InfoKind, InfoPage;
import 'package:xiaoan_tsl/features/settings/open_source_licenses_page.dart';
import 'package:xiaoan_tsl/features/settings/privacy_policy_page.dart';
import 'package:xiaoan_tsl/l10n/app_localizations.dart';

const _testLocalizationsDelegates = [
  AppLocalizations.delegate,
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
];

void main() {
  setUpAll(() {
    PackageInfo.setMockInitialValues(
      appName: '小安翻译',
      packageName: 'com.jbk.xiaoants',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  test('AppLocalizations 包含新增的关于和第三方库文案', () {
    const zh = AppLocalizationsZh();
    const en = AppLocalizationsEn();

    expect(zh.aboutTagline, isNotEmpty);
    expect(en.aboutTagline, isNotEmpty);
    expect(zh.openSourceDependenciesLabel, '第三方开源库与组件');
    expect(
      en.openSourceDependenciesLabel,
      'Open Source Licenses & Dependencies',
    );
    expect(zh.privacyEffectiveDate, contains('2026'));
    expect(en.privacyEffectiveDate, contains('2026'));
  });

  test('中英文本地化所有新增关于和隐私字段均不为空', () {
    const zh = AppLocalizationsZh();
    const en = AppLocalizationsEn();

    for (final loc in [zh, en]) {
      expect(loc.privacyEffectiveDate, isNotEmpty);
      expect(loc.privacySubtitle, isNotEmpty);
      expect(loc.privacySection1Title, isNotEmpty);
      expect(loc.privacySection1Content, isNotEmpty);
      expect(loc.privacySection2Title, isNotEmpty);
      expect(loc.privacySection2Content, isNotEmpty);
      expect(loc.privacySection3Title, isNotEmpty);
      expect(loc.privacySection3Content, isNotEmpty);
      expect(loc.privacySection4Title, isNotEmpty);
      expect(loc.privacySection4Content, isNotEmpty);
      expect(loc.privacySection5Title, isNotEmpty);
      expect(loc.privacySection5Content, isNotEmpty);
      expect(loc.viewFullPrivacyPolicy, isNotEmpty);
      expect(loc.aboutTagline, isNotEmpty);
      expect(loc.aboutFeatureOfflineTitle, isNotEmpty);
      expect(loc.aboutFeatureOfflineDesc, isNotEmpty);
      expect(loc.aboutFeaturePrivacyTitle, isNotEmpty);
      expect(loc.aboutFeaturePrivacyDesc, isNotEmpty);
      expect(loc.aboutFeatureTtsTitle, isNotEmpty);
      expect(loc.aboutFeatureTtsDesc, isNotEmpty);
      expect(loc.openSourceDependenciesLabel, isNotEmpty);
      expect(loc.openSourceDependenciesSubtitle, isNotEmpty);
      expect(loc.openSourceDependenciesTitle, isNotEmpty);
      expect(loc.openSourcePageNotice, isNotEmpty);
      expect(loc.copyrightNotice, isNotEmpty);
    }
  });

  testWidgets('OpenSourceLicensesPage 渲染 13 个核心依赖且具备镜像跳转属性', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        localizationsDelegates: _testLocalizationsDelegates,
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

  test('PackageDependency 元数据完整且包含正确的 pub-web 镜像地址', () {
    expect(corePackageDependencies.length, 13);
    for (final pkg in corePackageDependencies) {
      expect(pkg.name, isNotEmpty);
      expect(pkg.version, startsWith('^'));
      expect(pkg.descriptionZh, isNotEmpty);
      expect(pkg.descriptionEn, isNotEmpty);
      expect(
        pkg.mirrorUrl,
        'https://pub-web.flutter-io.cn/packages/${pkg.name}',
      );
    }
  });

  testWidgets('OpenSourceLicensesPage 在英文环境下渲染英文描述和标题', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        locale: Locale('en'),
        localizationsDelegates: _testLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: OpenSourceLicensesPage(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Open Source Licenses & Dependencies'), findsOneWidget);
    expect(find.textContaining('Reactive state management'), findsOneWidget);
  });

  testWidgets('OpenSourceLicensesPage 点击依赖项触发正确的镜像 URL 打开', (tester) async {
    Uri? launchedUri;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: _testLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: OpenSourceLicensesPage(
          urlLauncher: (uri, {mode = LaunchMode.platformDefault}) async {
            launchedUri = uri;
            return true;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('flutter_riverpod'));
    await tester.pumpAndSettle();

    expect(
      launchedUri.toString(),
      'https://pub-web.flutter-io.cn/packages/flutter_riverpod',
    );
  });

  testWidgets('OpenSourceLicensesPage 打开链接失败时显示错误提示 SnackBar', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: _testLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: OpenSourceLicensesPage(
          urlLauncher: (uri, {mode = LaunchMode.platformDefault}) async =>
              false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('go_router'));
    await tester.pumpAndSettle();

    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.text('无法打开网页，请在浏览器输入页面上的网址'), findsOneWidget);
  });

  testWidgets('OpenSourceLicensesPage 在暗色模式下正常渲染', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        locale: const Locale('zh'),
        localizationsDelegates: _testLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const OpenSourceLicensesPage(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('第三方开源库与组件'), findsOneWidget);
    expect(find.byType(ListTile), findsNWidgets(13));
  });

  testWidgets('PrivacyPolicyPage 渲染 5 个结构化卡片和外链按钮', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        locale: Locale('zh'),
        localizationsDelegates: _testLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: PrivacyPolicyPage(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('生效日期：2026年9月'), findsOneWidget);
    expect(find.textContaining('关闭系统备份'), findsOneWidget);
    expect(find.textContaining('不申请麦克风'), findsOneWidget);
    expect(find.text('https://jbksy.cn/xiaoan-privacy.html'), findsOneWidget);
    expect(find.text('查看完整在线隐私政策'), findsOneWidget);
    expect(find.text('数据存储与设备边界'), findsOneWidget);
    expect(find.text('离线模型与网络隔离'), findsOneWidget);
    expect(find.text('语音与系统分享安全'), findsOneWidget);
    expect(find.text('权限最小化声明'), findsOneWidget);
    expect(find.text('诊断数据与第三方说明'), findsOneWidget);
  });

  testWidgets('PrivacyPolicyPage 在英文环境下渲染英文各卡片内容', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        locale: Locale('en'),
        localizationsDelegates: _testLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: PrivacyPolicyPage(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Effective Date: September 2026'), findsOneWidget);
    expect(find.text('Data Storage & Device Boundary'), findsOneWidget);
    expect(find.text('Offline Models & Network Isolation'), findsOneWidget);
    expect(find.text('Speech & System Sharing Security'), findsOneWidget);
    expect(find.text('Minimal Permissions Declaration'), findsOneWidget);
    expect(find.text('Diagnostic Data & Third-Party Notice'), findsOneWidget);
    expect(find.text('View Complete Online Privacy Policy'), findsOneWidget);
    expect(
        find.text('https://jbksy.cn/xiaoan-privacy-en.html'), findsOneWidget);
  });

  testWidgets('PrivacyPolicyPage 英文界面打开英文政策网页', (tester) async {
    Uri? launchedUri;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: _testLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: PrivacyPolicyPage(
          urlLauncher: (uri, {mode = LaunchMode.platformDefault}) async {
            launchedUri = uri;
            return true;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    final button = find.text('View Complete Online Privacy Policy');
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();

    expect(launchedUri.toString(), 'https://jbksy.cn/xiaoan-privacy-en.html');
  });

  testWidgets('PrivacyPolicyPage 点击外链触发外部浏览器打开在线隐私政策', (tester) async {
    Uri? launchedUri;
    LaunchMode? launchMode;

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: _testLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: PrivacyPolicyPage(
          urlLauncher: (uri, {mode = LaunchMode.platformDefault}) async {
            launchedUri = uri;
            launchMode = mode;
            return true;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    final button = find.text('查看完整在线隐私政策');
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();

    expect(
      launchedUri.toString(),
      'https://jbksy.cn/xiaoan-privacy.html',
    );
    expect(launchMode, LaunchMode.externalApplication);
  });

  testWidgets('PrivacyPolicyPage 点击 URL 文本也能触发外链打开', (tester) async {
    Uri? launchedUri;

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: _testLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: PrivacyPolicyPage(
          urlLauncher: (uri, {mode = LaunchMode.platformDefault}) async {
            launchedUri = uri;
            return true;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    final urlText = find.text('https://jbksy.cn/xiaoan-privacy.html');
    await tester.ensureVisible(urlText);
    await tester.tap(urlText);
    await tester.pumpAndSettle();

    expect(
      launchedUri.toString(),
      'https://jbksy.cn/xiaoan-privacy.html',
    );
  });

  testWidgets('PrivacyPolicyPage 打开外链失败时显示错误提示 SnackBar', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: _testLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: PrivacyPolicyPage(
          urlLauncher: (uri, {mode = LaunchMode.platformDefault}) async =>
              false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final button = find.text('查看完整在线隐私政策');
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();

    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.text('无法打开网页，请在浏览器输入页面上的网址'), findsOneWidget);
  });

  testWidgets('PrivacyPolicyPage 在暗色模式下正常渲染', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        locale: const Locale('zh'),
        localizationsDelegates: _testLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const PrivacyPolicyPage(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('隐私政策'), findsOneWidget);
    expect(find.text('生效日期：2026年9月'), findsOneWidget);
  });

  testWidgets('AboutPage 展示应用图标、版本号及三大核心特性卡片', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        locale: Locale('zh'),
        localizationsDelegates: _testLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: AboutPage(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(Image), findsOneWidget);
    expect(find.text('小安翻译'), findsOneWidget);
    expect(find.text('Xiaoan Translate'), findsNothing);
    expect(find.text('测试版'), findsNothing);
    expect(find.text('版本 1.0.0 (1)'), findsOneWidget);
    expect(find.textContaining('Google ML Kit'), findsWidgets);
    expect(find.text('第三方开源库与组件'), findsOneWidget);
    expect(find.text('项目源代码'), findsOneWidget);
    expect(find.text('轻量、私密、纯粹的设备端离线翻译工具'), findsOneWidget);
    expect(find.text('离线双向翻译'), findsOneWidget);
    expect(find.text('隐私无痕存储'), findsOneWidget);
    expect(find.text('本地语音朗读'), findsOneWidget);
    expect(find.text('隐私政策'), findsOneWidget);
    expect(
      find.text('Copyright © 2026 小安翻译 Team. All rights reserved.'),
      findsOneWidget,
    );
  });

  testWidgets('AboutPage 在英文环境下渲染英文品牌与特性描述', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        locale: Locale('en'),
        localizationsDelegates: _testLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: AboutPage(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('About Xiaoan Translate'), findsOneWidget);
    expect(find.text('Xiaoan Translate'), findsOneWidget);
    expect(find.text('小安翻译'), findsNothing);
    expect(find.text('Beta'), findsNothing);
    expect(find.text('Version 1.0.0 (1)'), findsOneWidget);
    expect(find.text('Offline Bi-Directional Translation'), findsOneWidget);
    expect(find.text('Private Local Storage'), findsOneWidget);
    expect(find.text('Native Speech Synthesis'), findsOneWidget);
    expect(find.text('Open Source Licenses & Dependencies'), findsOneWidget);
    expect(find.text('Source Code'), findsOneWidget);
    expect(find.text('Privacy Policy'), findsOneWidget);
    expect(
      find.text('Copyright © 2026 Xiaoan Translate Team. All rights reserved.'),
      findsOneWidget,
    );
  });

  testWidgets('AboutPage 支持构造注入 PackageInfo Future 展示指定版本', (tester) async {
    final mockInfo = PackageInfo(
      appName: '小安翻译',
      packageName: 'com.jbk.xiaoants',
      version: '2.0.0',
      buildNumber: '2026',
      buildSignature: '',
    );
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: _testLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: AboutPage(
          packageInfoFuture: Future.value(mockInfo),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('版本 2.0.0 (2026)'), findsOneWidget);
  });

  testWidgets('AboutPage 项目源代码使用外部浏览器打开 GitHub', (tester) async {
    Uri? launchedUri;
    LaunchMode? launchMode;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: _testLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: AboutPage(
          sourceUrlLauncher: (uri, {mode = LaunchMode.platformDefault}) async {
            launchedUri = uri;
            launchMode = mode;
            return true;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    final sourceLink = find.text('项目源代码');
    await tester.ensureVisible(sourceLink);
    await tester.tap(sourceLink);
    await tester.pumpAndSettle();

    expect(launchedUri.toString(), projectSourceUrl);
    expect(launchMode, LaunchMode.externalApplication);
  });

  testWidgets('AboutPage 点击第三方开源库与组件触发 onNavigateToDependencies', (
    tester,
  ) async {
    var navigated = false;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: _testLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: AboutPage(
          onNavigateToDependencies: () => navigated = true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final target = find.text('第三方开源库与组件');
    await tester.ensureVisible(target);
    await tester.tap(target);
    await tester.pumpAndSettle();

    expect(navigated, isTrue);
  });

  testWidgets('AboutPage 点击隐私政策触发 onNavigateToPrivacy', (tester) async {
    var navigated = false;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: _testLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: AboutPage(
          onNavigateToPrivacy: () => navigated = true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final target = find.text('隐私政策');
    await tester.ensureVisible(target);
    await tester.tap(target);
    await tester.pumpAndSettle();

    expect(navigated, isTrue);
  });

  testWidgets('AboutPage 在暗色模式下正常渲染', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        locale: const Locale('zh'),
        localizationsDelegates: _testLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const AboutPage(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('小安翻译'), findsOneWidget);
    expect(find.text('关于小安翻译'), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('InfoPage 兼容层以 InfoKind.privacy 构造转发至 PrivacyPolicyPage', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        locale: Locale('zh'),
        localizationsDelegates: _testLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: InfoPage(kind: InfoKind.privacy),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(PrivacyPolicyPage), findsOneWidget);
    expect(find.text('隐私政策'), findsOneWidget);
    expect(find.text('生效日期：2026年9月'), findsOneWidget);
  });

  testWidgets('InfoPage 兼容层以 InfoKind.about 构造转发至 AboutPage', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        locale: Locale('zh'),
        localizationsDelegates: _testLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: InfoPage(kind: InfoKind.about),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AboutPage), findsOneWidget);
    expect(find.text('关于小安翻译'), findsOneWidget);
    expect(find.text('轻量、私密、纯粹的设备端离线翻译工具'), findsOneWidget);
  });

  test('routerProvider 正确配置 /privacy、/about 与 /about/dependencies 路由', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final router = container.read(routerProvider);
    final routes = router.configuration.routes.whereType<GoRoute>().toList();

    expect(routes.any((r) => r.path == '/privacy'), isTrue);
    expect(routes.any((r) => r.path == '/about'), isTrue);
    expect(routes.any((r) => r.path == '/about/dependencies'), isTrue);
  });
}
