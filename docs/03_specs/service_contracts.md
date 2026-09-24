# 核心服务契约与接口规格 (Service Contracts Spec)

> **适用范围**：`lib/services/` 及其对应的 Riverpod Providers  
> **设计目标**：解耦平台底层实现（ML Kit / TTS / Share），支持测试依赖注入（DI）与平滑替换。

---

## 1. 核心接口定义

### 1.1 翻译服务契约 (`TranslationService`)
```dart
abstract class TranslationService {
  /// 执行离线文本翻译
  ///
  /// [text] 待翻译源文本 (已校验非空且在长度范围内)
  /// [sourceLanguage] 标准源语言代码 (如 'zh', 'en')
  /// [targetLanguage] 标准目标语言代码 (如 'en', 'zh')
  ///
  /// 返回翻译后的译文字符串；若底层模型不可用或翻译失败抛出异常
  Future<String> translate({
    required String text,
    required String sourceLanguage,
    required String targetLanguage,
  });
}
```

### 1.2 语言识别契约 (`LanguageDetectionService`)
```dart
abstract class LanguageDetectionService {
  /// 识别输入文本的语言
  ///
  /// [text] 待识别原文
  /// 返回识别到的标准语言代码 (如 'zh', 'en')；若置信度过低或无法确定返回 null
  Future<String?> detectLanguage(String text);
  
  /// 释放识别器资源
  Future<void> dispose();
}
```

### 1.3 模型管理契约 (`ModelManagementService` / `MlKitModelService`)
```dart
abstract class ModelManagementService {
  /// 检查某语言的离线模型是否已在本地下载完成
  Future<bool> isModelDownloaded(String languageCode);

  /// 触发模型下载
  /// [languageCode] 目标语言代码
  /// [isWifiRequired] 是否仅限 Wi-Fi 环境 (默认为 true)
  Future<void> downloadModel(String languageCode, {bool isWifiRequired = true});

  /// 删除本地已下载的离线模型以释放存储
  Future<void> deleteModel(String languageCode);
}
```

### 1.4 语音朗读契约 (`SpeechService`)
```dart
abstract class SpeechService {
  /// 检查系统当前是否安装了该语言的 TTS 朗读语音包
  Future<bool> isLanguageAvailable(String languageCode);

  /// 朗读指定文本
  /// [text] 朗读内容
  /// [languageCode] 对应的发音语种代码
  Future<void> speak(String text, {required String languageCode});

  /// 立即打断并停止当前朗读
  Future<void> stop();

  /// 销毁并释放语音通道
  Future<void> dispose();
}
```

### 1.5 系统交互契约 (`SharingService`)
```dart
abstract class SharingService {
  /// 写入系统剪贴板
  Future<void> copyToClipboard(String text);

  /// 调用 Android 原生分享面板
  Future<void> shareText(String text, {String? subject});
}
```

---

## 2. 语言代码映射规范

系统内部统一采用 ISO-639-1 标准小写语言代码作为通信格式：

| 应用标准代码 | 中文名称 | ML Kit TranslateLanguage | TTS Locale 映射 |
|---|---|---|---|
| `'zh'` | 中文（简体） | `TranslateLanguage.chinese` | `'zh-CN'` |
| `'en'` | 英语 | `TranslateLanguage.english` | `'en-US'` |
| `'ja'` | 日语 | `TranslateLanguage.japanese` | `'ja-JP'` |
| `'ko'` | 韩语 | `TranslateLanguage.korean` | `'ko-KR'` |
| `'fr'` | 法语 | `TranslateLanguage.french` | `'fr-FR'` |
| `'de'` | 德语 | `TranslateLanguage.german` | `'de-DE'` |
| `'es'` | 西班牙语 | `TranslateLanguage.spanish` | `'es-ES'` |

* **安全回退**：遇到未注册的语言代码时，`TranslateLanguageCode.fromCode(code)` 必须返回 `null`，严禁抛出未捕获的运行时异常。

---

## 3. 依赖注入与测试隔离规范

每个服务均通过 Riverpod Provider 进行全局暴露：
* `translationServiceProvider`
* `languageDetectionServiceProvider`
* `modelServiceProvider`
* `speechServiceProvider`
* `sharingServiceProvider`

**测试隔离原则**：
在 `test/` 单元测试与 Widget 测试中，严禁调用 ML Kit 或平台原生 MethodChannel。必须通过 `ProviderScope(overrides: [...])` 将上述 Provider 替换为测试用 Mock 实现（如 `test/support/test_translation_services.dart`），确保测试可以在无 Android 原生环境的 CI 或 macOS 开发机上 100% 稳定运行。
