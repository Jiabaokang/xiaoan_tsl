import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:xiaoan_tsl/core/database/database_provider.dart';
import 'package:xiaoan_tsl/core/database/local_store.dart';
import 'package:xiaoan_tsl/features/screenshot/screenshot_controller.dart';
import 'package:xiaoan_tsl/features/history/history_store.dart';
import 'package:xiaoan_tsl/services/desktop/macos_desktop_service.dart';
import 'package:xiaoan_tsl/services/language/language_detection_provider.dart';
import 'package:xiaoan_tsl/services/translation/baidu_translation_service.dart';
import 'package:xiaoan_tsl/services/translation/translation_service.dart';
import 'package:xiaoan_tsl/services/translation/translation_service_provider.dart';

import '../../support/test_translation_services.dart';

// 桌面通道替身：可控的捕获结果、OCR 结果与错误。
class _FakeDesktopService implements MacosDesktopService {
  _FakeDesktopService({
    this.capturePayload,
    this.captureError,
    this.ocrText = 'hello world',
  });

  CaptureRegionResult? capturePayload;
  Object? captureError;
  String ocrText;

  int captureCalls = 0;
  int ocrCalls = 0;

  @override
  Future<CaptureRegionResult> captureRegion(String requestId) async {
    captureCalls++;
    final error = captureError;
    if (error != null) throw error;
    return capturePayload ?? _defaultPayload;
  }

  @override
  Future<String> recognizeText(String requestId, Uint8List pngBytes) async {
    ocrCalls++;
    return ocrText;
  }

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

// 翻译服务替身：记录调用次数并支持挂起/抛错。
class _CountingTranslationService implements TranslationService {
  _CountingTranslationService({this.error, this.deferred});

  Object? error;
  Completer<String>? deferred;

  int calls = 0;
  String? lastSource;
  String? lastTarget;

  @override
  String get engineId => 'baidu';

  @override
  bool get requiresMlKitModels => false;

  @override
  Future<String> translate({
    required String text,
    required String sourceLanguage,
    required String targetLanguage,
  }) async {
    lastSource = sourceLanguage;
    lastTarget = targetLanguage;
    // 模拟真实服务的凭据预检：缺凭据在发起请求前抛出，不计入 API 调用。
    if (error is BaiduConfigException) throw error!;
    calls++;
    final completer = deferred;
    if (completer != null) return completer.future;
    final err = error;
    if (err != null) throw err;
    return '你好，世界！';
  }
}

// 历史保存必失败的 LocalStore 包装。
class _ThrowingSaveStore implements LocalStore {
  _ThrowingSaveStore(this._base);

  final LocalStore _base;

  @override
  Future<void> setSetting(String key, String value) =>
      _base.setSetting(key, value);

  @override
  Future<String?> getSetting(String key) => _base.getSetting(key);

  @override
  Future<List<TranslationRecord>> search(
    String query, {
    bool favoritesOnly = false,
  }) => _base.search(query, favoritesOnly: favoritesOnly);

  @override
  Future<TranslationRecord?> getRecord(String id) => _base.getRecord(id);

  @override
  Future<TranslationRecord> saveRecord(TranslationRecord record) async {
    throw StateError('模拟历史保存失败');
  }

  @override
  Future<void> setFavorite(String id, bool value) =>
      _base.setFavorite(id, value);

  @override
  Future<void> deleteRecord(String id) => _base.deleteRecord(id);

  @override
  Future<void> clearRecords() => _base.clearRecords();

  @override
  Future<void> close() => _base.close();
}

CaptureRegionResult _payload({bool cancelled = false}) => CaptureRegionResult(
  requestId: 'shot-1',
  cancelled: cancelled,
  pngBytes: cancelled ? null : Uint8List.fromList([1, 2, 3]),
  displayId: cancelled ? null : 1001,
  selection: cancelled ? null : const Rect.fromLTWH(10, 20, 300, 120),
  pixelWidth: 600,
  pixelHeight: 240,
);

// 桌面替身的默认捕获结果。
final _defaultPayload = _payload();

void main() {
  setUpAll(sqfliteFfiInit);

  Future<(ProviderContainer, LocalStore, Directory)> makeContainer({
    required MacosDesktopService desktop,
    required TranslationService translation,
    Duration? translateTimeout,
  }) async {
    final directory = await Directory.systemTemp.createTemp(
      'xiaoan_screenshot_',
    );
    final store = await LocalStore.open(
      path: path.join(directory.path, 'app.db'),
      legacyFile: File(path.join(directory.path, 'none.json')),
      factory: databaseFactoryFfi,
    );
    final container = ProviderContainer(
      overrides: [
        localStoreProvider.overrideWithValue(store),
        macosDesktopServiceProvider.overrideWithValue(desktop),
        translationServiceProvider.overrideWithValue(translation),
        languageDetectionProvider.overrideWithValue(
          TestLanguageDetectionService(),
        ),
        if (translateTimeout != null)
          screenshotControllerProvider.overrideWith(
            () => ScreenshotController(translateTimeout: translateTimeout),
          ),
      ],
    );
    return (container, store, directory);
  }

  Future<void> teardown(
    ProviderContainer container,
    LocalStore store,
    Directory directory,
  ) async {
    container.dispose();
    await store.close();
    await directory.delete(recursive: true);
  }

  test('捕获取消回到 idle，不调用翻译 API', () async {
    final (container, store, dir) = await makeContainer(
      desktop: _FakeDesktopService(capturePayload: _payload(cancelled: true)),
      translation: _CountingTranslationService(),
    );
    final translation =
        container.read(translationServiceProvider)
            as _CountingTranslationService;
    await container.read(screenshotControllerProvider.notifier).startCapture();
    expect(
      container.read(screenshotControllerProvider).stage,
      ScreenshotStage.idle,
    );
    expect(translation.calls, 0);
    expect((await store.search('')).length, 0);
    await teardown(container, store, dir);
  });

  test('权限被拒绝进入 failed，不调用翻译 API', () async {
    final (container, store, dir) = await makeContainer(
      desktop: _FakeDesktopService(
        captureError: const MacosDesktopPermissionException('无权限'),
      ),
      translation: _CountingTranslationService(),
    );
    final translation =
        container.read(translationServiceProvider)
            as _CountingTranslationService;
    await container.read(screenshotControllerProvider.notifier).startCapture();
    final state = container.read(screenshotControllerProvider);
    expect(state.stage, ScreenshotStage.failed);
    expect(state.failure, ScreenshotFailure.permissionDenied);
    expect(translation.calls, 0);
    await teardown(container, store, dir);
  });

  test('OCR 空内容进入 failed，不调用翻译 API', () async {
    final (container, store, dir) = await makeContainer(
      desktop: _FakeDesktopService(ocrText: '   '),
      translation: _CountingTranslationService(),
    );
    final translation =
        container.read(translationServiceProvider)
            as _CountingTranslationService;
    await container.read(screenshotControllerProvider.notifier).startCapture();
    final state = container.read(screenshotControllerProvider);
    expect(state.stage, ScreenshotStage.failed);
    expect(state.failure, ScreenshotFailure.noText);
    expect(translation.calls, 0);
    await teardown(container, store, dir);
  });

  test('超过 5000 字符进入 failed，不调用翻译 API', () async {
    final (container, store, dir) = await makeContainer(
      desktop: _FakeDesktopService(ocrText: 'a' * 5001),
      translation: _CountingTranslationService(),
    );
    final translation =
        container.read(translationServiceProvider)
            as _CountingTranslationService;
    await container.read(screenshotControllerProvider.notifier).startCapture();
    final state = container.read(screenshotControllerProvider);
    expect(state.stage, ScreenshotStage.failed);
    expect(state.failure, ScreenshotFailure.tooLong);
    expect(translation.calls, 0);
    await teardown(container, store, dir);
  });

  test('非英文先确认，确认后才调用 API 并保存历史', () async {
    final (container, store, dir) = await makeContainer(
      desktop: _FakeDesktopService(ocrText: '谢谢你的帮助'),
      translation: _CountingTranslationService(),
    );
    final translation =
        container.read(translationServiceProvider)
            as _CountingTranslationService;
    final controller = container.read(screenshotControllerProvider.notifier);
    await controller.startCapture();
    var state = container.read(screenshotControllerProvider);
    expect(state.stage, ScreenshotStage.needsConfirm);
    expect(state.confirmRequired, isTrue);
    expect(state.recognizedText, '谢谢你的帮助');
    expect(translation.calls, 0);
    await controller.confirmAndTranslate();
    state = container.read(screenshotControllerProvider);
    expect(state.stage, ScreenshotStage.done);
    expect(state.translatedText, '你好，世界！');
    expect(translation.calls, 1);
    expect(translation.lastSource, 'en');
    expect(translation.lastTarget, 'zh');
    expect((await store.search('谢谢你的帮助')).length, 1);
    await teardown(container, store, dir);
  });

  test('英文直接翻译并保存历史', () async {
    final (container, store, dir) = await makeContainer(
      desktop: _FakeDesktopService(ocrText: 'hello world'),
      translation: _CountingTranslationService(),
    );
    final translation =
        container.read(translationServiceProvider)
            as _CountingTranslationService;
    await container.read(screenshotControllerProvider.notifier).startCapture();
    final state = container.read(screenshotControllerProvider);
    expect(state.stage, ScreenshotStage.done);
    expect(state.translatedText, '你好，世界！');
    expect(translation.calls, 1);
    expect((await store.search('hello world')).length, 1);
    await teardown(container, store, dir);
  });

  test('缺凭据进入 failed，API 调用次数为零', () async {
    final (container, store, dir) = await makeContainer(
      desktop: _FakeDesktopService(),
      translation: _CountingTranslationService(
        error: const BaiduConfigException('缺少凭据'),
      ),
    );
    final translation =
        container.read(translationServiceProvider)
            as _CountingTranslationService;
    await container.read(screenshotControllerProvider.notifier).startCapture();
    final state = container.read(screenshotControllerProvider);
    expect(state.stage, ScreenshotStage.failed);
    expect(state.failure, ScreenshotFailure.missingCredentials);
    expect(translation.calls, 0);
    await teardown(container, store, dir);
  });

  test('翻译超时进入 failed', () async {
    final (container, store, dir) = await makeContainer(
      desktop: _FakeDesktopService(),
      translation: _CountingTranslationService(deferred: Completer<String>()),
      translateTimeout: const Duration(milliseconds: 100),
    );
    final controller = container.read(screenshotControllerProvider.notifier);
    await controller.startCapture();
    final state = container.read(screenshotControllerProvider);
    expect(state.stage, ScreenshotStage.failed);
    expect(state.failure, ScreenshotFailure.timeout);
    await teardown(container, store, dir);
  });

  test('新截图开始后旧翻译响应不显示也不入历史', () async {
    final first = Completer<String>();
    final translation = _CountingTranslationService(deferred: first);
    final (container, store, dir) = await makeContainer(
      desktop: _FakeDesktopService(),
      translation: translation,
    );
    final controller = container.read(screenshotControllerProvider.notifier);
    // 不等待整个流程：翻译会挂起在未完成的响应上。
    final run1 = controller.startCapture();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(
      container.read(screenshotControllerProvider).stage,
      ScreenshotStage.translating,
    );
    // 旧会话翻译未完成时开启新截图。
    final second = Completer<String>();
    translation.deferred = second;
    final run2 = controller.startCapture();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(
      container.read(screenshotControllerProvider).stage,
      ScreenshotStage.translating,
    );
    // 旧响应晚到：必须被丢弃。
    first.complete('旧译文');
    await run1;
    await Future<void>.delayed(Duration.zero);
    var state = container.read(screenshotControllerProvider);
    expect(state.stage, ScreenshotStage.translating);
    expect(state.translatedText, isNull);
    // 新响应正常展示并保存历史。
    second.complete('新译文');
    await run2;
    state = container.read(screenshotControllerProvider);
    expect(state.stage, ScreenshotStage.done);
    expect(state.translatedText, '新译文');
    expect((await store.search('')).length, 1);
    await teardown(container, store, dir);
  });

  test('服务切换使旧会话失效', () async {
    final deferred = Completer<String>();
    final translation = _CountingTranslationService(deferred: deferred);
    final (container, store, dir) = await makeContainer(
      desktop: _FakeDesktopService(),
      translation: translation,
    );
    final controller = container.read(screenshotControllerProvider.notifier);
    final run = controller.startCapture();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(
      container.read(screenshotControllerProvider).stage,
      ScreenshotStage.translating,
    );
    // 切换服务偏好。
    await container.read(translationEngineProvider.notifier).setEngine('mlkit');
    expect(
      container.read(screenshotControllerProvider).stage,
      ScreenshotStage.idle,
    );
    // 晚到的旧响应不得显示或写入历史。
    deferred.complete('旧译文');
    await run;
    expect(
      container.read(screenshotControllerProvider).stage,
      ScreenshotStage.idle,
    );
    expect(container.read(screenshotControllerProvider).translatedText, isNull);
    expect((await store.search('')).length, 0);
    await teardown(container, store, dir);
  });

  test('历史保存失败仍展示译文并标记提示', () async {
    final (container, _, dir) = await makeContainer(
      desktop: _FakeDesktopService(),
      translation: _CountingTranslationService(),
    );
    final store = _ThrowingSaveStore(container.read(localStoreProvider));
    // 用会失败的包装替换存储。
    final failingContainer = ProviderContainer(
      overrides: [
        localStoreProvider.overrideWithValue(store),
        macosDesktopServiceProvider.overrideWithValue(_FakeDesktopService()),
        translationServiceProvider.overrideWithValue(
          _CountingTranslationService(),
        ),
        languageDetectionProvider.overrideWithValue(
          TestLanguageDetectionService(),
        ),
      ],
    );
    await failingContainer
        .read(screenshotControllerProvider.notifier)
        .startCapture();
    final state = failingContainer.read(screenshotControllerProvider);
    expect(state.stage, ScreenshotStage.done);
    expect(state.translatedText, '你好，世界！');
    expect(state.historySaveFailed, isTrue);
    failingContainer.dispose();
    await teardown(container, container.read(localStoreProvider), dir);
  });

  test('关闭释放截图内存并回到 idle', () async {
    final (container, store, dir) = await makeContainer(
      desktop: _FakeDesktopService(),
      translation: _CountingTranslationService(),
    );
    final controller = container.read(screenshotControllerProvider.notifier);
    await controller.startCapture();
    expect(container.read(screenshotControllerProvider).pngBytes, isNotNull);
    await controller.dismiss();
    final state = container.read(screenshotControllerProvider);
    expect(state.stage, ScreenshotStage.idle);
    expect(state.pngBytes, isNull);
    await teardown(container, store, dir);
  });

  test('重试复用已识别原文，不重复 OCR', () async {
    final translation = _CountingTranslationService(
      error: const MacosDesktopCaptureException('首次失败'),
    );
    final (container, store, dir) = await makeContainer(
      desktop: _FakeDesktopService(ocrText: 'hello world'),
      translation: translation,
    );
    final controller = container.read(screenshotControllerProvider.notifier);
    await controller.startCapture();
    expect(
      container.read(screenshotControllerProvider).stage,
      ScreenshotStage.failed,
    );
    // 清除错误后重试：复用原文直接翻译。
    translation.error = null;
    await controller.retry();
    final state = container.read(screenshotControllerProvider);
    expect(state.stage, ScreenshotStage.done);
    expect(state.translatedText, '你好，世界！');
    expect(translation.calls, 2);
    expect(
      (container.read(macosDesktopServiceProvider) as _FakeDesktopService)
          .ocrCalls,
      1,
    );
    expect((await store.search('hello world')).length, 1);
    await teardown(container, store, dir);
  });
}
