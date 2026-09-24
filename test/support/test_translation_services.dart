import 'package:xiaoan_tsl/services/language/mlkit_language_detection_service.dart';
import 'package:xiaoan_tsl/services/translation/mlkit_model_service.dart';

// 组件测试中提供确定的语言结果，避免依赖原生插件通道。
class TestLanguageDetectionService implements LanguageDetectionService {
  @override
  Future<String?> identify(String text) async {
    if (text.trim().runes.length <= 5) return null;
    return RegExp(r'[\u4e00-\u9fff]').hasMatch(text) ? 'zh' : 'en';
  }
}

// 已下载模型替身让旧页面测试聚焦页面与状态，不触发网络下载。
class DownloadedTranslationModels implements TranslationModelService {
  @override
  Future<bool> isDownloaded(String code) async => true;

  @override
  Future<void> download(String code, {bool wifiOnly = true}) async {}

  @override
  Future<void> delete(String code) async {}
}
