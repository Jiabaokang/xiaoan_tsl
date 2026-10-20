import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';

import 'translate_language_code.dart';
import 'model_download_status.dart';

// 模型状态始终从设备端查询，不能用历史数据库缓存替代。
abstract interface class TranslationModelService {
  Future<bool> isDownloaded(String code);
  Future<void> download(String code, {bool wifiOnly = true});
  Future<void> delete(String code);
}

// 对接 ML Kit 的翻译模型查询、下载和删除。
class MlKitModelService
    implements TranslationModelService, ModelDownloadEventSource {
  final _manager = OnDeviceTranslatorModelManager();
  static const _downloads = MethodChannel('xiaoan_tsl/model_download');
  static const _events = EventChannel('xiaoan_tsl/model_download_events');

  @override
  late final Stream<ModelDownloadStatus> downloadEvents = _events
      .receiveBroadcastStream()
      .where((event) => event is Map && event['model'] is String)
      .map((event) {
        final data = event as Map;
        return ModelDownloadStatus(
          code: data['model'] as String,
          phase: ModelDownloadPhase.values.firstWhere(
            (phase) => phase.name == data['phase'],
            orElse: () => ModelDownloadPhase.preparing,
          ),
          progress: data['progress'] is num
              ? (data['progress'] as num).toDouble()
              : null,
          canUseMobile: data['canUseMobile'] == true,
        );
      });

  @override
  Future<void> allowMobileData(String code) async {
    try {
      await _downloads.invokeMethod<void>('allowMobileData', {
        'model': _modelCode(code),
      });
    } on PlatformException catch (error) {
      throw ModelDownloadException.fromPlatform(error);
    }
  }

  String _modelCode(String code) {
    final language = translateLanguageForCode(code);
    if (language == null) {
      throw ArgumentError.value(code, 'code', '不支持的语言');
    }
    return language.bcpCode;
  }

  // iOS 英语模型随 SDK 内置，不能交给远程模型工厂下载或删除。
  bool _isBundled(String code) =>
      defaultTargetPlatform == TargetPlatform.iOS && code == 'en';

  @override
  Future<bool> isDownloaded(String code) async =>
      _isBundled(code) || await _manager.isModelDownloaded(_modelCode(code));

  @override
  Future<void> download(String code, {bool wifiOnly = true}) async {
    final model = _modelCode(code);
    if (_isBundled(code)) return;
    try {
      final result = await _downloads.invokeMethod<Object?>('download', {
        'model': model,
        'wifiOnly': wifiOnly,
      });
      if (result != 'success' && result != true) {
        throw ModelDownloadException(
          ModelDownloadFailure.unknown,
          '语言模型下载失败: $result',
        );
      }
    } on PlatformException catch (error) {
      throw ModelDownloadException.fromPlatform(error);
    }
  }

  @override
  Future<void> delete(String code) async {
    if (_isBundled(code)) return;
    final success = await _manager.deleteModel(_modelCode(code));
    if (!success) throw StateError('语言模型删除失败');
  }
}
