import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaoan_tsl/services/translation/mlkit_translation_service.dart';
import 'package:xiaoan_tsl/services/translation/translation_service_provider.dart';

void main() {
  test('应用默认使用设备端 ML Kit 翻译服务', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(
      container.read(translationServiceProvider),
      isA<MlKitTranslationService>(),
    );
  });
}
