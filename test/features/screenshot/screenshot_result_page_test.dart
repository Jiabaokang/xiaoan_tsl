import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:xiaoan_tsl/core/database/database_provider.dart';
import 'package:xiaoan_tsl/core/database/local_store.dart';
import 'package:xiaoan_tsl/core/theme/app_theme.dart';
import 'package:xiaoan_tsl/features/screenshot/screenshot_controller.dart';
import 'package:xiaoan_tsl/features/screenshot/screenshot_result_page.dart';
import 'package:xiaoan_tsl/l10n/app_localizations.dart';
import 'package:xiaoan_tsl/services/desktop/macos_desktop_service.dart';
import 'package:xiaoan_tsl/services/language/language_detection_provider.dart';
import 'package:xiaoan_tsl/services/translation/translation_service.dart';
import 'package:xiaoan_tsl/services/translation/translation_service_provider.dart';

import '../../support/test_translation_services.dart';

// 可预设初始状态并在测试中切换状态的控制器替身。
class _StateController extends ScreenshotController {
  _StateController(this._initial);

  final ScreenshotState _initial;

  @override
  ScreenshotState build() => _initial;

  void set(ScreenshotState value) => state = value;
}

// 1×1 透明 PNG，用于页面 Image.memory 解码。
final _kTestPng = Uint8List.fromList([
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, // PNG 签名
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, // IHDR
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, // 1×1
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, // RGBA
  0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41, 0x54, // IDAT
  0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00, 0x05, 0x00, 0x01,
  0x0D, 0x0A, 0x2D, 0xB4,
  0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, // IEND
  0xAE, 0x42, 0x60, 0x82,
]);

// 桌面通道替身：返回固定截图与可配置 OCR 文本。
class _PageDesktop implements MacosDesktopService {
  _PageDesktop({this.ocrText = 'hello world'});

  final String ocrText;

  @override
  Future<CaptureRegionResult> captureRegion(String requestId) async =>
      CaptureRegionResult(
        requestId: requestId,
        cancelled: false,
        pngBytes: _kTestPng,
        displayId: 1001,
        selection: const Rect.fromLTWH(10, 20, 300, 120),
        pixelWidth: 600,
        pixelHeight: 240,
      );

  @override
  Future<String> recognizeText(String requestId, Uint8List pngBytes) async =>
      ocrText;

  @override
  Future<String?> identifyLanguage(String text) async => 'en';

  @override
  Future<void> showResultWindow({
    required int displayId,
    required Rect selection,
  }) async {}

  @override
  Future<void> updateResult(Map<String, Object?> state) async {}

  @override
  Future<void> cancelCapture(String requestId) async {}

  @override
  Future<void> updateShortcut(String shortcut) async {}

  @override
  Stream<MacosDesktopEvent> get events => const Stream.empty();
}

// 翻译替身：固定返回中文译文。
class _PageTranslation implements TranslationService {
  @override
  String get engineId => 'baidu';

  @override
  bool get requiresMlKitModels => false;

  @override
  Future<String> translate({
    required String text,
    required String sourceLanguage,
    required String targetLanguage,
  }) async =>
      '你好，世界！';
}

void main() {
  setUpAll(sqfliteFfiInit);

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 80)),
    );
    // 进度圈会一直请求帧，不能用 pumpAndSettle。
    await tester.pump(const Duration(milliseconds: 100));
  }

  Future<ProviderContainer> pumpPage(
    WidgetTester tester, {
    required ScreenshotState state,
    Locale locale = const Locale('zh'),
    ThemeMode themeMode = ThemeMode.light,
    bool useRealController = false,
    String ocrText = 'hello world',
  }) async {
    // sqflite ffi 是真实异步，必须在 runAsync 中打开，否则假异步区挂起。
    Directory? directory;
    LocalStore? store;
    await tester.runAsync(() async {
      directory = await Directory.systemTemp.createTemp(
        'xiaoan_screenshot_page_',
      );
      store = await LocalStore.open(
        path: path.join(directory!.path, 'app.db'),
        legacyFile: File(path.join(directory!.path, 'none.json')),
        factory: databaseFactoryFfi,
      );
    });
    final openedStore = store!;
    addTearDown(() async {
      await openedStore.close();
      await directory!.delete(recursive: true);
    });
    final overrides = [
      localStoreProvider.overrideWithValue(openedStore),
      macosDesktopServiceProvider.overrideWithValue(
        _PageDesktop(ocrText: ocrText),
      ),
      translationServiceProvider.overrideWithValue(_PageTranslation()),
      languageDetectionProvider.overrideWithValue(
        TestLanguageDetectionService(),
      ),
      if (!useRealController)
        screenshotControllerProvider.overrideWith(
          () => _StateController(state),
        ),
    ];
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides,
        child: MaterialApp(
          locale: locale,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: appTheme(Brightness.light),
          darkTheme: appTheme(Brightness.dark),
          themeMode: themeMode,
          home: const ScreenshotResultPage(),
        ),
      ),
    );
    await settle(tester);
    return ProviderScope.containerOf(
      tester.element(find.byType(ScreenshotResultPage)),
    );
  }

  testWidgets('捕获中显示进度文案，中英文都可见', (tester) async {
    await pumpPage(
      tester,
      state: const ScreenshotState(stage: ScreenshotStage.capturing),
    );
    expect(find.text('正在选择截图区域…'), findsOneWidget);

    await pumpPage(
      tester,
      state: const ScreenshotState(stage: ScreenshotStage.capturing),
      locale: const Locale('en'),
    );
    expect(find.text('Selecting region…'), findsOneWidget);
  });

  testWidgets('非英文确认阶段显示提示与按英文翻译按钮', (tester) async {
    await pumpPage(
      tester,
      state: const ScreenshotState(
        stage: ScreenshotStage.needsConfirm,
        pngBytes: null,
        recognizedText: '谢谢你的帮助',
        confirmRequired: true,
      ),
    );
    expect(find.text('截图内容可能不是英文，仍按英文翻译吗？'), findsOneWidget);
    expect(find.byKey(const Key('screenshotConfirmTranslate')), findsOneWidget);
    expect(find.byKey(const Key('screenshotRecognizedText')), findsOneWidget);
  });

  testWidgets('完成阶段显示截图、原文、译文与操作按钮', (tester) async {
    await pumpPage(
      tester,
      state: ScreenshotState(
        stage: ScreenshotStage.done,
        pngBytes: _kTestPng,
        recognizedText: 'hello world',
        translatedText: '你好，世界！',
      ),
    );
    expect(find.byKey(const Key('screenshotImage')), findsOneWidget);
    expect(find.byKey(const Key('screenshotRecognizedText')), findsOneWidget);
    expect(find.byKey(const Key('screenshotTranslatedText')), findsOneWidget);
    expect(find.byKey(const Key('screenshotCopyButton')), findsOneWidget);
    expect(find.byKey(const Key('screenshotReshootButton')), findsOneWidget);
    expect(find.text('原文'), findsOneWidget);
    expect(find.text('中文译文'), findsOneWidget);
  });

  testWidgets('英文界面完成阶段文案可见', (tester) async {
    await pumpPage(
      tester,
      state: const ScreenshotState(
        stage: ScreenshotStage.done,
        pngBytes: null,
        recognizedText: 'hello world',
        translatedText: '你好，世界！',
      ),
      locale: const Locale('en'),
    );
    expect(find.text('Original'), findsOneWidget);
    expect(find.text('Chinese translation'), findsOneWidget);
    expect(find.text('Copy'), findsOneWidget);
    expect(find.text('New Screenshot'), findsOneWidget);
  });

  testWidgets('暗色模式下完成阶段正常渲染', (tester) async {
    await pumpPage(
      tester,
      state: ScreenshotState(
        stage: ScreenshotStage.done,
        pngBytes: _kTestPng,
        recognizedText: 'hello world',
        translatedText: '你好，世界！',
      ),
      themeMode: ThemeMode.dark,
    );
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('screenshotTranslatedText')), findsOneWidget);
  });

  testWidgets('长译文可滚动且不溢出', (tester) async {
    await pumpPage(
      tester,
      state: ScreenshotState(
        stage: ScreenshotStage.done,
        pngBytes: null,
        recognizedText: 'hello world',
        translatedText: '很长的译文' * 200,
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('screenshotTranslatedText')), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -800));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('缺凭据失败显示前往配置按钮', (tester) async {
    await pumpPage(
      tester,
      state: const ScreenshotState(
        stage: ScreenshotStage.failed,
        failure: ScreenshotFailure.missingCredentials,
        recognizedText: 'hello world',
      ),
    );
    expect(find.byKey(const Key('screenshotFailureText')), findsOneWidget);
    expect(find.byKey(const Key('screenshotGoConfigButton')), findsOneWidget);
    expect(find.text('缺少翻译凭据，请到设置中配置'), findsOneWidget);

    await pumpPage(
      tester,
      state: const ScreenshotState(
        stage: ScreenshotStage.failed,
        failure: ScreenshotFailure.missingCredentials,
        recognizedText: 'hello world',
      ),
      locale: const Locale('en'),
    );
    expect(
      find.text(
        'Translation credentials are missing. Configure them in Settings.',
      ),
      findsOneWidget,
    );
    expect(find.text('Go to Settings'), findsOneWidget);
  });

  testWidgets('权限失败说明已授权重启与 IDE 权限，浅深色均可重新截图', (tester) async {
    for (final theme in [ThemeMode.light, ThemeMode.dark]) {
      await pumpPage(
        tester,
        state: const ScreenshotState(
          stage: ScreenshotStage.failed,
          failure: ScreenshotFailure.permissionDenied,
        ),
        themeMode: theme,
      );
      final message = tester
          .widget<Text>(find.byKey(const Key('screenshotFailureText')))
          .data!;
      expect(message, contains('已授权'));
      expect(message, contains('独立启动'));
      expect(message, contains('IDE'));
      expect(
        find.byKey(const Key('screenshotFailedReshootButton')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('普通失败显示重试与重新截图按钮', (tester) async {
    await pumpPage(
      tester,
      state: const ScreenshotState(
        stage: ScreenshotStage.failed,
        failure: ScreenshotFailure.translationFailed,
        recognizedText: 'hello world',
      ),
    );
    expect(find.byKey(const Key('screenshotRetryButton')), findsOneWidget);
    expect(
      find.byKey(const Key('screenshotFailedReshootButton')),
      findsOneWidget,
    );
    expect(find.text('翻译失败，请重试'), findsOneWidget);
  });

  testWidgets('点击按英文翻译后完成并显示译文', (tester) async {
    await pumpPage(
      tester,
      state: ScreenshotState.idle,
      ocrText: '谢谢你的帮助',
      useRealController: true,
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ScreenshotResultPage)),
    );
    await container.read(screenshotControllerProvider.notifier).startCapture();
    await settle(tester);
    expect(find.byKey(const Key('screenshotConfirmTranslate')), findsOneWidget);
    await tester.tap(find.byKey(const Key('screenshotConfirmTranslate')));
    await settle(tester);
    expect(find.text('你好，世界！'), findsOneWidget);
  });

  testWidgets('关闭按钮回到 idle 并释放截图', (tester) async {
    final container = await pumpPage(
      tester,
      state: ScreenshotState(
        stage: ScreenshotStage.done,
        pngBytes: _kTestPng,
        recognizedText: 'hello world',
        translatedText: '你好，世界！',
      ),
    );
    await tester.tap(find.byKey(const Key('screenshotCloseButton')));
    await settle(tester);
    final state = container.read(screenshotControllerProvider);
    expect(state.stage, ScreenshotStage.idle);
    expect(state.pngBytes, isNull);
  });
}
