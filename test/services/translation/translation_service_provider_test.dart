import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:xiaoan_tsl/core/database/database_provider.dart';
import 'package:xiaoan_tsl/core/database/local_store.dart';
import 'package:xiaoan_tsl/core/network/dio_provider.dart';
import 'package:xiaoan_tsl/services/translation/baidu_translation_service.dart';
import 'package:xiaoan_tsl/services/translation/apple_translation_service.dart';
import 'package:xiaoan_tsl/services/translation/model_service_provider.dart';
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
  TestWidgetsFlutterBinding.ensureInitialized();
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

  test(
    'macOS apple resolves override without reading network credentials or ML Kit',
    () async {
      await seedEngine('apple');
      final apple = AppleTranslationService();
      final container = ProviderContainer(
        overrides: [
          localStoreProvider.overrideWithValue(store),
          translationPlatformProvider.overrideWithValue(
            TranslationPlatform.macOS,
          ),
          appleTranslationServiceProvider.overrideWithValue(apple),
          dioProvider.overrideWith(
            (_) => throw StateError('No cloud requests'),
          ),
          secureCredentialStoreProvider.overrideWith(
            (_) => throw StateError('No credentials'),
          ),
          translationModelProvider.overrideWith(
            (_) => throw StateError('No ML Kit'),
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(translationEngineProvider.notifier).ready;
      final service = container.read(translationServiceProvider);
      expect(service, same(apple));
      expect(service.engineId, 'apple');
      await expectLater(
        service.translate(
          text: 'Hello',
          sourceLanguage: 'en',
          targetLanguage: 'zh',
        ),
        throwsA(isA<AppleTranslationException>()),
      );
      expect(container.read(translationServiceProvider), same(apple));
    },
  );

  for (final platform in [
    TranslationPlatform.android,
    TranslationPlatform.ios,
    TranslationPlatform.other,
  ]) {
    test(
      '$platform availability never creates apple service or calls channel',
      () async {
        final container = ProviderContainer(
          overrides: [
            translationPlatformProvider.overrideWithValue(platform),
            appleTranslationServiceProvider.overrideWith(
              (_) => throw StateError('No macOS channel'),
            ),
          ],
        );
        addTearDown(container.dispose);
        expect(
          await container.read(appleTranslationAvailabilityProvider.future),
          AppleTranslationAvailability.platformUnsupported,
        );
      },
    );
  }

  test(
    'macOS availability queries en/zh and refreshes after invalidation',
    () async {
      const channel = MethodChannel('test/apple_provider');
      final calls = <MethodCall>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return {'status': calls.length == 1 ? 'supported' : 'installed'};
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final container = ProviderContainer(
        overrides: [
          translationPlatformProvider.overrideWithValue(
            TranslationPlatform.macOS,
          ),
          appleTranslationServiceProvider.overrideWithValue(
            AppleTranslationService(channel: channel),
          ),
        ],
      );
      addTearDown(container.dispose);
      expect(
        await container.read(appleTranslationAvailabilityProvider.future),
        AppleTranslationAvailability.supported,
      );
      container.invalidate(appleTranslationAvailabilityProvider);
      expect(
        await container.read(appleTranslationAvailabilityProvider.future),
        AppleTranslationAvailability.installed,
      );
      expect(
        calls.every(
          (call) =>
              call.method == 'appleTranslationAvailability' &&
              (call.arguments as Map)['sourceLanguage'] == 'en' &&
              (call.arguments as Map)['targetLanguage'] == 'zh',
        ),
        isTrue,
      );
    },
  );
}
