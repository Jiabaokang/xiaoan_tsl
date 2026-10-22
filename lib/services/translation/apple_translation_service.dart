import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'translation_service.dart';
import 'translation_service_provider.dart';

// 系统语言对能力；支持但未安装仍允许用户选择苹果服务。
enum AppleTranslationAvailability {
  platformUnsupported,
  unsupported,
  supported,
  installed,
}

// 苹果服务只传递稳定错误码，展示文案统一由国际化层处理。
class AppleTranslationException implements Exception {
  const AppleTranslationException(this.code);

  final String code;

  bool get isCancelled => code == 'appleCancelled';

  @override
  String toString() => 'AppleTranslationException($code)';
}

final _requestRandom = Random.secure();

// 首页、截图及独立调用共用 UUID v4，避免控制器重建后复用请求标识。
String generateAppleTranslationRequestId() {
  final bytes = List<int>.generate(16, (_) => _requestRandom.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

// 通过既有桌面通道管理苹果准备、翻译和请求清理，不回退在线服务。
class AppleTranslationService implements TranslationService {
  AppleTranslationService({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('xiaoan_tsl/macos_desktop');

  final MethodChannel _channel;

  // 仅记录在途准备；取消先标记，避免能力查询晚到后重新创建原生宿主。
  final _pendingPreparations = <String, bool>{};

  @override
  String get engineId => 'apple';

  @override
  bool get requiresMlKitModels => false;

  Future<AppleTranslationAvailability> availability({
    required String sourceLanguage,
    required String targetLanguage,
  }) async {
    final response = await _invoke('appleTranslationAvailability', {
      'sourceLanguage': sourceLanguage,
      'targetLanguage': targetLanguage,
    });
    if (response is Map) {
      for (final status in AppleTranslationAvailability.values) {
        if (response['status'] == status.name) return status;
      }
    }
    throw const AppleTranslationException('appleTranslationFailed');
  }

  // 每次查询实际语言对；准备成功后原生保留同一会话，供显式 ID 翻译使用。
  Future<void> prepare({
    required String requestId,
    required String sourceLanguage,
    required String targetLanguage,
  }) async {
    _validateRequestId(requestId);
    if (_pendingPreparations.containsKey(requestId)) {
      throw const AppleTranslationException('appleInvalidRequest');
    }
    _pendingPreparations[requestId] = false;
    try {
      if (sourceLanguage.trim().isEmpty || targetLanguage.trim().isEmpty) {
        throw const AppleTranslationException('appleInvalidArguments');
      }
      if (sourceLanguage == 'auto' || targetLanguage == 'auto') {
        throw const AppleTranslationException('appleUnsupportedLanguage');
      }
      final status = await availability(
        sourceLanguage: sourceLanguage,
        targetLanguage: targetLanguage,
      );
      _checkPreparationCancelled(requestId);
      if (status == AppleTranslationAvailability.platformUnsupported) {
        throw const AppleTranslationException('appleUnsupported');
      }
      if (status == AppleTranslationAvailability.unsupported) {
        throw const AppleTranslationException('appleUnsupportedLanguage');
      }
      final response = await _invoke('prepareAppleTranslation', {
        'requestId': requestId,
        'sourceLanguage': sourceLanguage,
        'targetLanguage': targetLanguage,
      });
      _checkPreparationCancelled(requestId);
      if (response != null) {
        throw const AppleTranslationException('appleTranslationFailed');
      }
    } catch (_) {
      await _cleanup(requestId);
      rethrow;
    } finally {
      _pendingPreparations.remove(requestId);
    }
  }

  Future<void> cancel(String requestId) async {
    _validateRequestId(requestId);
    if (_pendingPreparations.containsKey(requestId)) {
      _pendingPreparations[requestId] = true;
    }
    final response = await _invoke('cancelAppleTranslation', {
      'requestId': requestId,
    });
    if (response != null) {
      throw const AppleTranslationException('appleTranslationFailed');
    }
  }

  @override
  Future<String> translate({
    required String text,
    required String sourceLanguage,
    required String targetLanguage,
    String? requestId,
  }) async {
    final id = requestId ?? generateAppleTranslationRequestId();
    _validateRequestId(id);
    try {
      // 与原生统一按 UTF-16 单元限制长度，emoji 不会绕过 5000 字符上限。
      if (text.trim().isEmpty || text.length > 5000) {
        throw const AppleTranslationException('appleInvalidArguments');
      }
      if (requestId == null) {
        await prepare(
          requestId: id,
          sourceLanguage: sourceLanguage,
          targetLanguage: targetLanguage,
        );
      }
      final response = await _invoke('translateText', {
        'requestId': id,
        'text': text,
      });
      if (response is! Map) {
        throw const AppleTranslationException('appleTranslationFailed');
      }
      if (response['requestId'] != id) {
        throw const AppleTranslationException('appleInvalidRequest');
      }
      final translated = response['translatedText'];
      if (translated is! String || translated.trim().isEmpty) {
        throw const AppleTranslationException('appleTranslationFailed');
      }
      return translated;
    } finally {
      await _cleanup(id);
    }
  }

  void _validateRequestId(String requestId) {
    if (requestId.trim().isEmpty) {
      throw const AppleTranslationException('appleInvalidArguments');
    }
  }

  void _checkPreparationCancelled(String requestId) {
    if (_pendingPreparations[requestId] == true) {
      throw const AppleTranslationException('appleCancelled');
    }
  }

  Future<Object?> _invoke(String method, Map<String, String> arguments) async {
    try {
      return await _channel.invokeMethod<Object?>(method, arguments);
    } on PlatformException catch (error) {
      throw AppleTranslationException(error.code);
    } on MissingPluginException {
      throw const AppleTranslationException('appleTranslationFailed');
    }
  }

  // 清理仅针对本请求，不能用清理异常覆盖已取得的译文或原始失败。
  Future<void> _cleanup(String requestId) async {
    try {
      await cancel(requestId);
    } catch (_) {
      // 原生终结路径也会释放宿主；取消失败不改变本次翻译的结果。
    }
  }
}

// 两个控制器与设置页可覆盖同一个苹果服务实例。
final appleTranslationServiceProvider = Provider<AppleTranslationService>(
  (ref) => AppleTranslationService(),
);

// 设置页只查询英简中能力；其他平台不创建苹果服务，也不调用桌面通道。
final appleTranslationAvailabilityProvider =
    FutureProvider<AppleTranslationAvailability>((ref) {
      if (ref.watch(translationPlatformProvider) != TranslationPlatform.macOS) {
        return AppleTranslationAvailability.platformUnsupported;
      }
      return ref
          .watch(appleTranslationServiceProvider)
          .availability(sourceLanguage: 'en', targetLanguage: 'zh');
    }, retry: (retryCount, error) => null);
