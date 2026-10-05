import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../desktop/macos_desktop_service.dart';
import 'mlkit_language_detection_service.dart';

// macOS 使用原生 Natural Language 识别；移动端保留 ML Kit 阈值行为不变。
final languageDetectionProvider = Provider<LanguageDetectionService>((ref) {
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.macOS) {
    return MacosNativeLanguageDetectionService(
      ref.watch(macosDesktopServiceProvider),
    );
  }
  return MlKitLanguageDetectionService();
});

// 通过桌面通道的原生 Natural Language 识别语言；不确定返回 null。
class MacosNativeLanguageDetectionService implements LanguageDetectionService {
  MacosNativeLanguageDetectionService(this._desktop);

  final MacosDesktopService _desktop;

  @override
  Future<String?> identify(String text) async {
    if (text.trim().isEmpty) return null;
    return _desktop.identifyLanguage(text);
  }
}
