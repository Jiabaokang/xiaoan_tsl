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
  bool get requiresMlKitModels => true;

  @override
  Future<String> translate({
    required String text,
    required String sourceLanguage,
    required String targetLanguage,
  }) async =>
      '真实译文';
}

// 在线服务替身：不检查模型，结果引擎为 baidu。
class _OnlineTranslator implements TranslationService {
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
      '在线译文';
}

// 延迟完成的在线服务，用于验证服务切换后旧结果失效。
class _DeferredOnlineTranslator implements TranslationService {
  final completer = Completer<String>();

  @override
  String get engineId => 'baidu';

  @override
  bool get requiresMlKitModels => false;

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

  test('输入属于原文语言时识别后翻译成另一种语言', () async {
    models.downloaded.add('zh');
    final controller = container.read(appControllerProvider.notifier);
    controller.setSourceLanguage('en');
    controller.setInput('Hello, world!');
    await controller.translate(downloadMissing: true);

    expect(detector.calls, 1);
    expect(models.checked, ['en', 'zh']);
    expect(models.downloads, ['en']);
    expect(
      container.read(appControllerProvider).result?.translatedText,
      '真实译文',
    );
    expect((await store.search('')).single.engine, 'mlkit');
  });

  test('缺少模型时先等待用户确认，不自动下载', () async {
    final controller = container.read(appControllerProvider.notifier);
    controller.setInput('Hello, world!');
    await controller.translate();

    expect(container.read(appControllerProvider).phase,
        TranslationPhase.modelDownloadRequired);
    expect(models.downloads, isEmpty);
    expect(await store.search(''), isEmpty);

    await controller.translate(downloadMissing: true);
    expect(
        container.read(appControllerProvider).phase, TranslationPhase.success);
    expect(models.downloads, ['en', 'zh']);
  });

  test('输入属于译文语言时自动反向翻译并保存实际语言方向', () async {
    detector.result = 'zh';
    final controller = container.read(appControllerProvider.notifier);
    controller.setSourceLanguage('en');
    controller.setTargetLanguage('zh');
    controller.setInput('你好，世界！');
    await controller.translate(downloadMissing: true);

    final result = container.read(appControllerProvider).result;
    expect(result?.sourceLanguage, 'zh');
    expect(result?.targetLanguage, 'en');
    expect((await store.search('')).single.targetLanguage, 'en');
  });

  test('输入语言不在所选两种语言中时不启动翻译', () async {
    detector.result = 'fr';
    final controller = container.read(appControllerProvider.notifier);
    controller.setSourceLanguage('en');
    controller.setTargetLanguage('zh');
    controller.setInput('Bonjour tout le monde');
    await controller.translate();

    expect(container.read(appControllerProvider).phase, TranslationPhase.error);
    expect(models.checked, isEmpty);
    expect(await store.search(''), isEmpty);
  });

  test('默认译文语言改变后撤销旧译文并保持两种不同语言', () async {
    final controller = container.read(appControllerProvider.notifier);
    controller.setInput('Hello, world!');
    await controller.translate(downloadMissing: true);
    expect(container.read(appControllerProvider).result, isNotNull);

    await controller.setDefaultTargetLanguage('en');
    final state = container.read(appControllerProvider);
    expect(state.sourceLanguage, 'zh');
    expect(state.targetLanguage, 'en');
    expect(state.result, isNull);
  });

  test('无法识别时提示补充输入，不触发模型下载', () async {
    detector.result = null;
    final controller = container.read(appControllerProvider.notifier);
    controller.setSourceLanguage('auto');
    controller.setInput('Something long enough');
    await controller.translate();

    expect(container.read(appControllerProvider).phase, TranslationPhase.error);
    expect(container.read(appControllerProvider).message, contains('更完整的内容'));
    expect(models.checked, isEmpty);
  });

  test('已选原文语言时，识别不确定仍按所选方向翻译', () async {
    detector.result = null;
    final controller = container.read(appControllerProvider.notifier);
    controller.setSourceLanguage('en');
    controller.setInput('Hello');
    await controller.translate(downloadMissing: true);

    final result = container.read(appControllerProvider).result;
    expect(result?.sourceLanguage, 'en');
    expect(result?.targetLanguage, 'zh');
    expect(result?.translatedText, '真实译文');
  });

  test('模型下载失败保留输入，显式重试后成功', () async {
    models.failDownload = true;
    final controller = container.read(appControllerProvider.notifier);
    controller.setSourceLanguage('en');
    controller.setInput('Hello, world!');
    await controller.translate(downloadMissing: true);
    expect(container.read(appControllerProvider).phase, TranslationPhase.error);
    expect(container.read(appControllerProvider).message, contains('模型'));
    expect(container.read(appControllerProvider).input, 'Hello, world!');
    expect(await store.search(''), isEmpty);

    models.failDownload = false;
    await controller.translate(downloadMissing: true);
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
    final pending = controller.translate(downloadMissing: true);
    await models.started.future.timeout(const Duration(seconds: 2));
    controller.setInput('New text');
    models.gate!.complete();
    await pending;

    expect(container.read(appControllerProvider).result, isNull);
    expect(await store.search(''), isEmpty);
  });

  test('在线服务不检查或下载模型，结果引擎为 baidu', () async {
    final online = ProviderContainer(
      overrides: [
        localStoreProvider.overrideWithValue(store),
        languageDetectionProvider.overrideWithValue(detector),
        translationModelProvider.overrideWithValue(models),
        translationServiceProvider.overrideWithValue(_OnlineTranslator()),
      ],
    );
    addTearDown(online.dispose);
    final controller = online.read(appControllerProvider.notifier);
    await controller.initialize();
    controller.setSourceLanguage('en');
    controller.setInput('Hello, world!');
    await controller.translate(downloadMissing: true);

    expect(models.checked, isEmpty);
    expect(models.downloads, isEmpty);
    final state = online.read(appControllerProvider);
    expect(state.result?.translatedText, '在线译文');
    expect(state.result?.engine, 'baidu');
    expect((await store.search('')).single.engine, 'baidu');
  });

  test('切换翻译服务后旧请求结果不更新界面也不写入历史', () async {
    final service = _DeferredOnlineTranslator();
    final switching = ProviderContainer(
      overrides: [
        localStoreProvider.overrideWithValue(store),
        languageDetectionProvider.overrideWithValue(detector),
        translationModelProvider.overrideWithValue(models),
        translationServiceProvider.overrideWithValue(service),
      ],
    );
    addTearDown(switching.dispose);
    final controller = switching.read(appControllerProvider.notifier);
    await controller.initialize();
    controller.setSourceLanguage('en');
    controller.setInput('Hello, world!');
    final pending = controller.translate();
    await pumpEventQueue();
    await controller.setTranslationEngine('mlkit');
    service.completer.complete('旧在线译文');
    await pending;

    expect(switching.read(appControllerProvider).result, isNull);
    expect(await store.search(''), isEmpty);
  });
}
