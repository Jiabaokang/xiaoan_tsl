import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

// 翻译服务普通配置的稳定键名；密钥只走安全存储，不写入 SQLite。
abstract final class TranslationSettingKeys {
  static const engine = 'translation_engine';
  static const screenshotShortcut = 'screenshot_shortcut';
  static const screenshotTarget = 'screenshot_target';
  static const baiduProduct = 'baidu_product';
}

// 凭据安全存储边界；测试使用内存替身，生产使用系统 Keychain/Keystore。
abstract interface class SecureCredentialStore {
  Future<String?> readBaiduAppId();
  Future<String?> readBaiduSecret();
  Future<bool> hasBaiduCredentials();
  Future<void> writeBaiduCredentials({
    required String appId,
    required String secret,
  });
  Future<void> deleteBaiduCredentials();
}

// 基于 flutter_secure_storage 的实现，密钥不进入普通数据库设置。
class KeychainCredentialStore implements SecureCredentialStore {
  KeychainCredentialStore(this._storage);

  static const _appIdKey = 'baidu_app_id';
  static const _secretKey = 'baidu_secret';

  final FlutterSecureStorage _storage;

  @override
  Future<String?> readBaiduAppId() => _storage.read(key: _appIdKey);

  @override
  Future<String?> readBaiduSecret() => _storage.read(key: _secretKey);

  @override
  Future<bool> hasBaiduCredentials() async {
    final appId = await readBaiduAppId();
    final secret = await readBaiduSecret();
    return appId != null &&
        appId.isNotEmpty &&
        secret != null &&
        secret.isNotEmpty;
  }

  @override
  Future<void> writeBaiduCredentials({
    required String appId,
    required String secret,
  }) async {
    await _storage.write(key: _appIdKey, value: appId);
    await _storage.write(key: _secretKey, value: secret);
  }

  @override
  Future<void> deleteBaiduCredentials() async {
    await _storage.delete(key: _appIdKey);
    await _storage.delete(key: _secretKey);
  }
}

// 安全存储实例；测试通过 override 换成替身，避免依赖原生通道。
final secureCredentialStoreProvider = Provider<SecureCredentialStore>((ref) {
  const storage = FlutterSecureStorage(
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
    // macOS 使用本机登录钥匙串；当前独立应用无需共享组，避免临时签名触发 -34018。
    mOptions: MacOsOptions(
      accessibility: KeychainAccessibility.first_unlock,
      usesDataProtectionKeychain: false,
    ),
  );
  return KeychainCredentialStore(storage);
});
