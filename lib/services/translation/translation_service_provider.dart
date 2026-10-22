import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:xiaoan_tsl/core/database/database_provider.dart';
import 'package:xiaoan_tsl/core/network/dio_provider.dart';

import 'baidu_translation_service.dart';
import 'apple_translation_service.dart';
import 'mlkit_translation_service.dart';
import 'translation_service.dart';
import 'translation_settings.dart';

// 运行平台标识，测试可整体覆盖；页面不再各自重复判断平台。
enum TranslationPlatform { android, ios, macOS, other }

// 平台选择集中在一处：移动端允许 ML Kit，macOS 支持百度及苹果服务。
final translationPlatformProvider = Provider<TranslationPlatform>((ref) {
  if (kIsWeb) return TranslationPlatform.other;
  return switch (defaultTargetPlatform) {
    TargetPlatform.android => TranslationPlatform.android,
    TargetPlatform.iOS => TranslationPlatform.ios,
    TargetPlatform.macOS => TranslationPlatform.macOS,
    _ => TranslationPlatform.other,
  };
});

// 各平台未保存选择时的默认服务：macOS 百度，其余 ML Kit。
String defaultEngineFor(TranslationPlatform platform) =>
    platform == TranslationPlatform.macOS ? 'baidu' : 'mlkit';

// 已保存服务偏好的异步加载；空值代表尚未加载或从未设置。
final translationEngineProvider =
    NotifierProvider<TranslationEngineNotifier, String>(
      TranslationEngineNotifier.new,
    );

// 读取并持久化 translation_engine 设置；普通设置走 SQLite。
class TranslationEngineNotifier extends Notifier<String> {
  Future<void>? _loadFuture;

  @override
  String build() {
    _loadFuture = _load();
    return '';
  }

  // 供测试等待首次设置加载完成，避免读取到未解析的默认服务。
  Future<void> get ready => _loadFuture ?? Future.value();

  Future<void> _load() async {
    try {
      final saved = await ref
          .read(localStoreProvider)
          .getSetting(TranslationSettingKeys.engine);
      if (!ref.mounted) return;
      state = saved ?? '';
    } catch (_) {
      // 读取失败保持空值，Provider 会使用平台默认服务。
    }
  }

  Future<void> setEngine(String engine) async {
    await ref
        .read(localStoreProvider)
        .setSetting(TranslationSettingKeys.engine, engine);
    if (ref.mounted) state = engine;
  }
}

// 根据平台与已保存偏好解析实际翻译服务；缺凭据时仍返回百度实例，
// 由服务在请求时抛出配置错误，禁止用 demo 伪装正式服务。
final translationServiceProvider = Provider<TranslationService>((ref) {
  final platform = ref.watch(translationPlatformProvider);
  final saved = ref.watch(translationEngineProvider);
  final engine = saved.isEmpty ? defaultEngineFor(platform) : saved;
  return _resolveService(ref, platform, engine);
});

TranslationService _resolveService(
  Ref ref,
  TranslationPlatform platform,
  String engine,
) {
  switch (engine) {
    case 'baidu':
      return BaiduTranslationService(
        credentials: ref.read(secureCredentialStoreProvider),
        dio: ref.read(dioProvider),
      );
    case 'mlkit':
      // macOS 不创建 ML Kit 插件对象；未知配置回退平台默认。
      if (platform == TranslationPlatform.macOS) {
        return _resolveService(ref, platform, defaultEngineFor(platform));
      }
      return MlKitTranslationService();
    case 'apple':
      // 已保存的 macOS 苹果偏好不因暂时不可用改走在线服务。
      if (platform == TranslationPlatform.macOS) {
        return ref.watch(appleTranslationServiceProvider);
      }
      return _resolveService(ref, platform, defaultEngineFor(platform));
    default:
      // 未知或空配置回退平台默认。
      return _resolveService(ref, platform, defaultEngineFor(platform));
  }
}
