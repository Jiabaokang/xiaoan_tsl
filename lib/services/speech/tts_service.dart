import 'package:flutter_tts/flutter_tts.dart';

// 将翻译语言代码映射为设备朗读使用的 locale。
String? ttsLocaleForCode(String code) => switch (code) {
  'zh' => 'zh-CN',
  'en' => 'en-US',
  'ja' => 'ja-JP',
  'ko' => 'ko-KR',
  'fr' => 'fr-FR',
  'de' => 'de-DE',
  'es' => 'es-ES',
  'pt' => 'pt-BR',
  'it' => 'it-IT',
  'ru' => 'ru-RU',
  _ => null,
};

// 页面只通过此边界控制系统朗读和停止。
abstract interface class SpeechService {
  Future<void> speak({required String text, required String languageCode});
  Future<void> stop();
}

// 检查设备语音后使用 flutter_tts 朗读；Future 在朗读结束时完成。
class FlutterTtsSpeechService implements SpeechService {
  final FlutterTts _tts = FlutterTts();

  @override
  Future<void> speak({
    required String text,
    required String languageCode,
  }) async {
    if (text.trim().isEmpty) {
      throw ArgumentError.value(text, 'text', '朗读内容不能为空');
    }
    final locale = ttsLocaleForCode(languageCode);
    if (locale == null || await _tts.isLanguageAvailable(locale) != true) {
      throw UnsupportedError('当前设备暂不支持该语言朗读');
    }
    await _tts.awaitSpeakCompletion(true);
    await _tts.setLanguage(locale);
    final result = await _tts.speak(text);
    if (result != 1) throw StateError('朗读失败');
  }

  @override
  Future<void> stop() async {
    await _tts.stop();
  }
}
