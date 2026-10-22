import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:xiaoan_tsl/features/translate/app_controller.dart';
import 'package:xiaoan_tsl/core/database/database_provider.dart';
import 'package:xiaoan_tsl/core/database/local_store.dart';
import 'package:xiaoan_tsl/services/translation/translation_service.dart';
import 'package:xiaoan_tsl/services/translation/apple_translation_service.dart';
import 'package:xiaoan_tsl/l10n/app_localizations.dart';
import 'package:xiaoan_tsl/services/translation/translation_service_provider.dart';
import 'package:xiaoan_tsl/services/language/language_detection_provider.dart';
import 'package:xiaoan_tsl/services/translation/model_service_provider.dart';

import '../../support/test_translation_services.dart';

// 用延迟完成的结果验证旧翻译请求不会覆盖新的输入。
class _DeferredService implements TranslationService {
  final completer = Completer<String>();

  @override
  String get engineId => 'demo';

  @override
  bool get requiresMlKitModels => false;

  @override
  Future<String> translate({
    required String text,
    required String sourceLanguage,
    required String targetLanguage,
  }) => completer.future;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);

  group('苹果首页请求', () {
    const channel = MethodChannel('test/home/apple_translation');
    late LocalStore store;
    late ProviderContainer container;
    late AppController controller;
    late Completer<void> preparing;
    late Completer<void> prepareStarted;
    late List<MethodCall> calls;
    Object? preparationError;
    Completer<String>? translating;

    setUp(() async {
      preparing = Completer<void>();
      prepareStarted = Completer<void>();
      calls = [];
      preparationError = null;
      translating = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            switch (call.method) {
              case 'appleTranslationAvailability':
                return {'status': 'installed'};
              case 'prepareAppleTranslation':
                prepareStarted.complete();
                await preparing.future;
                if (preparationError != null) throw preparationError!;
                return null;
              case 'translateText':
                return {
                  'requestId': (call.arguments as Map)['requestId'],
                  'translatedText': translating == null
                      ? '你好，世界！'
                      : await translating!.future,
                };
              case 'cancelAppleTranslation':
                return null;
              default:
                throw StateError('unexpected method ${call.method}');
            }
          });
      store = await LocalStore.open(
        path: inMemoryDatabasePath,
        legacyFile: File('/nonexistent/apple_home_history.json'),
        factory: databaseFactoryFfi,
      );
      container = ProviderContainer(
        overrides: [
          localStoreProvider.overrideWithValue(store),
          translationPlatformProvider.overrideWithValue(
            TranslationPlatform.macOS,
          ),
          translationServiceProvider.overrideWithValue(
            AppleTranslationService(channel: channel),
          ),
          languageDetectionProvider.overrideWithValue(
            TestLanguageDetectionService(),
          ),
          translationModelProvider.overrideWith((ref) {
            throw StateError('苹果请求不得读取 ML Kit 模型');
          }),
        ],
      );
      controller = container.read(appControllerProvider.notifier);
      await controller.initialize();
      await container.read(translationEngineProvider.notifier).ready;
      controller.setInput('Hello, world!');
    });

    tearDown(() async {
      container.dispose();
      await store.close();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('准备期间忙碌且无历史，完成后只保存 apple 真实结果', () async {
      final pending = controller.translate();
      await prepareStarted.future;
      final state = container.read(appControllerProvider);
      expect(state.phase, TranslationPhase.preparingTranslation);
      expect(state.phase.isBusy, isTrue);
      expect(state.localizedMessage(AppLocalizationsZh()), contains('准备'));
      expect(await store.search(''), isEmpty);
      expect(calls.where((c) => c.method == 'translateText'), isEmpty);
      preparing.complete();
      await pending;
      expect(
        container.read(appControllerProvider).phase,
        TranslationPhase.success,
      );
      expect(container.read(appControllerProvider).result?.engine, 'apple');
      expect((await store.search('')).single.translatedText, '你好，世界！');
      expect(
        calls.where((c) => c.method == 'prepareAppleTranslation'),
        hasLength(1),
      );
    });

    test('取消准备保留输入，晚到的准备完成不能翻译或保存', () async {
      final pending = controller.translate();
      await prepareStarted.future;
      controller.cancelTranslation();
      expect(
        container.read(appControllerProvider).phase,
        TranslationPhase.idle,
      );
      expect(container.read(appControllerProvider).input, 'Hello, world!');
      preparing.complete();
      await pending;
      expect(
        calls.where((c) => c.method == 'cancelAppleTranslation'),
        isNotEmpty,
      );
      expect(calls.where((c) => c.method == 'translateText'), isEmpty);
      expect(await store.search(''), isEmpty);
    });

    test('发布准备状态时同步取消不能再打开系统宿主', () async {
      final subscription = container.listen(appControllerProvider, (_, next) {
        if (next.phase == TranslationPhase.preparingTranslation) {
          controller.cancelTranslation();
        }
      });
      preparing.complete();
      await controller.translate();
      subscription.close();
      expect(
        container.read(appControllerProvider).phase,
        TranslationPhase.idle,
      );
      expect(
        calls.where((c) => c.method == 'prepareAppleTranslation'),
        isEmpty,
      );
      expect(await store.search(''), isEmpty);
    });

    for (final code in [
      'appleUnsupportedLanguage',
      'applePreparationFailed',
      'applePreparationTimeout',
      'appleBusy',
      'appleCancelled',
    ]) {
      test('$code 使用苹果错误出口且不保存历史', () async {
        preparationError = PlatformException(code: code);
        final pending = controller.translate();
        await prepareStarted.future;
        preparing.complete();
        await pending;
        final state = container.read(appControllerProvider);
        if (code == 'appleCancelled') {
          expect(state.phase, TranslationPhase.idle);
        } else {
          expect(state.failure, TranslationFailure.apple);
          expect(state.appleErrorCode, code);
          expect(
            state.localizedMessage(AppLocalizationsEn()),
            AppLocalizationsEn().appleTranslationError(code),
          );
        }
        expect(state.input, 'Hello, world!');
        expect(calls.where((c) => c.method == 'translateText'), isEmpty);
        expect(await store.search(''), isEmpty);
      });
    }

    test('直接更改服务偏好立即撤销准备，不依赖首页切换入口', () async {
      final pending = controller.translate();
      await prepareStarted.future;
      await container
          .read(translationEngineProvider.notifier)
          .setEngine('baidu');
      expect(
        container.read(appControllerProvider).phase,
        TranslationPhase.idle,
      );
      preparing.complete();
      await pending;
      expect(calls.where((c) => c.method == 'translateText'), isEmpty);
      expect(await store.search(''), isEmpty);
    });

    test('翻译期间改变输入丢弃晚到结果和历史', () async {
      translating = Completer<String>();
      preparing.complete();
      final pending = controller.translate();
      while (!calls.any((call) => call.method == 'translateText')) {
        await Future<void>.delayed(Duration.zero);
      }
      controller.setInput('New input');
      translating!.complete('过期译文');
      await pending;
      expect(container.read(appControllerProvider).result, isNull);
      expect(container.read(appControllerProvider).input, 'New input');
      expect(await store.search(''), isEmpty);
    });

    test('控制器销毁时取消自己持有的苹果请求', () async {
      final pending = controller.translate();
      await prepareStarted.future;
      container.dispose();
      preparing.complete();
      await pending;
      expect(
        calls.where((c) => c.method == 'cancelAppleTranslation'),
        isNotEmpty,
      );
      expect(calls.where((c) => c.method == 'translateText'), isEmpty);
      expect(await store.search(''), isEmpty);
    });
  });

  test('已选原文语言时短文本和完整文本都能翻译并写入历史', () async {
    final directory = await Directory.systemTemp.createTemp('xiaoan_state_');
    try {
      final store = await LocalStore.open(
        path: path.join(directory.path, 'app.db'),
        legacyFile: File(path.join(directory.path, 'none.json')),
        factory: databaseFactoryFfi,
      );
      final container = ProviderContainer(
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
        ],
      );
      final controller = container.read(appControllerProvider.notifier);
      await controller.initialize();
      controller.setInput('Hi');
      await controller.translate();
      expect(
        container.read(appControllerProvider).phase,
        TranslationPhase.success,
      );
      controller.setInput('Hello, world!');
      await controller.translate();
      expect(
        container.read(appControllerProvider).result?.translatedText,
        '你好，世界！',
      );
      expect((await store.search('Hello')).length, 1);
      expect((await store.search('Hi')).length, 1);
      container.dispose();
      await store.close();
    } finally {
      await directory.delete(recursive: true);
    }
  });

  test('输入改变后忽略晚到的旧译文', () async {
    final directory = await Directory.systemTemp.createTemp('xiaoan_state_');
    try {
      final store = await LocalStore.open(
        path: path.join(directory.path, 'app.db'),
        legacyFile: File(path.join(directory.path, 'none.json')),
        factory: databaseFactoryFfi,
      );
      final service = _DeferredService();
      final container = ProviderContainer(
        overrides: [
          localStoreProvider.overrideWithValue(store),
          translationServiceProvider.overrideWithValue(service),
          languageDetectionProvider.overrideWithValue(
            TestLanguageDetectionService(),
          ),
          translationModelProvider.overrideWithValue(
            DownloadedTranslationModels(),
          ),
        ],
      );
      final controller = container.read(appControllerProvider.notifier);
      await controller.initialize();
      controller.setInput('Hello, world!');
      final pending = controller.translate();
      controller.setInput('Good morning');
      service.completer.complete('旧结果');
      await pending;
      expect(container.read(appControllerProvider).result, isNull);
      expect(await store.search(''), isEmpty);
      container.dispose();
      await store.close();
    } finally {
      await directory.delete(recursive: true);
    }
  });

  test('默认目标语言与主题从本地设置恢复', () async {
    final directory = await Directory.systemTemp.createTemp('xiaoan_state_');
    try {
      final store = await LocalStore.open(
        path: path.join(directory.path, 'app.db'),
        legacyFile: File(path.join(directory.path, 'none.json')),
        factory: databaseFactoryFfi,
      );
      var container = ProviderContainer(
        overrides: [localStoreProvider.overrideWithValue(store)],
      );
      var controller = container.read(appControllerProvider.notifier);
      await controller.initialize();
      await controller.setDefaultTargetLanguage('en');
      expect(container.read(appControllerProvider).sourceLanguage, 'zh');
      expect(container.read(appControllerProvider).targetLanguage, 'en');
      await controller.setThemeMode(ThemeMode.dark);
      container.dispose();

      container = ProviderContainer(
        overrides: [localStoreProvider.overrideWithValue(store)],
      );
      controller = container.read(appControllerProvider.notifier);
      await controller.initialize();
      expect(container.read(appControllerProvider).targetLanguage, 'en');
      expect(container.read(appControllerProvider).sourceLanguage, 'zh');
      expect(container.read(appControllerProvider).themeMode, ThemeMode.dark);
      container.dispose();
      await store.close();
    } finally {
      await directory.delete(recursive: true);
    }
  });
}
