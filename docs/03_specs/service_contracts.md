# 核心服务契约与接口规格 (Service Contracts Spec)

> **适用范围**：`lib/services/` 及其对应的 Riverpod Providers  
> **设计目标**：解耦平台底层实现（ML Kit / TTS / Share），支持测试依赖注入（DI）与平滑替换。

---

## 1. 核心接口定义

### 1.1 翻译服务契约 (`TranslationService`)
```dart
abstract class TranslationService {
  String get engineId;
  bool get requiresMlKitModels;

  /// 使用选定引擎翻译；失败不能自动转到其他服务
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

macOS 默认仍为 `baidu`；显式保存 `apple` 时解析为 `AppleTranslationService`，即使能力查询失败也不自动改选或上传百度。非 macOS 的遗留 apple 配置按原平台默认处理。

苹果服务复用 `xiaoan_tsl/macos_desktop`：`appleTranslationAvailability` 查询实际语言对，`prepareAppleTranslation` 以唯一 `requestId` 准备系统语言包，`translateText` 消费同一请求，`cancelAppleTranslation` 只取消匹配 ID。能力区分 `platformUnsupported`、`unsupported`、`supported`、`installed`，不持久化语言包状态。`supported` 允许选择，选择服务本身不触发下载。

`AppleTranslationService.translate` 在既有必填参数之外接受可选 `requestId`；不传时自行准备，传入时消费已准备会话。两个业务控制器显式准备，以呈现准备阶段；通用 `TranslationService` 接口不增加苹果参数。`AppleTranslationException.code` 由中英文本地化出口映射，取消回 idle、保留输入且不保存成功历史。完整参数、错误码和超时契约见[苹果接入开发文档](../superpowers/plans/20261020151615_macOS苹果离线翻译接入开发文档.md#4-dart--原生接口契约)。

最低系统保持 macOS 14，苹果 API 经运行时检查仅在 15+ 创建。系统 SwiftUI 宿主中的同一 `translationTask` 先准备、再等待并执行翻译；准备上限 10 分钟，准备后的闲置和实际翻译各限 30 秒。`zh` 只映射系统报告支持的简体中文；文本长度统一按 5000 个 UTF-16 单元校验。

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
