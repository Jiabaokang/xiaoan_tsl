import 'package:google_mlkit_translation/google_mlkit_translation.dart';

// 仅接受 ML Kit 实际支持的 BCP-47 语言代码。
TranslateLanguage? translateLanguageForCode(String code) {
  for (final language in TranslateLanguage.values) {
    if (language.bcpCode == code) return language;
  }
  return null;
}
