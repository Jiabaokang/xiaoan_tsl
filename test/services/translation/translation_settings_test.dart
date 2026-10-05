import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:xiaoan_tsl/core/database/local_store.dart';
import 'package:xiaoan_tsl/services/translation/translation_settings.dart';

// 内存凭据替身：验证安全存储契约，不触碰系统 Keychain。
class _MemoryCredentials implements SecureCredentialStore {
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

  test('macOS 凭据读写删除均使用无需共享权限的本机钥匙串', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    const channel = MethodChannel(
      'plugins.it_nomads.com/flutter_secure_storage',
    );
    final calls = <MethodCall>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      final arguments = call.arguments as Map;
      final options = arguments['options'] as Map;
      if (options['usesDataProtectionKeychain'] != 'false') {
        throw PlatformException(
          code: 'Unexpected security result code',
          details: -34018,
        );
      }
      return call.method == 'read' ? 'test-value' : null;
    });
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      messenger.setMockMethodCallHandler(channel, null);
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final credentials = container.read(secureCredentialStoreProvider);

    await credentials.writeBaiduCredentials(
      appId: 'test-app',
      secret: 'test-secret',
    );
    expect(await credentials.hasBaiduCredentials(), isTrue);
    await credentials.deleteBaiduCredentials();
    expect(calls.map((call) => call.method), [
      'write',
      'write',
      'read',
      'read',
      'delete',
      'delete',
    ]);
  });

  test('凭据替身完整支持写入、读取、判断与删除', () async {
    final credentials = _MemoryCredentials();
    expect(await credentials.hasBaiduCredentials(), isFalse);

    await credentials.writeBaiduCredentials(appId: 'app-1', secret: 's3cret');
    expect(await credentials.hasBaiduCredentials(), isTrue);
    expect(await credentials.readBaiduAppId(), 'app-1');
    expect(await credentials.readBaiduSecret(), 's3cret');

    await credentials.deleteBaiduCredentials();
    expect(await credentials.hasBaiduCredentials(), isFalse);
    expect(await credentials.readBaiduAppId(), isNull);
    expect(await credentials.readBaiduSecret(), isNull);
  });

  test('普通设置与密钥分离：SQLite 设置不包含 secret', () async {
    final directory = await Directory.systemTemp.createTemp('xiaoan_settings_');
    try {
      final store = await LocalStore.open(
        path: path.join(directory.path, 'app.db'),
        legacyFile: File(path.join(directory.path, 'none.json')),
        factory: databaseFactoryFfi,
      );
      addTearDown(store.close);
      final credentials = _MemoryCredentials();

      // 普通服务配置只写 SQLite，密钥只写安全存储。
      await store.setSetting(TranslationSettingKeys.engine, 'baidu');
      await store.setSetting(TranslationSettingKeys.baiduProduct, 'openapi');
      await credentials.writeBaiduCredentials(
        appId: 'app-secret-9',
        secret: 'top-secret-value',
      );

      expect(await store.getSetting(TranslationSettingKeys.engine), 'baidu');
      expect(
        await store.getSetting(TranslationSettingKeys.baiduProduct),
        'openapi',
      );
      // 密钥键不允许出现在普通设置表中。
      expect(await store.getSetting('baidu_secret'), isNull);
      expect(await store.getSetting('baidu_app_id'), isNull);
      // 设置值本身不包含密钥内容。
      expect(
        await store.getSetting(TranslationSettingKeys.engine),
        isNot(contains('top-secret-value')),
      );
    } finally {
      await directory.delete(recursive: true);
    }
  });
}
