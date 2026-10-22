import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:xiaoan_tsl/core/database/database_provider.dart';
import 'package:xiaoan_tsl/features/history/history_store.dart';
import 'package:xiaoan_tsl/features/language/app_languages.dart';
import 'package:xiaoan_tsl/l10n/app_localizations.dart';
import 'package:xiaoan_tsl/services/language/language_detection_provider.dart';
import 'package:xiaoan_tsl/services/translation/baidu_translation_service.dart';
import 'package:xiaoan_tsl/services/translation/apple_translation_service.dart';
import 'package:xiaoan_tsl/services/translation/model_service_provider.dart';
import 'package:xiaoan_tsl/services/translation/model_download_controller.dart';
import 'package:xiaoan_tsl/services/translation/model_download_status.dart';
import 'package:xiaoan_tsl/services/translation/translation_service_provider.dart';

// 翻译请求在页面上呈现的阶段。
enum TranslationPhase {
  idle,
  detecting,
  checkingModel,
  modelDownloadRequired,
  downloadingModel,
  preparingTranslation,
  translating,
  success,
  error;

  bool get isBusy => switch (this) {
    detecting ||
    checkingModel ||
    downloadingModel ||
    preparingTranslation ||
    translating => true,
    _ => false,
  };
}

// 失败类型用于显示针对性的恢复操作。
enum TranslationFailure {
  none,
  detection,
  unsupportedLanguage,
  modelCheck,
  modelDownload,
  translation,
  storage,
  config,
  apple,
}

// 首页、历史、收藏及设置共用的一份应用状态。
class AppState {
  const AppState({
    this.input = '',
    this.sourceLanguage = 'en',
    this.targetLanguage = 'zh',
    this.defaultTargetLanguage = 'zh',
    this.detectedLanguage,
    this.result,
    this.phase = TranslationPhase.idle,
    this.failure = TranslationFailure.none,
    this.message = '等待翻译',
    this.records = const [],
    this.themeMode = ThemeMode.system,
    this.localeMode = 'system',
    this.loaded = false,
    this.modelDownloadCodes = const [],
    this.modelDownloadIndex = 0,
    this.modelDownloadError,
    this.appleErrorCode,
  });

  final String input;
  final String sourceLanguage;
  final String targetLanguage;
  final String defaultTargetLanguage;
  final String? detectedLanguage;
  final TranslationRecord? result;
  final TranslationPhase phase;
  final TranslationFailure failure;
  final String message;
  final List<TranslationRecord> records;
  final ThemeMode themeMode;
  final String localeMode;
  final bool loaded;
  // 本次需要下载的模型及当前位置，供首页显示语言和多包步骤。
  final List<String> modelDownloadCodes;
  final int modelDownloadIndex;
  final ModelDownloadException? modelDownloadError;
  // 苹果错误保留稳定代码，由本地化出口选择可恢复提示。
  final String? appleErrorCode;

  String? get downloadingModelCode =>
      modelDownloadIndex < modelDownloadCodes.length
      ? modelDownloadCodes[modelDownloadIndex]
      : null;

  // 根据当前 localeMode 获取 Flutter 实体 Locale（null 代表跟随系统）。
  Locale? get locale => switch (localeMode) {
    'zh' => const Locale('zh'),
    'en' => const Locale('en'),
    _ => null,
  };

  // 根据当前国际化上下文返回对应的阶段或错误文案。
  String localizedMessage(AppLocalizations l10n) => switch (phase) {
    TranslationPhase.idle => l10n.phaseReady,
    TranslationPhase.detecting => l10n.phaseDetecting,
    TranslationPhase.checkingModel => l10n.phaseCheckingModel,
    TranslationPhase.modelDownloadRequired => l10n.modelDownloadRequired,
    TranslationPhase.downloadingModel => l10n.phaseDownloadingModel,
    TranslationPhase.preparingTranslation =>
      l10n.phasePreparingAppleTranslation,
    TranslationPhase.translating => l10n.phaseTranslating,
    TranslationPhase.success => l10n.phaseSuccess,
    TranslationPhase.error => switch (failure) {
      TranslationFailure.detection => l10n.errorDetection,
      TranslationFailure.unsupportedLanguage =>
        message == '最多输入 5000 个字符'
            ? l10n.errorMaxChars
            : (message == '请先翻译或手动选择原文语言'
                  ? l10n.errorSwapLanguage
                  : l10n.errorUnsupportedLang),
      TranslationFailure.modelCheck => l10n.errorModelCheck,
      TranslationFailure.modelDownload => l10n.modelDownloadFailure(
        modelDownloadError?.failure.name ?? 'unknown',
      ),
      TranslationFailure.translation => l10n.errorTranslation,
      TranslationFailure.config => l10n.errorConfigMissing,
      TranslationFailure.apple => l10n.appleTranslationError(
        appleErrorCode ?? 'appleTranslationFailed',
      ),
      TranslationFailure.storage =>
        message == '无法将结果写入历史' ? l10n.errorStorageSave : l10n.errorStorage,
      TranslationFailure.none => message,
    },
  };

  static const _unchanged = Object();

  AppState copyWith({
    String? input,
    String? sourceLanguage,
    String? targetLanguage,
    String? defaultTargetLanguage,
    Object? detectedLanguage = _unchanged,
    Object? result = _unchanged,
    TranslationPhase? phase,
    TranslationFailure? failure,
    String? message,
    List<TranslationRecord>? records,
    ThemeMode? themeMode,
    String? localeMode,
    bool? loaded,
    List<String>? modelDownloadCodes,
    int? modelDownloadIndex,
    Object? modelDownloadError = _unchanged,
    Object? appleErrorCode = _unchanged,
  }) => AppState(
    input: input ?? this.input,
    sourceLanguage: sourceLanguage ?? this.sourceLanguage,
    targetLanguage: targetLanguage ?? this.targetLanguage,
    defaultTargetLanguage: defaultTargetLanguage ?? this.defaultTargetLanguage,
    detectedLanguage: identical(detectedLanguage, _unchanged)
        ? this.detectedLanguage
        : detectedLanguage as String?,
    result: identical(result, _unchanged)
        ? this.result
        : result as TranslationRecord?,
    phase: phase ?? this.phase,
    failure: failure ?? this.failure,
    message: message ?? this.message,
    records: records ?? this.records,
    themeMode: themeMode ?? this.themeMode,
    localeMode: localeMode ?? this.localeMode,
    loaded: loaded ?? this.loaded,
    modelDownloadCodes: modelDownloadCodes ?? this.modelDownloadCodes,
    modelDownloadIndex: modelDownloadIndex ?? this.modelDownloadIndex,
    modelDownloadError: identical(modelDownloadError, _unchanged)
        ? this.modelDownloadError
        : modelDownloadError as ModelDownloadException?,
    appleErrorCode: identical(appleErrorCode, _unchanged)
        ? this.appleErrorCode
        : appleErrorCode as String?,
  );
}

final appControllerProvider = NotifierProvider<AppController, AppState>(
  AppController.new,
);

// 统一处理识别、模型准备、设备端翻译和本地数据变更。
class AppController extends Notifier<AppState> {
  int _request = 0;
  Future<void>? _initialization;
  AppleTranslationService? _appleService;
  String? _appleRequestId;

  @override
  AppState build() {
    ref.onDispose(_invalidateRequest);
    ref.listen(translationEngineProvider, (previous, next) {
      if (previous != next) cancelTranslation();
    });
    Future.microtask(initialize);
    return const AppState();
  }

  // 先使业务请求失效，再取消其原生宿主；不能误取消其他调用者的任务。
  void _invalidateRequest() {
    _request++;
    final service = _appleService;
    final requestId = _appleRequestId;
    _appleService = null;
    _appleRequestId = null;
    if (service != null && requestId != null) {
      unawaited(_cancelApple(service, requestId));
    }
  }

  Future<void> _cancelApple(AppleTranslationService service, String id) async {
    try {
      await service.cancel(id);
    } catch (_) {
      // 清理失败不能覆盖当前请求的结果或错误。
    }
  }

  // 用户取消或服务切换回到空闲，保留原文以便重试。
  void cancelTranslation() {
    _invalidateRequest();
    if (!ref.mounted) return;
    state = state.copyWith(
      result: null,
      phase: TranslationPhase.idle,
      failure: TranslationFailure.none,
      appleErrorCode: null,
      message: '等待翻译',
    );
  }

  Future<void> initialize() => _initialization ??= _load();

  Future<void> _load() async {
    try {
      final store = ref.read(localStoreProvider);
      final target = await store.getSetting('default_target') ?? 'zh';
      final themeName = await store.getSetting('theme_mode') ?? 'system';
      final localeMode = await store.getSetting('locale_mode') ?? 'system';
      final records = await store.search('');
      if (!ref.mounted) return;
      final theme = ThemeMode.values.where((mode) => mode.name == themeName);
      state = state.copyWith(
        sourceLanguage: state.sourceLanguage == target
            ? (target == 'en' ? 'zh' : 'en')
            : state.sourceLanguage,
        targetLanguage: target,
        defaultTargetLanguage: target,
        themeMode: theme.isEmpty ? ThemeMode.system : theme.first,
        localeMode: localeMode,
        records: records,
        loaded: true,
      );
    } catch (_) {
      if (ref.mounted) {
        state = state.copyWith(
          phase: TranslationPhase.error,
          failure: TranslationFailure.storage,
          message: '读取本地数据失败，请重启应用',
        );
      }
    }
  }

  void setInput(String value) {
    _invalidateRequest();
    state = state.copyWith(
      input: value,
      result: null,
      detectedLanguage: null,
      phase: TranslationPhase.idle,
      failure: TranslationFailure.none,
      message: '等待翻译',
    );
  }

  void setSourceLanguage(String code) {
    _invalidateRequest();
    state = state.copyWith(
      sourceLanguage: code,
      result: null,
      detectedLanguage: null,
      phase: TranslationPhase.idle,
      failure: TranslationFailure.none,
      message: '等待翻译',
    );
  }

  void setTargetLanguage(String code) {
    if (code == 'auto') return;
    _invalidateRequest();
    state = state.copyWith(
      targetLanguage: code,
      result: null,
      detectedLanguage: null,
      phase: TranslationPhase.idle,
      failure: TranslationFailure.none,
      message: '等待翻译',
    );
  }

  Future<void> setDefaultTargetLanguage(String code) async {
    if (code == 'auto') return;
    await ref.read(localStoreProvider).setSetting('default_target', code);
    if (!ref.mounted) return;
    final useAsCurrent = state.targetLanguage == state.defaultTargetLanguage;
    final targetChanged = useAsCurrent && state.targetLanguage != code;
    if (targetChanged) _invalidateRequest();
    state = state.copyWith(
      defaultTargetLanguage: code,
      targetLanguage: useAsCurrent ? code : state.targetLanguage,
      sourceLanguage: targetChanged && state.sourceLanguage == code
          ? state.targetLanguage
          : state.sourceLanguage,
      detectedLanguage: targetChanged ? null : state.detectedLanguage,
      result: targetChanged ? null : state.result,
      phase: targetChanged ? TranslationPhase.idle : state.phase,
      failure: targetChanged ? TranslationFailure.none : state.failure,
      message: targetChanged ? '等待翻译' : state.message,
    );
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    await ref.read(localStoreProvider).setSetting('theme_mode', mode.name);
    if (ref.mounted) state = state.copyWith(themeMode: mode);
  }

  // 切换并持久化界面语言偏好（'system', 'zh', 'en'）。
  Future<void> setLocaleMode(String mode) async {
    await ref.read(localStoreProvider).setSetting('locale_mode', mode);
    if (ref.mounted) state = state.copyWith(localeMode: mode);
  }

  // 切换翻译服务并让旧请求立即失效；输入保留，旧结果不更新 UI 也不入历史。
  Future<void> setTranslationEngine(String engine) async {
    cancelTranslation();
    await ref.read(translationEngineProvider.notifier).setEngine(engine);
  }

  bool swapLanguages() {
    final resolved = state.sourceLanguage == 'auto'
        ? state.detectedLanguage
        : state.sourceLanguage;
    if (resolved == null) {
      state = state.copyWith(
        phase: TranslationPhase.error,
        failure: TranslationFailure.unsupportedLanguage,
        message: '请先翻译或手动选择原文语言',
      );
      return false;
    }
    _invalidateRequest();
    state = state.copyWith(
      sourceLanguage: state.targetLanguage,
      targetLanguage: resolved,
      input: state.result?.translatedText ?? state.input,
      detectedLanguage: null,
      result: null,
      phase: TranslationPhase.idle,
      failure: TranslationFailure.none,
      message: '等待翻译',
    );
    return true;
  }

  Future<void> translate({
    bool downloadMissing = false,
    bool wifiOnly = false,
  }) async {
    final text = state.input.trim();
    if (text.isEmpty || state.phase.isBusy) return;
    if (text.length > 5000) {
      state = state.copyWith(
        phase: TranslationPhase.error,
        failure: TranslationFailure.unsupportedLanguage,
        message: '最多输入 5000 个字符',
      );
      return;
    }
    final selectedSource = state.sourceLanguage;
    final selectedTarget = state.targetLanguage;
    final request = ++_request;
    // 请求开始固定本次使用的服务实例，避免识别或模型准备期间服务切换。
    final service = ref.read(translationServiceProvider);
    state = state.copyWith(
      phase: TranslationPhase.detecting,
      failure: TranslationFailure.none,
      message: '正在识别输入语言',
      result: null,
      modelDownloadCodes: const [],
      modelDownloadIndex: 0,
      modelDownloadError: null,
      appleErrorCode: null,
    );
    try {
      final detected = await ref.read(languageDetectionProvider).identify(text);
      // 识别不确定时优先使用用户已明确选择的原文语言。
      final source =
          detected ?? (selectedSource == 'auto' ? null : selectedSource);
      if (!ref.mounted || request != _request) return;
      if (source == null || !appLanguages.containsKey(source)) {
        state = state.copyWith(
          phase: TranslationPhase.error,
          failure: TranslationFailure.detection,
          message: '无法识别输入语言，请输入更完整的内容',
        );
        return;
      }
      if (selectedSource == selectedTarget) {
        state = state.copyWith(
          phase: TranslationPhase.error,
          failure: TranslationFailure.unsupportedLanguage,
          message: '请选择两种不同的语言',
        );
        return;
      }
      final String target;
      if (source == selectedSource) {
        target = selectedTarget;
      } else if (source == selectedTarget && selectedSource != 'auto') {
        target = selectedSource;
      } else if (selectedSource == 'auto' && source != selectedTarget) {
        target = selectedTarget;
      } else {
        state = state.copyWith(
          phase: TranslationPhase.error,
          failure: TranslationFailure.unsupportedLanguage,
          message: '输入语言不在所选语言组合中，请调整语言',
        );
        return;
      }
      state = state.copyWith(detectedLanguage: source);
      // 模型检查与下载只属于 ML Kit；苹果语言包由系统准备。
      if (service.requiresMlKitModels) {
        final models = ref.read(translationModelProvider);
        final missing = <String>[];
        for (final code in {source, target}) {
          state = state.copyWith(
            phase: TranslationPhase.checkingModel,
            message: '正在检查离线模型',
          );
          final downloaded = await models.isDownloaded(code);
          if (!ref.mounted || request != _request) return;
          if (!downloaded) missing.add(code);
        }
        state = state.copyWith(modelDownloadCodes: missing);
        if (missing.isNotEmpty && !downloadMissing) {
          state = state.copyWith(
            phase: TranslationPhase.modelDownloadRequired,
            message: '需要下载语言模型',
          );
          return;
        }
        for (var index = 0; index < missing.length; index++) {
          state = state.copyWith(
            phase: TranslationPhase.downloadingModel,
            modelDownloadIndex: index,
            message: '正在准备离线翻译模型',
          );
          await ref
              .read(modelDownloadsProvider.notifier)
              .download(missing[index], wifiOnly: wifiOnly);
          if (!ref.mounted || request != _request) return;
        }
      }
      String? appleRequestId;
      if (service is AppleTranslationService) {
        appleRequestId = generateAppleTranslationRequestId();
        _appleService = service;
        _appleRequestId = appleRequestId;
        state = state.copyWith(phase: TranslationPhase.preparingTranslation);
        // 状态监听器可能同步取消；先确认请求仍有效再创建原生宿主。
        if (!ref.mounted || request != _request) return;
        await service.prepare(
          requestId: appleRequestId,
          sourceLanguage: source,
          targetLanguage: target,
        );
        if (!ref.mounted || request != _request) {
          await _cancelApple(service, appleRequestId);
          return;
        }
      }
      state = state.copyWith(
        phase: TranslationPhase.translating,
        message: '正在翻译',
      );
      final translated = service is AppleTranslationService
          ? await service.translate(
              text: text,
              sourceLanguage: source,
              targetLanguage: target,
              requestId: appleRequestId,
            )
          : await service.translate(
              text: text,
              sourceLanguage: source,
              targetLanguage: target,
            );
      if (!ref.mounted || request != _request) return;
      final record = TranslationRecord(
        sourceText: text,
        translatedText: translated,
        sourceLanguage: source,
        targetLanguage: target,
        createdAt: DateTime.now(),
        engine: service.engineId,
      );
      try {
        final saved = await ref.read(localStoreProvider).saveRecord(record);
        if (!ref.mounted || request != _request) return;
        final records = await ref.read(localStoreProvider).search('');
        if (!ref.mounted || request != _request) return;
        state = state.copyWith(
          result: saved,
          records: records,
          detectedLanguage: source,
          phase: TranslationPhase.success,
          failure: TranslationFailure.none,
          message: '翻译完成',
        );
      } catch (_) {
        if (ref.mounted && request == _request) {
          state = state.copyWith(
            result: record,
            detectedLanguage: source,
            phase: TranslationPhase.success,
            failure: TranslationFailure.storage,
            message: '译文已生成，历史保存失败',
          );
        }
      }
    } catch (error) {
      if (ref.mounted && request == _request) {
        if (error is AppleTranslationException) {
          state = state.copyWith(
            phase: error.isCancelled
                ? TranslationPhase.idle
                : TranslationPhase.error,
            failure: error.isCancelled
                ? TranslationFailure.none
                : TranslationFailure.apple,
            appleErrorCode: error.isCancelled ? null : error.code,
          );
          return;
        }
        // 缺少凭据属于配置错误，给出明确的设置恢复入口文案。
        if (error is BaiduConfigException) {
          state = state.copyWith(
            phase: TranslationPhase.error,
            failure: TranslationFailure.config,
            message: '缺少翻译凭据，请到设置中配置',
          );
          return;
        }
        final failure = switch (state.phase) {
          TranslationPhase.detecting => TranslationFailure.detection,
          TranslationPhase.checkingModel => TranslationFailure.modelCheck,
          TranslationPhase.downloadingModel => TranslationFailure.modelDownload,
          _ => TranslationFailure.translation,
        };
        final message = switch (failure) {
          TranslationFailure.detection => '语言识别失败，请重试',
          TranslationFailure.modelCheck => '无法检查语言模型，请重试',
          TranslationFailure.modelDownload => '语言模型下载失败，请检查网络后重试',
          _ => '翻译失败，请重试',
        };
        state = state.copyWith(
          phase: TranslationPhase.error,
          failure: failure,
          message: message,
          modelDownloadError: error is ModelDownloadException ? error : null,
        );
      }
    } finally {
      // 正常结束也清理宿主；旧请求的 finally 不能动新请求。
      if (request == _request) {
        final apple = _appleService;
        final id = _appleRequestId;
        _appleService = null;
        _appleRequestId = null;
        if (apple != null && id != null) await _cancelApple(apple, id);
      }
    }
  }

  // 从本地重新加载历史记录；截图翻译保存历史后调用，保持历史页数据新鲜。
  Future<void> refreshRecords() async {
    final records = await ref.read(localStoreProvider).search('');
    if (ref.mounted) state = state.copyWith(records: records);
  }

  Future<void> openRecordById(String id) async {
    final record = await ref.read(localStoreProvider).getRecord(id);
    if (!ref.mounted) return;
    if (record == null) {
      state = state.copyWith(
        phase: TranslationPhase.error,
        message: '这条记录不存在或已删除',
      );
      return;
    }
    _invalidateRequest();
    state = state.copyWith(
      input: record.sourceText,
      sourceLanguage: record.sourceLanguage,
      targetLanguage: record.targetLanguage,
      detectedLanguage: record.sourceLanguage,
      result: record,
      phase: TranslationPhase.success,
      failure: TranslationFailure.none,
      message: '来自历史',
    );
  }

  Future<void> toggleFavorite(TranslationRecord record) async {
    if (record.id.isEmpty) return;
    final next = !record.favorite;
    await ref.read(localStoreProvider).setFavorite(record.id, next);
    if (!ref.mounted) return;
    final records = await ref.read(localStoreProvider).search('');
    if (!ref.mounted) return;
    state = state.copyWith(
      result: state.result?.id == record.id
          ? record.withFavorite(next)
          : state.result,
      records: records,
    );
  }

  Future<void> deleteRecord(String id) async {
    await ref.read(localStoreProvider).deleteRecord(id);
    if (!ref.mounted) return;
    final records = await ref.read(localStoreProvider).search('');
    if (!ref.mounted) return;
    state = state.copyWith(
      result: state.result?.id == id ? null : state.result,
      records: records,
    );
  }

  Future<void> clearHistory() async {
    await ref.read(localStoreProvider).clearRecords();
    if (ref.mounted) state = state.copyWith(records: [], result: null);
  }
}
