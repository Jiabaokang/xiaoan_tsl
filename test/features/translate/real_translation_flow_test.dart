import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:xiaoan_tsl/core/database/database_provider.dart';
import 'package:xiaoan_tsl/core/database/local_store.dart';
import 'package:xiaoan_tsl/features/translate/app_controller.dart';
import 'package:xiaoan_tsl/services/language/language_detection_provider.dart';
import 'package:xiaoan_tsl/services/language/mlkit_language_detection_service.dart';
import 'package:xiaoan_tsl/services/translation/mlkit_model_service.dart';
import 'package:xiaoan_tsl/services/translation/model_service_provider.dart';
import 'package:xiaoan_tsl/services/translation/translation_service.dart';
import 'package:xiaoan_tsl/services/translation/translation_service_provider.dart';

// 提供确定的识别结果，记录自动识别是否被调用。
class _Detector implements LanguageDetectionService {
  String? result = 'en';
  int calls = 0;

  @override
  Future<String?> identify(String text) async {
    calls++;
    return result;
  }
}

// 模拟模型下载和失败，检查控制器是否只处理缺少的模型。
class _Models implements TranslationModelService {
  final downloaded = <String>{};
  final checked = <String>[];
  final downloads = <String>[];
  bool failDownload = false;
  Completer<void>? gate;
  final started = Completer<void>();

  @override
  Future<bool> isDownloaded(String code) async {
    checked.add(code);
    return downloaded.contains(code);
  }

  @override
  Future<void> download(String code, {bool wifiOnly = true}) async {
    downloads.add(code);
    if (!started.isCompleted) started.complete();
    if (failDownload) throw StateError('下载失败');
    await gate?.future;
    downloaded.add(code);
  }

  @override
  Future<void> delete(String code) async => downloaded.remove(code);
}

// 返回固定内容，但标识真实引擎以验证历史记录来源。
class _Translator implements TranslationService {
  @override
  String get engineId => 'mlkit';

  @override
  Future<String> translate({
    required String text,
    required String sourceLanguage,
    required String targetLanguage,
  }) async => '真实译文';
}

void main() {
  setUpAll(sqfliteFfiInit);

  late Directory directory;
  late LocalStore store;
  late ProviderContainer container;
  late _Detector detector;
  late _Models models;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('xiaoan_real_flow_');
    store = await LocalStore.open(
      path: path.join(directory.path, 'app.db'),
      legacyFile: File(path.join(directory.path, 'history.json')),
      factory: databaseFactoryFfi,
    );
    detector = _Detector();
    models = _Models();
    container = ProviderContainer(
      overrides: [
        localStoreProvider.overrideWithValue(store),
        languageDetectionProvider.overrideWithValue(detector),
        translationModelProvider.overrideWithValue(models),
        translationServiceProvider.overrideWithValue(_Translator()),
      ],
    );
    await container.read(appControllerProvider.notifier).initialize();
  });

  tearDown(() async {
    container.dispose();
    await store.close();
    await directory.delete(recursive: true);
  });

  test('手选语言跳过识别，仅下载缺少的模型并保存引擎', () async {
    models.downloaded.add('zh');
    final controller = container.read(appControllerProvider.notifier);
    controller.setSourceLanguage('en');
    controller.setInput('Hello, world!');
    await controller.translate();

    expect(detector.calls, 0);
    expect(models.checked, ['en', 'zh']);
    expect(models.downloads, ['en']);
    expect(
      container.read(appControllerProvider).result?.translatedText,
      '真实译文',
    );
    expect((await store.search('')).single.engine, 'mlkit');
  });

  test('无法识别时要求手选，不触发模型下载', () async {
    detector.result = null;
    final controller = container.read(appControllerProvider.notifier);
    controller.setInput('Something long enough');
    await controller.translate();

    expect(container.read(appControllerProvider).phase, TranslationPhase.error);
    expect(container.read(appControllerProvider).message, contains('手动选择'));
    expect(models.checked, isEmpty);
  });

  test('模型下载失败保留输入，显式重试后成功', () async {
    models.failDownload = true;
    final controller = container.read(appControllerProvider.notifier);
    controller.setSourceLanguage('en');
    controller.setInput('Hello, world!');
    await controller.translate();
    expect(container.read(appControllerProvider).phase, TranslationPhase.error);
    expect(container.read(appControllerProvider).message, contains('模型'));
    expect(container.read(appControllerProvider).input, 'Hello, world!');
    expect(await store.search(''), isEmpty);

    models.failDownload = false;
    await controller.translate();
    expect(
      container.read(appControllerProvider).phase,
      TranslationPhase.success,
    );
    expect(models.downloads, ['en', 'en', 'zh']);
  });

  test('输入变化时忽略仍在下载的旧请求', () async {
    models.gate = Completer<void>();
    final controller = container.read(appControllerProvider.notifier);
    controller.setSourceLanguage('en');
    controller.setInput('Hello, world!');
    final pending = controller.translate();
    await models.started.future.timeout(const Duration(seconds: 2));
    controller.setInput('New text');
    models.gate!.complete();
    await pending;

    expect(container.read(appControllerProvider).result, isNull);
    expect(await store.search(''), isEmpty);
  });
}
