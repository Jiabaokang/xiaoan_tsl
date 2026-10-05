import 'package:google_mlkit_translation/google_mlkit_translation.dart';

import 'translate_language_code.dart';
import 'translation_service.dart';

// 调用设备端 ML Kit 翻译，并在每次调用后释放原生 translator。
class MlKitTranslationService implements TranslationService {
  @override
  String get engineId => 'mlkit';

  // ML Kit 服务必须先完成模型检查与下载，不能直接调用翻译。
  @override
  bool get requiresMlKitModels => true;

  @override
  Future<String> translate({
    required String text,
    required String sourceLanguage,
    required String targetLanguage,
  }) async {
    final source = translateLanguageForCode(sourceLanguage);
    final target = translateLanguageForCode(targetLanguage);
    if (source == null) {
      throw ArgumentError.value(sourceLanguage, 'sourceLanguage', '不支持的语言');
    }
    if (target == null) {
      throw ArgumentError.value(targetLanguage, 'targetLanguage', '不支持的语言');
    }

    final translator = OnDeviceTranslator(
      sourceLanguage: source,
      targetLanguage: target,
    );
    try {
      return await translator.translateText(text);
    } finally {
      await translator.close();
    }
  }
}
