import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'mlkit_model_service.dart';

// 翻译流程与离线模型页共用设备端模型状态。
final translationModelProvider = Provider<TranslationModelService>(
  (ref) => MlKitModelService(),
);
