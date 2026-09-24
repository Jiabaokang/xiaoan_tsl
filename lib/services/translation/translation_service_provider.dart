import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'mlkit_translation_service.dart';
import 'translation_service.dart';

// 正式流程默认使用设备端翻译，测试可注入演示或替身实现。
final translationServiceProvider = Provider<TranslationService>(
  (ref) => MlKitTranslationService(),
);
