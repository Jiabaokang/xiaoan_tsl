// 翻译服务边界；正式接入 ML Kit 时只需替换实现。
abstract interface class TranslationService {
  Future<String> translate({
    required String text,
    required String sourceLanguage,
    required String targetLanguage,
  });
}

// 仅提供原型中的固定示例，其余输入明确标记为模拟结果。
class DemoTranslationService implements TranslationService {
  static const _examples = <String, String>{
    'en:zh:hello, world!': '你好，世界！',
    'en:zh:good morning': '早上好',
    'en:zh:how are you?': '你好吗？',
    'zh:en:谢谢你的帮助': 'Thank you for your help.',
    'zh:en:你好，世界！': 'Hello, world!',
  };

  @override
  Future<String> translate({
    required String text,
    required String sourceLanguage,
    required String targetLanguage,
  }) async {
    final key = '$sourceLanguage:$targetLanguage:${text.trim().toLowerCase()}';
    return _examples[key] ?? '模拟译文（未接入翻译引擎）：${text.trim()}';
  }
}
