import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'mlkit_language_detection_service.dart';

// 正式运行时使用 ML Kit，测试中可注入确定的识别结果。
final languageDetectionProvider = Provider<LanguageDetectionService>(
  (ref) => MlKitLanguageDetectionService(),
);
