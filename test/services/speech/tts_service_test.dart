import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaoan_tsl/services/speech/tts_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('flutter_tts');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];
  var available = true;

  setUp(() {
    calls.clear();
    available = true;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'isLanguageAvailable') return available;
      return 1;
    });
  });

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('朗读语言代码映射为系统 TTS locale', () {
    expect(ttsLocaleForCode('zh'), 'zh-CN');
    expect(ttsLocaleForCode('en'), 'en-US');
    expect(ttsLocaleForCode('ja'), 'ja-JP');
    expect(ttsLocaleForCode('xx'), isNull);
  });

  test('可用语言朗读时设置 locale，停止时调用设备服务', () async {
    final service = FlutterTtsSpeechService();
    await service.speak(text: '你好', languageCode: 'zh');
    await service.stop();
    expect(calls.map((call) => call.method), [
      'isLanguageAvailable',
      'awaitSpeakCompletion',
      'setLanguage',
      'speak',
      'stop',
    ]);
    expect(calls.first.arguments, 'zh-CN');
    expect(calls[2].arguments, 'zh-CN');
  });

  test('设备不支持当前语言时不发起朗读', () async {
    final service = FlutterTtsSpeechService();
    available = false;
    await expectLater(
      service.speak(text: '你好', languageCode: 'zh'),
      throwsUnsupportedError,
    );
    expect(calls.map((call) => call.method), ['isLanguageAvailable']);
  });
}
