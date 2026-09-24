import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaoan_tsl/services/language/mlkit_language_detection_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('google_mlkit_language_identifier');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];
  var response = 'en';

  setUp(() {
    calls.clear();
    response = 'en';
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return call.method == 'nlp#startLanguageIdentifier' ? response : null;
    });
  });

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('短文本要求手选且不调用插件', () async {
    final service = MlKitLanguageDetectionService();
    expect(await service.identify('Apple'), isNull);
    expect(calls, isEmpty);
  });

  test('识别支持的代码并释放 identifier', () async {
    final service = MlKitLanguageDetectionService();
    expect(await service.identify('Hello, world!'), 'en');
    expect(calls.map((call) => call.method), [
      'nlp#startLanguageIdentifier',
      'nlp#closeLanguageIdentifier',
    ]);
    expect((calls.first.arguments as Map)['confidence'], 0.5);
  });

  test('无法确定或不支持的语言要求手选', () async {
    final service = MlKitLanguageDetectionService();
    response = 'und';
    expect(await service.identify('Something unexpected'), isNull);
    response = 'xx';
    expect(await service.identify('Something unexpected'), isNull);
    expect(
      calls.where((call) => call.method == 'nlp#closeLanguageIdentifier'),
      hasLength(2),
    );
  });
}
