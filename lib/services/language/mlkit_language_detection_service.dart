import 'package:google_mlkit_language_id/google_mlkit_language_id.dart';

import '../translation/translate_language_code.dart';

// 自动识别可替换的设备能力边界。
abstract interface class LanguageDetectionService {
  Future<String?> identify(String text);
}

// 通过 ML Kit 识别语言；短文本和不确定结果交给用户手动选择。
class MlKitLanguageDetectionService implements LanguageDetectionService {
  @override
  Future<String?> identify(String text) async {
    if (text.trim().runes.length <= 5) return null;

    final identifier = LanguageIdentifier(confidenceThreshold: 0.5);
    try {
      final code = await identifier.identifyLanguage(text);
      return translateLanguageForCode(code) == null ? null : code;
    } finally {
      await identifier.close();
    }
  }
}
