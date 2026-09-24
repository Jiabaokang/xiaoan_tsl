import 'package:flutter_test/flutter_test.dart';
import 'package:xiaoan_tsl/services/translation/translate_language_code.dart';

void main() {
  test('应用语言代码只映射 ML Kit 支持的语言', () {
    expect(translateLanguageForCode('en')?.name, 'english');
    expect(translateLanguageForCode('zh'), isNotNull);
    expect(translateLanguageForCode('auto'), isNull);
    expect(translateLanguageForCode('xx'), isNull);
  });
}
