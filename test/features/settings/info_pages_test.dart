import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:xiaoan_tsl/features/settings/open_source_licenses_page.dart';
import 'package:xiaoan_tsl/l10n/app_localizations.dart';

const _testLocalizationsDelegates = [
  AppLocalizations.delegate,
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
];

void main() {
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
}
