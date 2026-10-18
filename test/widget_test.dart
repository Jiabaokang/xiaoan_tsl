import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:xiaoan_tsl/app.dart';
import 'package:xiaoan_tsl/core/widgets/app_panel.dart';
import 'package:xiaoan_tsl/features/translate/app_controller.dart';
import 'package:xiaoan_tsl/core/database/database_provider.dart';
import 'package:xiaoan_tsl/core/router/app_router.dart';
import 'package:xiaoan_tsl/features/history/history_store.dart';
import 'package:xiaoan_tsl/core/database/local_store.dart';
import 'package:xiaoan_tsl/services/language/language_detection_provider.dart';
import 'package:xiaoan_tsl/services/translation/model_service_provider.dart';
import 'package:xiaoan_tsl/services/translation/mlkit_model_service.dart';
import 'package:xiaoan_tsl/services/translation/translation_service.dart';
import 'package:xiaoan_tsl/services/translation/translation_service_provider.dart';
import 'package:xiaoan_tsl/services/translation/translation_settings.dart';
import 'package:xiaoan_tsl/services/speech/speech_service_provider.dart';
import 'package:xiaoan_tsl/services/speech/tts_service.dart';
import 'package:xiaoan_tsl/services/desktop/macos_desktop_service.dart';

import 'support/test_translation_services.dart';

// 模型首次下载失败后可切换为成功，用于验证页面的显式重试。
class _RetryModels implements TranslationModelService {
  bool fail = true;

  @override
  Future<bool> isDownloaded(String code) async => !fail;

  @override
  Future<void> download(String code, {bool wifiOnly = true}) async {
    if (fail) throw StateError('下载失败');
  }

  @override
  Future<void> delete(String code) async {}
}

// 需要 ML Kit 模型流程的翻译替身：模型下载类组件测试专用。
class _ModelRequiredTranslator implements TranslationService {
  @override
  String get engineId => 'demo';

  @override
  bool get requiresMlKitModels => true;

  @override
  Future<String> translate({
    required String text,
    required String sourceLanguage,
    required String targetLanguage,
  }) async => '你好，世界！';
}

// 内存模型列表用于核对管理页的查询、下载与删除反馈。
class _ManagedModels implements TranslationModelService {
  final downloaded = <String>{'en'};
  final wifiRequirements = <bool>[];

  @override
  Future<bool> isDownloaded(String code) async => downloaded.contains(code);

  @override
  Future<void> download(String code, {bool wifiOnly = true}) async {
    wifiRequirements.add(wifiOnly);
    downloaded.add(code);
  }

  @override
  Future<void> delete(String code) async {
    downloaded.remove(code);
  }
}

// 记录页面朗读与停止操作，不访问设备声音服务。
class _SpeechRecorder implements SpeechService {
  final calls = <(String, String)>[];
  int stops = 0;
  Completer<void>? pending;

  @override
  Future<void> speak({required String text, required String languageCode}) {
    calls.add((text, languageCode));
    pending = Completer<void>();
    return pending!.future;
  }

  @override
  Future<void> stop() async {
    stops++;
    if (pending?.isCompleted == false) pending!.complete();
  }
}

// 用于验证设备语音不可用和引擎故障时的页面反馈。
class _FailingSpeech implements SpeechService {
  _FailingSpeech(this.error);

  final Object error;

  @override
  Future<void> speak({
    required String text,
    required String languageCode,
  }) async {
    throw error;
  }

  @override
  Future<void> stop() async {}
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    PackageInfo.setMockInitialValues(
      appName: '小安翻译',
      packageName: 'com.jbk.xiaoants',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  late LocalStore store;
  late ProviderContainer container;

  setUp(() async {
    store = await LocalStore.open(
      path: inMemoryDatabasePath,
      legacyFile: File('/nonexistent/xiaoan_history.json'),
      factory: databaseFactoryFfi,
    );
    container = ProviderContainer(
      overrides: [
        localStoreProvider.overrideWithValue(store),
        translationServiceProvider.overrideWithValue(DemoTranslationService()),
        languageDetectionProvider.overrideWithValue(
          TestLanguageDetectionService(),
        ),
        translationModelProvider.overrideWithValue(
          DownloadedTranslationModels(),
        ),
      ],
    );
    await container.read(appControllerProvider.notifier).initialize();
  });

  tearDown(() async {
    container.dispose();
    await store.close();
  });

  Future<void> pumpApp(WidgetTester tester) async {
    tester.platformDispatcher.localesTestValue = const [Locale('zh', 'CN')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const XiaoanApp()),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('macOS 截图快捷键保留主页和输入，不再把结果路由压到主页上', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    container.invalidate(translationPlatformProvider);
    const channel = MethodChannel('xiaoan_tsl/macos_desktop');
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'captureRegion') return {'cancelled': true};
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    const events = EventChannel('xiaoan_tsl/macos_desktop_events');
    MockStreamHandlerEventSink? sink;
    messenger.setMockStreamHandler(events, MockStreamHandler.inline(
      onListen: (_, eventSink) {
        sink = eventSink;
      },
    ));
    addTearDown(() => messenger.setMockStreamHandler(events, null));
    await pumpApp(tester);
    await tester.enterText(
        find.byKey(const Key('sourceInput')), 'Keep my draft');
    sink!.success('screenshotHotkey');
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byKey(const Key('sourceInput')), findsOneWidget);
    expect(container.read(appControllerProvider).input, 'Keep my draft');
    expect(container.read(macosDesktopServiceProvider),
        isA<MacosDesktopChannel>());
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('macOS 设置主页可选择并保存全局截图快捷键，冲突保留旧设置', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    container.invalidate(translationPlatformProvider);
    const channel = MethodChannel('xiaoan_tsl/macos_desktop');
    var conflict = false;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      if (call.method == 'updateShortcut' && conflict) {
        throw PlatformException(code: 'shortcutConflict');
      }
      return null;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    // 使用真实服务 Provider，事件流边界仅替换系统通道。
    const events = MethodChannel('xiaoan_tsl/macos_desktop_events');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      events,
      (_) async => null,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        events,
        null,
      ),
    );
    await pumpApp(tester);
    await tester.tap(find.text('设置').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('screenshotShortcutTile')), findsOneWidget);
    await tester.tap(find.byKey(const Key('screenshotShortcutTile')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('shortcutOption_Control+Shift+T')));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    expect(
      await tester.runAsync(
        () => store.getSetting(TranslationSettingKeys.screenshotShortcut),
      ),
      'Control+Shift+T',
    );
    expect(find.textContaining('Control + Shift + T'), findsOneWidget);
    // 等成功提示消失，再验证下一次操作的冲突提示，避免 SnackBar 排队遮挡断言。
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    conflict = true;
    await tester.tap(find.byKey(const Key('screenshotShortcutTile')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('shortcutOption_Command+Option+T')));
    await tester.pumpAndSettle();
    expect(
      await tester.runAsync(
        () => store.getSetting(TranslationSettingKeys.screenshotShortcut),
      ),
      'Control+Shift+T',
    );
    expect(find.text('快捷键注册失败或与其他应用冲突，已保留原设置'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  Future<void> waitFor(WidgetTester tester, bool Function() condition) async {
    for (var i = 0; i < 100 && !condition(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 30));
    }
    expect(
      condition(),
      isTrue,
      reason:
          'state: ${container.read(appControllerProvider).phase}, '
          'input: ${container.read(appControllerProvider).input}, '
          'message: ${container.read(appControllerProvider).message}',
    );
    await tester.pumpAndSettle();
  }

  for (final route in ['/history', '/favorites', '/settings']) {
    testWidgets('$route在横屏时避让两侧系统区域', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(900, 500);
      tester.view.padding = const FakeViewPadding(
        left: 72,
        right: 36,
        bottom: 24,
      );
      addTearDown(tester.view.reset);
      await pumpApp(tester);
      container.read(routerProvider).go(route);
      await tester.pump();
      await waitFor(
        tester,
        () => find.byType(CircularProgressIndicator).evaluate().isEmpty,
      );
      final item = route == '/settings'
          ? find.byType(ListTile).first
          : find.byType(TextField).first;
      final rect = tester.getRect(item);
      expect(rect.left, greaterThanOrEqualTo(72));
      expect(rect.right, lessThanOrEqualTo(864));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('首页品牌图标在浅色和深色主题下使用应用图标', (tester) async {
    await pumpApp(tester);
    final icon = find.byKey(const Key('appBrandIcon'));
    expect(icon, findsOneWidget);
    expect(
      (tester.widget<Image>(icon).image as AssetImage).assetName,
      'assets/branding/app_icon_128.png',
    );

    await tester.runAsync(
      () => container
          .read(appControllerProvider.notifier)
          .setThemeMode(ThemeMode.dark),
    );
    await tester.pumpAndSettle();
    expect(icon, findsOneWidget);
    expect(Theme.of(tester.element(icon)).brightness, Brightness.dark);
  });

  testWidgets('系统手势区域与底部导航栏在浅色和深色主题下同色', (tester) async {
    await pumpApp(tester);
    final navigationBar = find.byType(NavigationBar);

    void expectSystemBar(Brightness brightness) {
      final bar = tester.widget<NavigationBar>(navigationBar);
      final region = tester.widget<AnnotatedRegion<SystemUiOverlayStyle>>(
        find.ancestor(
          of: navigationBar,
          matching: find.byType(AnnotatedRegion<SystemUiOverlayStyle>),
        ),
      );
      final expectedColor = Theme.of(
        tester.element(navigationBar),
      ).colorScheme.surfaceContainer;
      expect(bar.backgroundColor, expectedColor);
      expect(region.value.systemNavigationBarColor, expectedColor);
      expect(region.value.systemNavigationBarIconBrightness, brightness);
      expect(region.value.systemNavigationBarContrastEnforced, isFalse);
    }

    expectSystemBar(Brightness.dark);
    await tester.runAsync(
      () => container
          .read(appControllerProvider.notifier)
          .setThemeMode(ThemeMode.dark),
    );
    await tester.pumpAndSettle();
    expectSystemBar(Brightness.light);
  });

  testWidgets('输入后自动显示双向译文', (tester) async {
    await pumpApp(tester);
    final input = find.byKey(const Key('sourceInput'));
    await tester.enterText(input, 'Hello, world!');
    await waitFor(
      tester,
      () =>
          container.read(appControllerProvider).result?.translatedText ==
          '你好，世界！',
    );
    await tester.scrollUntilVisible(
      find.text('你好，世界！'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('你好，世界！'), findsOneWidget);
    expect(find.text('重新翻译'), findsOneWidget);

    await tester.scrollUntilVisible(
      input,
      -200,
      scrollable: find.byType(Scrollable).first,
    );

    await tester.enterText(input, '你好，世界！');
    await waitFor(
      tester,
      () =>
          container.read(appControllerProvider).result?.translatedText ==
          'Hello, world!',
    );
    expect(container.read(appControllerProvider).result?.targetLanguage, 'en');
    await tester.scrollUntilVisible(
      find.text('原文语言'),
      -200,
      scrollable: find.byType(Scrollable).first,
    );
    final sourceButton = find.ancestor(
      of: find.text('原文语言'),
      matching: find.byType(TextButton),
    );
    final targetButton = find.ancestor(
      of: find.text('译文语言'),
      matching: find.byType(TextButton),
    );
    final languagePanel = find.ancestor(
      of: sourceButton,
      matching: find.byType(AppPanel),
    );
    final sourceRect = tester.getRect(sourceButton);
    final swapSlotRect = tester.getRect(
      find.byKey(const Key('swapLanguageSlot')),
    );
    final targetRect = tester.getRect(targetButton);
    final panelRect = tester.getRect(languagePanel);
    final swapRect = tester.getRect(find.byTooltip('交换语言'));
    expect(sourceRect.width, closeTo(swapSlotRect.width, 1));
    expect(sourceRect.width, closeTo(targetRect.width, 1));
    expect(
      sourceRect.width + swapSlotRect.width + targetRect.width,
      closeTo(panelRect.width, 2),
    );
    expect(swapRect.center.dx, closeTo(panelRect.center.dx, 1));
    expect(
      find.descendant(of: sourceButton, matching: find.text('简体中文')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: targetButton, matching: find.text('English')),
      findsOneWidget,
    );
    await tester.ensureVisible(sourceButton);
    await tester.tap(sourceButton);
    await tester.pumpAndSettle();
    expect(find.text('选择原文语言'), findsOneWidget);
  });

  testWidgets('模拟翻译、收藏、历史和四个底部入口', (tester) async {
    await pumpApp(tester);
    expect(find.text('随时翻译 · 轻松记住'), findsNothing);
    expect(find.text('把想说的话，\n翻译得更简单。'), findsNothing);
    expect(find.text('历史保存在本机，常用表达随手收藏。'), findsNothing);
    expect(find.text('语言模型首次使用需下载，之后可在设备端翻译'), findsNothing);
    expect(find.byType(ActionChip), findsNothing);
    expect(find.textContaining('由 Google Translate'), findsNothing);
    await tester.enterText(
      find.byKey(const Key('sourceInput')),
      'Hello, world!',
    );
    expect(container.read(appControllerProvider).input, 'Hello, world!');
    await tester.pump();
    await tester.ensureVisible(find.text('开始翻译'));
    await tester.tap(find.text('开始翻译'));
    await tester.pump();
    await waitFor(
      tester,
      () => container.read(appControllerProvider).result?.id.isNotEmpty == true,
    );
    expect(find.text('你好，世界！'), findsOneWidget);
    expect(find.text('演示译文，不代表真实翻译效果'), findsOneWidget);
    await tester.ensureVisible(find.byTooltip('收藏译文'));
    await tester.tap(find.byTooltip('收藏译文'));
    await waitFor(
      tester,
      () => container.read(appControllerProvider).result?.favorite == true,
    );

    await tester.tap(find.text('历史').last);
    await waitFor(
      tester,
      () =>
          find.text('翻译历史').evaluate().isNotEmpty &&
          find.text('Hello, world!').evaluate().isNotEmpty,
    );
    expect(find.text('你好，世界！'), findsOneWidget);
    expect(find.textContaining('演示记录'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, '找不到');
    await waitFor(tester, () => find.text('没有找到相关记录').evaluate().isNotEmpty);
    await tester.enterText(find.byType(TextField).last, '你好');
    await waitFor(
      tester,
      () => find.text('Hello, world!').evaluate().isNotEmpty,
    );
    await tester.tap(find.text('收藏').last);
    await waitFor(
      tester,
      () =>
          find.text('我的收藏').evaluate().isNotEmpty &&
          find.text('Hello, world!').evaluate().isNotEmpty,
    );
    await tester.tap(find.text('设置').last);
    await tester.pumpAndSettle();
    expect(find.text('默认目标语言'), findsOneWidget);
    await tester.tap(find.text('清空翻译历史'));
    await tester.pumpAndSettle();
    expect(find.text('收藏也会一并删除，此操作无法撤销。'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(container.read(appControllerProvider).records, isNotEmpty);
    await tester.tap(find.text('清空翻译历史'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('清空').last);
    await waitFor(
      tester,
      () => container.read(appControllerProvider).records.isEmpty,
    );
    await tester.runAsync(() => store.search(''));
    await tester.pump();
    await tester.tap(find.text('翻译').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('sourceInput')), findsOneWidget);
    expect(container.read(appControllerProvider).input, 'Hello, world!');
  });

  testWidgets('历史 ID 深链、未知地址和语言选择', (tester) async {
    final saved = await tester.runAsync(
      () => store.saveRecord(
        TranslationRecord(
          sourceText: 'Good morning',
          translatedText: '早上好',
          sourceLanguage: 'en',
          targetLanguage: 'zh',
          createdAt: DateTime(2026, 9, 24),
        ),
      ),
    );
    final recordId = saved!.id;
    container.read(routerProvider).go('/translate?record=$recordId');
    await pumpApp(tester);
    await waitFor(
      tester,
      () => container.read(appControllerProvider).result?.id == recordId,
    );
    await tester.scrollUntilVisible(
      find.text('早上好'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('早上好'), findsOneWidget);

    await tester.drag(find.byType(Scrollable).first, const Offset(0, 1000));
    await tester.pumpAndSettle();

    await tester.tap(find.text('简体中文').first);
    await tester.pumpAndSettle();
    expect(find.text('选择译文语言'), findsOneWidget);
    expect(find.text('自动检测'), findsNothing);
    await tester.enterText(find.byType(TextField).last, 'en');
    await tester.pumpAndSettle();
    await tester.tap(find.text('English').last);
    await tester.pumpAndSettle();
    expect(container.read(appControllerProvider).targetLanguage, 'en');

    container.read(routerProvider).go('/missing');
    await tester.pumpAndSettle();
    expect(find.text('找不到这个页面'), findsOneWidget);
    await tester.tap(find.text('返回翻译首页'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('sourceInput')), findsOneWidget);
  });

  testWidgets('设置主题和次级页面可返回', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('设置').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, '外观模式'));
    await tester.pumpAndSettle();
    expect(find.byType(SimpleDialog), findsOneWidget);
    await tester.tap(find.widgetWithText(SimpleDialogOption, '深色'));
    await waitFor(
      tester,
      () => container.read(appControllerProvider).themeMode == ThemeMode.dark,
    );
    expect(
      Theme.of(tester.element(find.text('设置').first)).brightness,
      Brightness.dark,
    );
    await tester.scrollUntilVisible(
      find.text('离线语言包'),
      120,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('离线语言包'));
    await tester.pumpAndSettle();
    await waitFor(
      tester,
      () => find.textContaining('模型状态来自设备').evaluate().isNotEmpty,
    );
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('清空翻译历史'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('关于小安翻译'),
      120,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('关于小安翻译'));
    await tester.pumpAndSettle();
    expect(find.text('版本 1.0.0 (1)'), findsOneWidget);
    expect(find.textContaining('Google ML Kit'), findsOneWidget);
    await tester.ensureVisible(find.text('第三方开源库与组件'));
    await tester.tap(find.text('第三方开源库与组件'));
    await tester.pumpAndSettle();
    expect(find.text('flutter_riverpod'), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('关于小安翻译'), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('隐私政策'),
      120,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('隐私政策'));
    await tester.pumpAndSettle();
    expect(find.textContaining('关闭系统备份'), findsOneWidget);
    expect(find.textContaining('不申请麦克风'), findsOneWidget);
    expect(find.text('https://jbksy.cn/xiaoan-privacy.html'), findsOneWidget);
  });

  testWidgets('历史记录可单条删除', (tester) async {
    await tester.runAsync(
      () => store.saveRecord(
        TranslationRecord(
          sourceText: 'Good morning',
          translatedText: '早上好',
          sourceLanguage: 'en',
          targetLanguage: 'zh',
          createdAt: DateTime(2026, 9, 24),
        ),
      ),
    );
    await pumpApp(tester);
    await tester.tap(find.text('历史').last);
    await waitFor(
      tester,
      () => find.text('Good morning').evaluate().isNotEmpty,
    );
    await tester.tap(find.byTooltip('删除记录'));
    await waitFor(tester, () => find.text('还没有翻译记录').evaluate().isNotEmpty);
  });

  testWidgets('模型下载失败显示重试，成功后展示结果', (tester) async {
    final models = _RetryModels();
    container.dispose();
    container = ProviderContainer(
      overrides: [
        localStoreProvider.overrideWithValue(store),
        translationServiceProvider.overrideWithValue(
          _ModelRequiredTranslator(),
        ),
        languageDetectionProvider.overrideWithValue(
          TestLanguageDetectionService(),
        ),
        translationModelProvider.overrideWithValue(models),
      ],
    );
    final controller = container.read(appControllerProvider.notifier);
    await tester.runAsync(controller.initialize);
    controller.setSourceLanguage('en');
    controller.setInput('Hello, world!');
    await tester.runAsync(() => controller.translate(downloadMissing: true));
    await pumpApp(tester);

    expect(find.text('重试翻译'), findsOneWidget);
    expect(container.read(appControllerProvider).input, 'Hello, world!');
    models.fail = false;
    await tester.ensureVisible(find.text('重试翻译'));
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -180));
    await tester.pumpAndSettle();
    await tester.tap(find.text('重试翻译'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('允许移动网络下载'));
    await waitFor(
      tester,
      () =>
          container.read(appControllerProvider).phase ==
          TranslationPhase.success,
    );
    expect(
      container.read(appControllerProvider).result?.translatedText,
      '你好，世界！',
    );
  });

  testWidgets('首页缺少模型时先提示，确认后用移动网络选项下载并翻译', (tester) async {
    final models = _ManagedModels();
    container.dispose();
    container = ProviderContainer(
      overrides: [
        localStoreProvider.overrideWithValue(store),
        translationServiceProvider.overrideWithValue(
          _ModelRequiredTranslator(),
        ),
        languageDetectionProvider.overrideWithValue(
          TestLanguageDetectionService(),
        ),
        translationModelProvider.overrideWithValue(models),
      ],
    );
    await tester.runAsync(
      () => container.read(appControllerProvider.notifier).initialize(),
    );
    await pumpApp(tester);
    await tester.enterText(
      find.byKey(const Key('sourceInput')),
      'Hello, world!',
    );
    await tester.pump(const Duration(milliseconds: 650));
    await waitFor(tester, () => find.text('需要下载语言模型').evaluate().isNotEmpty);
    expect(models.wifiRequirements, isEmpty);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(models.wifiRequirements, isEmpty);
    await tester.tap(find.widgetWithText(FilledButton, '需要下载语言模型'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('允许移动网络下载'));
    await waitFor(
      tester,
      () =>
          container.read(appControllerProvider).phase ==
          TranslationPhase.success,
    );
    expect(models.wifiRequirements, [false]);
    expect(
      container.read(appControllerProvider).result?.translatedText,
      '你好，世界！',
    );
  });

  testWidgets('离线语言包页面查询状态并支持下载和删除', (tester) async {
    final models = _ManagedModels();
    container.dispose();
    container = ProviderContainer(
      overrides: [
        localStoreProvider.overrideWithValue(store),
        translationServiceProvider.overrideWithValue(DemoTranslationService()),
        languageDetectionProvider.overrideWithValue(
          TestLanguageDetectionService(),
        ),
        translationModelProvider.overrideWithValue(models),
      ],
    );
    await tester.runAsync(
      () => container.read(appControllerProvider.notifier).initialize(),
    );
    await pumpApp(tester);
    await tester.tap(find.text('设置').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('离线语言包'));
    await waitFor(
      tester,
      () => find.byKey(const Key('download_zh')).evaluate().isNotEmpty,
    );
    expect(find.byKey(const Key('delete_en')), findsOneWidget);

    await tester.tap(find.byKey(const Key('download_zh')));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text('仅 Wi-Fi 下载'));
    await waitFor(
      tester,
      () => find.byKey(const Key('delete_zh')).evaluate().isNotEmpty,
    );
    await tester.tap(find.byKey(const Key('delete_zh')));
    await waitFor(
      tester,
      () => find.byKey(const Key('download_zh')).evaluate().isNotEmpty,
    );
  });

  testWidgets('离线语言包下载失败后可再次下载', (tester) async {
    final models = _RetryModels();
    container.dispose();
    container = ProviderContainer(
      overrides: [
        localStoreProvider.overrideWithValue(store),
        translationServiceProvider.overrideWithValue(DemoTranslationService()),
        languageDetectionProvider.overrideWithValue(
          TestLanguageDetectionService(),
        ),
        translationModelProvider.overrideWithValue(models),
      ],
    );
    await tester.runAsync(
      () => container.read(appControllerProvider.notifier).initialize(),
    );
    await pumpApp(tester);
    await tester.tap(find.text('设置').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('离线语言包'));
    await waitFor(
      tester,
      () => find.byKey(const Key('download_zh')).evaluate().isNotEmpty,
    );
    await tester.tap(find.byKey(const Key('download_zh')));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text('仅 Wi-Fi 下载'));
    await waitFor(
      tester,
      () => find.textContaining('语言包下载失败').evaluate().isNotEmpty,
    );
    expect(find.text('重试下载'), findsOneWidget);
    models.fail = false;
    await tester.tap(find.text('重试下载'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text('仅 Wi-Fi 下载'));
    await waitFor(
      tester,
      () => find.byKey(const Key('delete_zh')).evaluate().isNotEmpty,
    );
    expect(find.textContaining('语言包下载失败'), findsNothing);
  });

  testWidgets('原文和译文使用各自语言朗读并可停止', (tester) async {
    final speech = _SpeechRecorder();
    container.dispose();
    container = ProviderContainer(
      overrides: [
        localStoreProvider.overrideWithValue(store),
        translationServiceProvider.overrideWithValue(DemoTranslationService()),
        languageDetectionProvider.overrideWithValue(
          TestLanguageDetectionService(),
        ),
        translationModelProvider.overrideWithValue(
          DownloadedTranslationModels(),
        ),
        speechServiceProvider.overrideWithValue(speech),
      ],
    );
    final controller = container.read(appControllerProvider.notifier);
    await tester.runAsync(controller.initialize);
    controller.setSourceLanguage('en');
    controller.setInput('Hello, world!');
    await pumpApp(tester);

    await tester.tap(find.byTooltip('朗读原文'));
    await tester.pump();
    expect(speech.calls.single, ('Hello, world!', 'en'));
    await tester.tap(find.byTooltip('停止朗读').first);
    await tester.pump();
    expect(speech.stops, 1);

    await tester.runAsync(controller.translate);
    await tester.pump();
    await tester.scrollUntilVisible(
      find.byTooltip('朗读译文'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -160));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('朗读译文'));
    await tester.pump();
    expect(speech.calls.last, ('你好，世界！', 'zh'));

    await tester.tap(find.byTooltip('停止朗读').last);
    await tester.pump();
    controller.setInput('你好，世界！');
    await tester.runAsync(controller.translate);
    await tester.pump();
    await tester.scrollUntilVisible(
      find.byTooltip('朗读原文'),
      -200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byTooltip('朗读原文'));
    await tester.pump();
    expect(speech.calls.last, ('你好，世界！', 'zh'));
  });

  for (final (error, message) in [
    (UnsupportedError('当前设备暂不支持该语言朗读'), '当前设备暂不支持该语言朗读'),
    (StateError('引擎异常'), '朗读失败，请检查设备语音服务'),
  ]) {
    testWidgets('朗读失败提示：$message', (tester) async {
      container.dispose();
      container = ProviderContainer(
        overrides: [
          localStoreProvider.overrideWithValue(store),
          translationServiceProvider.overrideWithValue(
            DemoTranslationService(),
          ),
          languageDetectionProvider.overrideWithValue(
            TestLanguageDetectionService(),
          ),
          translationModelProvider.overrideWithValue(
            DownloadedTranslationModels(),
          ),
          speechServiceProvider.overrideWithValue(_FailingSpeech(error)),
        ],
      );
      final controller = container.read(appControllerProvider.notifier);
      await tester.runAsync(controller.initialize);
      controller.setSourceLanguage('en');
      controller.setInput('Hello, world!');
      await pumpApp(tester);
      await tester.tap(find.byTooltip('朗读原文'));
      await tester.pumpAndSettle();
      expect(find.text(message), findsOneWidget);
    });
  }

  testWidgets('默认语言与主题在重建后恢复', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('设置').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('默认目标语言'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('English'));
    await waitFor(
      tester,
      () => container.read(appControllerProvider).defaultTargetLanguage == 'en',
    );
    await tester.tap(find.widgetWithText(ListTile, '外观模式'));
    await tester.pumpAndSettle();
    expect(find.byType(SimpleDialog), findsOneWidget);
    await tester.tap(find.widgetWithText(SimpleDialogOption, '浅色'));
    await waitFor(
      tester,
      () => container.read(appControllerProvider).themeMode == ThemeMode.light,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
    container = ProviderContainer(
      overrides: [
        localStoreProvider.overrideWithValue(store),
        translationServiceProvider.overrideWithValue(DemoTranslationService()),
        languageDetectionProvider.overrideWithValue(
          TestLanguageDetectionService(),
        ),
        translationModelProvider.overrideWithValue(
          DownloadedTranslationModels(),
        ),
      ],
    );
    await tester.runAsync(
      () => container.read(appControllerProvider.notifier).initialize(),
    );
    await pumpApp(tester);
    expect(container.read(appControllerProvider).defaultTargetLanguage, 'en');
    expect(container.read(appControllerProvider).themeMode, ThemeMode.light);
    expect(container.read(appControllerProvider).targetLanguage, 'en');
  });

  testWidgets('跟随系统语言：系统语言为英文时自动显示英文界面，为中文时自动显示中文界面', (tester) async {
    // 模拟系统语言为英文
    tester.platformDispatcher.localesTestValue = const [Locale('en', 'US')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const XiaoanApp()),
    );
    await tester.pumpAndSettle();

    expect(find.text('Translate'), findsWidgets);
    expect(find.text('History'), findsOneWidget);
    expect(find.text('Favorites'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Source Language'), findsOneWidget);
    expect(find.text('Target Language'), findsOneWidget);
    expect(find.text('Ready to translate'), findsOneWidget);

    // 切换系统语言为中文
    tester.platformDispatcher.localesTestValue = const [Locale('zh', 'CN')];
    await tester.pumpAndSettle();

    expect(find.text('翻译'), findsWidgets);
    expect(find.text('历史'), findsOneWidget);
    expect(find.text('收藏'), findsOneWidget);
    expect(find.text('设置'), findsOneWidget);
    expect(find.text('原文语言'), findsOneWidget);
    expect(find.text('译文语言'), findsOneWidget);
    expect(find.text('等待翻译'), findsOneWidget);
  });

  testWidgets('设置中手动切换应用语言为英文与中文', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.text('设置').last);
    await tester.pumpAndSettle();
    expect(find.text('应用语言'), findsOneWidget);
    expect(find.text('跟随系统语言'), findsOneWidget);

    // 打开语言选择弹窗并选择英文
    await tester.tap(find.text('应用语言'));
    await tester.pumpAndSettle();
    expect(find.text('English'), findsOneWidget);
    await tester.tap(find.text('English'));
    await waitFor(
      tester,
      () => container.read(appControllerProvider).localeMode == 'en',
    );

    // 验证界面已即时变为英文
    expect(container.read(appControllerProvider).localeMode, 'en');
    expect(find.text('Settings'), findsWidgets);
    expect(find.text('Translation Preferences'), findsOneWidget);
    expect(find.text('App Language'), findsOneWidget);

    // 再次打开语言弹窗并切换回简体中文
    await tester.tap(find.text('App Language'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('简体中文'));
    await waitFor(
      tester,
      () => container.read(appControllerProvider).localeMode == 'zh',
    );

    // 验证界面恢复为中文
    expect(container.read(appControllerProvider).localeMode, 'zh');
    expect(find.text('设置'), findsWidgets);
    expect(find.text('翻译偏好'), findsOneWidget);
    expect(find.text('应用语言'), findsOneWidget);
  });

  testWidgets('应用语言偏好在重建后持久化恢复', (tester) async {
    await pumpApp(tester);
    final controller = container.read(appControllerProvider.notifier);
    await tester.runAsync(() => controller.setLocaleMode('en'));
    await tester.pumpAndSettle();
    expect(container.read(appControllerProvider).localeMode, 'en');

    // 模拟应用重启，重新读取 LocalStore
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
    container = ProviderContainer(
      overrides: [
        localStoreProvider.overrideWithValue(store),
        translationServiceProvider.overrideWithValue(DemoTranslationService()),
        languageDetectionProvider.overrideWithValue(
          TestLanguageDetectionService(),
        ),
        translationModelProvider.overrideWithValue(
          DownloadedTranslationModels(),
        ),
      ],
    );
    await tester.runAsync(
      () => container.read(appControllerProvider.notifier).initialize(),
    );
    expect(container.read(appControllerProvider).localeMode, 'en');
    expect(container.read(appControllerProvider).locale, const Locale('en'));

    // 再次在英文状态下启动应用，验证初始界面直接为英文
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const XiaoanApp()),
    );
    await tester.pumpAndSettle();
    expect(find.text('Translate'), findsWidgets);
    expect(find.text('Settings'), findsOneWidget);
  });

  testWidgets('设置中外观模式显示副标题且支持通过弹窗切换与勾选', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('设置').last);
    await tester.pumpAndSettle();

    // 初始状态下外观模式显示副标题“跟随系统”
    final themeTile = find.widgetWithText(ListTile, '外观模式');
    expect(themeTile, findsOneWidget);
    expect(
      find.descendant(of: themeTile, matching: find.text('跟随系统')),
      findsOneWidget,
    );

    // 点击外观模式整行，弹出与应用语言一致的 SimpleDialog
    await tester.tap(themeTile);
    await tester.pumpAndSettle();
    expect(find.byType(SimpleDialog), findsOneWidget);

    // 验证当前“跟随系统”选项带有勾选图标
    final systemOption = find.widgetWithText(SimpleDialogOption, '跟随系统');
    expect(
      find.descendant(of: systemOption, matching: find.byIcon(Icons.check)),
      findsOneWidget,
    );

    // 点击“深色”选项
    await tester.tap(find.widgetWithText(SimpleDialogOption, '深色'));
    await tester.pumpAndSettle();

    // 弹窗关闭，主题切换为深色，副标题更新为“深色”
    expect(find.byType(SimpleDialog), findsNothing);
    await waitFor(
      tester,
      () => container.read(appControllerProvider).themeMode == ThemeMode.dark,
    );
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: themeTile, matching: find.text('深色')),
      findsOneWidget,
    );
  });
}
