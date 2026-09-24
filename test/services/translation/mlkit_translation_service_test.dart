import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaoan_tsl/services/translation/mlkit_translation_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('google_mlkit_on_device_translator');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];
  var failTranslation = false;

  setUp(() {
    calls.clear();
    failTranslation = false;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'nlp#startLanguageTranslator') {
        if (failTranslation) throw PlatformException(code: 'translate_failed');
        return '你好';
      }
      return null;
    });
  });

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('真实翻译服务调用插件并释放 translator', () async {
    final service = MlKitTranslationService();
    final translated = await service.translate(
      text: 'Hello',
      sourceLanguage: 'en',
      targetLanguage: 'zh',
    );

    expect(translated, '你好');
    expect(calls.map((call) => call.method), [
      'nlp#startLanguageTranslator',
      'nlp#closeLanguageTranslator',
    ]);
    expect((calls.first.arguments as Map)['source'], 'en');
    expect((calls.first.arguments as Map)['target'], 'zh');
  });

  test('翻译异常仍释放 translator，不支持的语言不调用插件', () async {
    final service = MlKitTranslationService();
    failTranslation = true;
    await expectLater(
      service.translate(
        text: 'Hello',
        sourceLanguage: 'en',
        targetLanguage: 'zh',
      ),
      throwsA(isA<PlatformException>()),
    );
    expect(calls.last.method, 'nlp#closeLanguageTranslator');
    calls.clear();
    await expectLater(
      service.translate(
        text: 'Hello',
        sourceLanguage: 'xx',
        targetLanguage: 'zh',
      ),
      throwsArgumentError,
    );
    expect(calls, isEmpty);
  });
}
