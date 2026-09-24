import 'package:google_mlkit_translation/google_mlkit_translation.dart';

import 'translate_language_code.dart';

// 模型状态始终从设备端查询，不能用历史数据库缓存替代。
abstract interface class TranslationModelService {
  Future<bool> isDownloaded(String code);
  Future<void> download(String code, {bool wifiOnly = true});
  Future<void> delete(String code);
}

// 对接 ML Kit 的翻译模型查询、下载和删除。
class MlKitModelService implements TranslationModelService {
  final _manager = OnDeviceTranslatorModelManager();

  String _modelCode(String code) {
    final language = translateLanguageForCode(code);
    if (language == null) {
      throw ArgumentError.value(code, 'code', '不支持的语言');
    }
    return language.bcpCode;
  }

  @override
  Future<bool> isDownloaded(String code) async =>
      _manager.isModelDownloaded(_modelCode(code));

  @override
  Future<void> download(String code, {bool wifiOnly = true}) async {
    final success = await _manager.downloadModel(
      _modelCode(code),
      isWifiRequired: wifiOnly,
    );
    if (!success) throw StateError('语言模型下载失败');
  }

  @override
  Future<void> delete(String code) async {
    final success = await _manager.deleteModel(_modelCode(code));
    if (!success) throw StateError('语言模型删除失败');
  }
}
