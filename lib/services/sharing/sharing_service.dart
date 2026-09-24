import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

// 统一封装系统剪贴板与分享入口。
class SharingService {
  static Future<void> copyTranslation(String text) =>
      Clipboard.setData(ClipboardData(text: text));

  static Future<void> shareTranslation({
    required String sourceText,
    required String translatedText,
  }) async {
    await SharePlus.instance.share(
      ShareParams(
        text: '$sourceText\n\n'
            '$translatedText\n\n— 小安翻译',
      ),
    );
  }
}
