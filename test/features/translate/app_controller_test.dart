import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:xiaoan_tsl/features/translate/app_controller.dart';
import 'package:xiaoan_tsl/core/database/database_provider.dart';
import 'package:xiaoan_tsl/core/database/local_store.dart';
import 'package:xiaoan_tsl/services/translation/translation_service.dart';
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
  Future<String> translate({
    required String text,
    required String sourceLanguage,
    required String targetLanguage,
  }) =>
      completer.future;
}

void main() {
  setUpAll(sqfliteFfiInit);

  test('短文本要求手选语言，成功翻译写入历史', () async {
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
        TranslationPhase.error,
      );
      controller.setSourceLanguage('en');
      controller.setInput('Hello, world!');
      await controller.translate();
      expect(
        container.read(appControllerProvider).result?.translatedText,
        '你好，世界！',
      );
      expect((await store.search('Hello')).length, 1);
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
      await controller.setThemeMode(ThemeMode.dark);
      container.dispose();

      container = ProviderContainer(
        overrides: [localStoreProvider.overrideWithValue(store)],
      );
      controller = container.read(appControllerProvider.notifier);
      await controller.initialize();
      expect(container.read(appControllerProvider).targetLanguage, 'en');
      expect(container.read(appControllerProvider).themeMode, ThemeMode.dark);
      container.dispose();
      await store.close();
    } finally {
      await directory.delete(recursive: true);
    }
  });
}
