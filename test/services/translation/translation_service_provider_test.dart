import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:xiaoan_tsl/core/database/database_provider.dart';
import 'package:xiaoan_tsl/core/database/local_store.dart';
import 'package:xiaoan_tsl/core/network/dio_provider.dart';
import 'package:xiaoan_tsl/services/translation/baidu_translation_service.dart';
import 'package:xiaoan_tsl/services/translation/mlkit_translation_service.dart';
import 'package:xiaoan_tsl/services/translation/translation_service_provider.dart';
import 'package:xiaoan_tsl/services/translation/translation_settings.dart';

// 凭据安全存储内存替身，避免测试触碰系统 Keychain。
class _FakeCredentials implements SecureCredentialStore {
  String? appId;
  String? secret;

  @override
  Future<String?> readBaiduAppId() async => appId;

  @override
  Future<String?> readBaiduSecret() async => secret;

  @override
  Future<bool> hasBaiduCredentials() async =>
      appId != null &&
      appId!.isNotEmpty &&
      secret != null &&
      secret!.isNotEmpty;

  @override
  Future<void> writeBaiduCredentials({
    required String appId,
    required String secret,
  }) async {
    this.appId = appId;
    this.secret = secret;
  }

  @override
  Future<void> deleteBaiduCredentials() async {
    appId = null;
    secret = null;
  }
}

void main() {
  setUpAll(sqfliteFfiInit);

  late Directory directory;
  late LocalStore store;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('xiaoan_provider_');
    store = await LocalStore.open(
      path: path.join(directory.path, 'app.db'),
      legacyFile: File(path.join(directory.path, 'none.json')),
      factory: databaseFactoryFfi,
    );
  });

  tearDown(() async {
    await store.close();
    await directory.delete(recursive: true);
  });

  ProviderContainer buildContainer(
    TranslationPlatform platform, {
    String? savedEngine,
    SecureCredentialStore? credentials,
  }) {
    return ProviderContainer(
      overrides: [
        localStoreProvider.overrideWithValue(store),
        translationPlatformProvider.overrideWithValue(platform),
        secureCredentialStoreProvider.overrideWithValue(
          credentials ?? _FakeCredentials(),
        ),
        dioProvider.overrideWithValue(Dio()),
      ],
    );
  }

  Future<void> seedEngine(String engine) =>
      store.setSetting(TranslationSettingKeys.engine, engine);

  test('移动端未保存选择时默认使用 ML Kit 服务', () async {
    final container = buildContainer(TranslationPlatform.android);
    addTearDown(container.dispose);
    await pumpEventQueue();
    final service = container.read(translationServiceProvider);
    expect(service, isA<MlKitTranslationService>());
    expect(service.requiresMlKitModels, isTrue);
  });

  test('macOS 不创建 ML Kit，默认使用百度服务', () async {
    final container = buildContainer(TranslationPlatform.macOS);
    addTearDown(container.dispose);
    await pumpEventQueue();
    final service = container.read(translationServiceProvider);
    expect(service, isA<BaiduTranslationService>());
    expect(service, isNot(isA<MlKitTranslationService>()));
    expect(service.requiresMlKitModels, isFalse);
  });

  test('macOS 即使保存 mlkit 也回退到平台默认百度服务', () async {
    await seedEngine('mlkit');
    final container = buildContainer(TranslationPlatform.macOS);
    addTearDown(container.dispose);
    await container.read(translationEngineProvider.notifier).ready;
    final service = container.read(translationServiceProvider);
    expect(service, isA<BaiduTranslationService>());
    expect(service.engineId, 'baidu');
  });

  test('移动端保存 baidu 时解析为百度服务', () async {
    await seedEngine('baidu');
    final container = buildContainer(TranslationPlatform.android);
    addTearDown(container.dispose);
    await container.read(translationEngineProvider.notifier).ready;
    final service = container.read(translationServiceProvider);
    expect(service, isA<BaiduTranslationService>());
    expect(service.engineId, 'baidu');
    expect(service.requiresMlKitModels, isFalse);
  });

  test('未知或未交付服务配置回退平台默认并保持准确标识', () async {
    await seedEngine('apple');
    final container = buildContainer(TranslationPlatform.android);
    addTearDown(container.dispose);
    await container.read(translationEngineProvider.notifier).ready;
    final service = container.read(translationServiceProvider);
    expect(service, isA<MlKitTranslationService>());
    expect(service.engineId, 'mlkit');
  });
}
