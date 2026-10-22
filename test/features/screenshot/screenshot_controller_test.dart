import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:xiaoan_tsl/core/database/database_provider.dart';
import 'package:xiaoan_tsl/core/network/dio_provider.dart';
import 'package:xiaoan_tsl/features/translate/app_controller.dart';
import 'package:xiaoan_tsl/services/translation/apple_translation_service.dart';
import 'package:xiaoan_tsl/services/translation/model_service_provider.dart';
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
  final captureIds = <String>[];
  final ocrIds = <String>[];
  final cancelledIds = <String>[];
  Completer<void>? cancelDeferred;
  Completer<void>? resultWindowDeferred;

  @override
  Future<CaptureRegionResult> captureRegion(String requestId) async {
    captureCalls++;
    captureIds.add(requestId);
    final error = captureError;
    if (error != null) throw error;
    return capturePayload ?? _defaultPayload;
  }

  @override
  Future<String> recognizeText(String requestId, Uint8List pngBytes) async {
    ocrCalls++;
    ocrIds.add(requestId);
    return ocrText;
  }

  @override
  Future<String?> identifyLanguage(String text) async => 'en';

  @override
  Future<void> showResultWindow({
    required int displayId,
    required Rect selection,
  }) async {
    await resultWindowDeferred?.future;
  }

  @override
  Future<void> updateResult(Map<String, Object?> state) async {}

  @override
  Future<void> cancelCapture(String requestId) async {
    cancelledIds.add(requestId);
    await cancelDeferred?.future;
  }

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

// 模拟原生两阶段会话与单请求锁，真实 Apple 服务仍负责通道及错误处理。
class _AppleNative {
  static const channel = MethodChannel('test/screenshot/apple_translation');
  final calls = <MethodCall>[];
  Completer<void>? preparing;
  Completer<String>? translating;
  String? prepareErrorCode;
  String? translateErrorCode;
  String? activeId;
  bool lockRequests = false;
  bool cancelFails = false;

  List<String> ids(String method) => calls
      .where((call) => call.method == method)
      .map((call) => (call.arguments as Map)['requestId'] as String)
      .toList();

  Future<Object?> handle(MethodCall call) async {
    calls.add(call);
    if (call.method == 'appleTranslationAvailability') {
      return {'status': 'installed'};
    }
    final args = call.arguments as Map;
    final id = args['requestId'] as String;
    switch (call.method) {
      case 'prepareAppleTranslation':
        if (lockRequests && activeId != null) {
          throw PlatformException(code: 'appleBusy');
        }
        activeId = id;
        await preparing?.future;
        if (prepareErrorCode != null) {
          throw PlatformException(code: prepareErrorCode!);
        }
        return null;
      case 'translateText':
        if (!ids('prepareAppleTranslation').contains(id)) {
          throw PlatformException(code: 'appleInvalidRequest');
        }
        if (translateErrorCode != null) {
          throw PlatformException(code: translateErrorCode!);
        }
        return {
          'requestId': id,
          'translatedText': await translating?.future ?? '苹果译文',
        };
      case 'cancelAppleTranslation':
        if (id == activeId) activeId = null;
        if (cancelFails) throw PlatformException(code: 'cleanupFailed');
        return null;
      default:
        throw StateError('Unexpected Apple method: ${call.method}');
    }
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
  TestWidgetsFlutterBinding.ensureInitialized();
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
    if (translation is AppleTranslationService) {
      await store.setSetting('translation_engine', 'apple');
    }
    final container = ProviderContainer(
      overrides: [
        localStoreProvider.overrideWithValue(store),
        macosDesktopServiceProvider.overrideWithValue(desktop),
        if (translation is! AppleTranslationService)
          translationServiceProvider.overrideWithValue(translation),
        if (translation is AppleTranslationService) ...[
          appleTranslationServiceProvider.overrideWithValue(translation),
          translationPlatformProvider.overrideWithValue(
            TranslationPlatform.macOS,
          ),
          dioProvider.overrideWith((ref) => throw StateError('苹果不得调用百度 HTTP')),
          translationModelProvider.overrideWith(
            (ref) => throw StateError('苹果不得读取 ML Kit 模型'),
          ),
        ],
        languageDetectionProvider.overrideWithValue(
          TestLanguageDetectionService(),
        ),
        if (translateTimeout != null)
          screenshotControllerProvider.overrideWith(
            () => ScreenshotController(translateTimeout: translateTimeout),
          ),
      ],
    );
    await container.read(translationEngineProvider.notifier).ready;
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

  test('capture/OCR 使用同一 UUID，关闭仅取消当前真实请求 ID', () async {
    final desktop = _FakeDesktopService();
    final (container, store, dir) = await makeContainer(
      desktop: desktop,
      translation: _CountingTranslationService(),
    );
    final controller = container.read(screenshotControllerProvider.notifier);
    await controller.startCapture();
    final id = desktop.captureIds.single;
    expect(
      id,
      matches(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ),
      ),
    );
    expect(desktop.ocrIds, [id]);
    await controller.dismiss();
    expect(desktop.cancelledIds, [id]);
    await teardown(container, store, dir);
  });

  test('旧取消等待期间再次重截，不允许旧调用启动捕获或替换新状态', () async {
    final desktop = _FakeDesktopService();
    final (container, store, dir) = await makeContainer(
      desktop: desktop,
      translation: _CountingTranslationService(),
    );
    final controller = container.read(screenshotControllerProvider.notifier);
    await controller.startCapture();
    desktop.cancelDeferred = Completer<void>();
    final obsolete = controller.startCapture();
    final current = controller.startCapture();
    desktop.cancelDeferred!.complete();
    await Future.wait([obsolete, current]);
    expect(desktop.captureIds.length, 2);
    expect(desktop.captureIds.toSet().length, 2);
    expect(
      container.read(screenshotControllerProvider).stage,
      ScreenshotStage.done,
    );
    await teardown(container, store, dir);
  });

  test('展示结果窗口等待期间关闭，晚到窗口完成不得启动 OCR', () async {
    final desktop = _FakeDesktopService()
      ..resultWindowDeferred = Completer<void>();
    final translation = _CountingTranslationService();
    final (container, store, dir) = await makeContainer(
      desktop: desktop,
      translation: translation,
    );
    final controller = container.read(screenshotControllerProvider.notifier);
    final run = controller.startCapture();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await controller.dismiss();
    desktop.resultWindowDeferred!.complete();
    await run;
    expect(desktop.ocrCalls, 0);
    expect(translation.calls, 0);
    expect(
      container.read(screenshotControllerProvider).stage,
      ScreenshotStage.idle,
    );
    expect(await store.search(''), isEmpty);
    await teardown(container, store, dir);
  });

  group('苹果截图两阶段请求', () {
    late _AppleNative native;
    late ProviderContainer container;
    late LocalStore store;
    late Directory directory;
    late ScreenshotController controller;
    late _FakeDesktopService desktop;

    Future<void> waitStage(String stage) async {
      for (var i = 0; i < 100; i++) {
        if (container.read(screenshotControllerProvider).stage.name == stage) {
          return;
        }
        await Future<void>.delayed(const Duration(milliseconds: 2));
      }
      expect(container.read(screenshotControllerProvider).stage.name, stage);
    }

    setUp(() async {
      native = _AppleNative();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_AppleNative.channel, native.handle);
      desktop = _FakeDesktopService();
      (container, store, directory) = await makeContainer(
        desktop: desktop,
        translation: AppleTranslationService(channel: _AppleNative.channel),
        translateTimeout: const Duration(milliseconds: 40),
      );
      final home = container.read(appControllerProvider.notifier);
      await home.initialize();
      controller = container.read(screenshotControllerProvider.notifier);
    });

    tearDown(() async {
      await teardown(container, store, directory);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_AppleNative.channel, null);
    });

    test('准备超过翻译超时仍忙碌，完成后同 ID 翻译并只保存 apple 历史', () async {
      native.preparing = Completer<void>();
      final run = controller.startCapture();
      await waitStage('preparingTranslation');
      await Future<void>.delayed(const Duration(milliseconds: 80));
      final state = container.read(screenshotControllerProvider);
      expect(state.stage.name, 'preparingTranslation');
      expect(state.busy, isTrue);
      expect(state.recognizedText, 'hello world');
      expect(native.ids('translateText'), isEmpty);
      expect(await store.search(''), isEmpty);
      native.preparing!.complete();
      await run;
      expect(
        container.read(screenshotControllerProvider).stage,
        ScreenshotStage.done,
      );
      final prepared = native.ids('prepareAppleTranslation').single;
      expect(native.ids('translateText'), [prepared]);
      expect(prepared, isNot(desktop.captureIds.single));
      expect(native.calls.first.arguments, {
        'sourceLanguage': 'en',
        'targetLanguage': 'zh',
      });
      final records = await store.search('');
      expect(records, hasLength(1));
      expect(records.single.engine, 'apple');
      expect(records.single.translatedText, '苹果译文');
    });

    test('准备后翻译超时取消本 ID，晚到译文不写历史；重试使用新 ID', () async {
      native.translating = Completer<String>();
      final lateTranslation = native.translating!;
      await controller.startCapture();
      final failed = container.read(screenshotControllerProvider);
      expect(failed.stage, ScreenshotStage.failed);
      expect(failed.failure, ScreenshotFailure.timeout);
      final oldId = native.ids('prepareAppleTranslation').single;
      expect(native.ids('cancelAppleTranslation'), contains(oldId));
      lateTranslation.complete('超时的旧译文');
      await Future<void>.delayed(Duration.zero);
      expect(
        container.read(screenshotControllerProvider).translatedText,
        isNull,
      );
      expect(await store.search(''), isEmpty);
      native.translating = null;
      await controller.retry();
      expect(native.ids('prepareAppleTranslation').toSet(), hasLength(2));
      expect(desktop.ocrCalls, 1);
      expect((await store.search('')).single.translatedText, '苹果译文');
    });

    for (final phase in ['prepare', 'translate']) {
      for (final action in ['dismiss', 'switch', 'dispose', 'reshoot']) {
        test('$phase 期间 $action 使旧请求失效，晚到结果不覆盖新状态或历史', () async {
          if (phase == 'prepare') {
            native.preparing = Completer<void>();
          } else {
            native.translating = Completer<String>();
          }
          final oldPreparation = native.preparing;
          final oldTranslation = native.translating;
          final oldRun = controller.startCapture();
          await waitStage(
            phase == 'prepare' ? 'preparingTranslation' : 'translating',
          );
          final oldId = native.ids('prepareAppleTranslation').single;
          switch (action) {
            case 'dismiss':
              await controller.dismiss();
            case 'switch':
              await container
                  .read(translationEngineProvider.notifier)
                  .setEngine('baidu');
            case 'dispose':
              container.invalidate(screenshotControllerProvider);
              await container.pump();
            case 'reshoot':
              native.preparing = null;
              native.translating = null;
              await controller.startCapture();
          }
          expect(native.ids('cancelAppleTranslation'), contains(oldId));
          oldPreparation?.complete();
          oldTranslation?.complete('失效旧译文');
          await oldRun;
          final state = container.read(screenshotControllerProvider);
          if (action == 'reshoot') {
            expect(state.stage, ScreenshotStage.done);
            expect(state.translatedText, '苹果译文');
            expect(native.ids('prepareAppleTranslation').toSet(), hasLength(2));
            expect((await store.search('')).single.translatedText, '苹果译文');
          } else {
            expect(state.stage, ScreenshotStage.idle);
            expect(state.translatedText, isNull);
            expect(await store.search(''), isEmpty);
          }
          if (phase == 'prepare') {
            expect(native.ids('translateText'), isNot(contains(oldId)));
          }
        });
      }
    }

    for (final phase in ['prepare', 'translate']) {
      for (final code in [
        'appleCancelled',
        'appleUnsupported',
        'appleUnsupportedLanguage',
        'applePreparationFailed',
        'applePreparationTimeout',
        'appleBusy',
        'appleTimeout',
        'appleInvalidArguments',
        'appleInvalidRequest',
        'appleTranslationFailed',
      ]) {
        test('$phase 的 $code 保留类型化错误且无百度或历史回退', () async {
          if (phase == 'prepare') {
            native.prepareErrorCode = code;
          } else {
            native.translateErrorCode = code;
          }
          native.cancelFails = true;
          await controller.startCapture();
          final state = container.read(screenshotControllerProvider);
          if (code == 'appleCancelled') {
            expect(state.stage, ScreenshotStage.idle);
          } else {
            expect(state.stage, ScreenshotStage.failed);
            expect(state.failure, ScreenshotFailure.apple);
            expect(state.appleErrorCode, code);
            expect(state.recognizedText, 'hello world');
          }
          expect(await store.search(''), isEmpty);
        });
      }
    }

    for (final phase in ['prepare', 'translate']) {
      test('旧 $phase 晚到清理时，新准备宿主仍属于新 ID', () async {
        final oldPreparation = Completer<void>();
        final oldTranslation = Completer<String>();
        if (phase == 'prepare') {
          native.preparing = oldPreparation;
        } else {
          native.translating = oldTranslation;
        }
        final oldRun = controller.startCapture();
        await waitStage(
          phase == 'prepare' ? 'preparingTranslation' : 'translating',
        );
        final oldId = native.activeId;
        final newPreparation = Completer<void>();
        native.preparing = newPreparation;
        native.translating = null;
        final newRun = controller.startCapture();
        await Future<void>.delayed(const Duration(milliseconds: 10));
        final newId = native.activeId;
        expect(newId, isNot(oldId));
        expect(newId, isNotNull);
        if (phase == 'prepare') {
          oldPreparation.complete();
        } else {
          oldTranslation.complete('旧翻译');
        }
        await oldRun;
        await Future<void>.delayed(Duration.zero);
        expect(native.activeId, newId);
        expect(native.ids('cancelAppleTranslation'), isNot(contains(newId)));
        expect(
          container.read(screenshotControllerProvider).stage.name,
          'preparingTranslation',
        );
        expect(await store.search(''), isEmpty);
        newPreparation.complete();
        await newRun;
        expect((await store.search('')).single.translatedText, '苹果译文');
      });
    }

    test('准备阶段同步取消时不再打开系统准备宿主', () async {
      final subscription = container.listen(screenshotControllerProvider, (
        _,
        next,
      ) {
        if (next.stage == ScreenshotStage.preparingTranslation) {
          unawaited(controller.dismiss());
        }
      });
      addTearDown(subscription.close);
      await controller.startCapture();
      expect(
        container.read(screenshotControllerProvider).stage,
        ScreenshotStage.idle,
      );
      expect(native.ids('prepareAppleTranslation'), isEmpty);
      expect(native.ids('translateText'), isEmpty);
      expect(await store.search(''), isEmpty);
    });

    test('控制器销毁重建后 capture 与苹果请求 UUID 均不复用', () async {
      await controller.startCapture();
      container.invalidate(screenshotControllerProvider);
      await container.pump();
      controller = container.read(screenshotControllerProvider.notifier);
      await controller.startCapture();
      final ids = [
        ...desktop.captureIds,
        ...native.ids('prepareAppleTranslation'),
      ];
      expect(ids.toSet(), hasLength(4));
      for (final id in ids) {
        expect(
          id,
          matches(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
          ),
        );
      }
    });

    for (final homeFirst in [true, false]) {
      test('${homeFirst ? '首页' : '截图'}占用原生时另一控制器 busy 不取消占用 ID', () async {
        native.lockRequests = true;
        native.preparing = Completer<void>();
        final home = container.read(appControllerProvider.notifier);
        home.setInput('Hello from home');
        final ownerRun = homeFirst
            ? home.translate()
            : controller.startCapture();
        for (var i = 0; i < 100 && native.activeId == null; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 2));
        }
        final ownerId = native.activeId;
        expect(ownerId, isNotNull);
        await (homeFirst ? controller.startCapture() : home.translate());
        if (homeFirst) {
          final state = container.read(screenshotControllerProvider);
          expect(state.failure, ScreenshotFailure.apple);
          expect(state.appleErrorCode, 'appleBusy');
          expect(
            container.read(appControllerProvider).phase.name,
            'preparingTranslation',
          );
        } else {
          final state = container.read(appControllerProvider);
          expect(state.appleErrorCode, 'appleBusy');
          expect(
            container.read(screenshotControllerProvider).stage.name,
            'preparingTranslation',
          );
        }
        expect(native.activeId, ownerId);
        expect(native.ids('cancelAppleTranslation'), isNot(contains(ownerId)));
        expect(native.ids('prepareAppleTranslation').toSet(), hasLength(2));
        expect(await store.search(''), isEmpty);
        native.preparing!.complete();
        await ownerRun;
        expect((await store.search('')).single.engine, 'apple');
        expect(
          homeFirst
              ? container.read(appControllerProvider).result?.translatedText
              : container.read(screenshotControllerProvider).translatedText,
          '苹果译文',
        );
      });
    }
  });
}
