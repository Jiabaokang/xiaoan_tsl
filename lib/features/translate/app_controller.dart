import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:xiaoan_tsl/core/database/database_provider.dart';
import 'package:xiaoan_tsl/features/history/history_store.dart';
import 'package:xiaoan_tsl/features/language/app_languages.dart';
import 'package:xiaoan_tsl/services/language/language_detection_provider.dart';
import 'package:xiaoan_tsl/services/translation/model_service_provider.dart';
import 'package:xiaoan_tsl/services/translation/translation_service_provider.dart';

// 翻译请求在页面上呈现的阶段。
enum TranslationPhase {
  idle,
  detecting,
  checkingModel,
  downloadingModel,
  translating,
  success,
  error;

  bool get isBusy => switch (this) {
        detecting || checkingModel || downloadingModel || translating => true,
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
    this.loaded = false,
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
  final bool loaded;

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
    bool? loaded,
  }) =>
      AppState(
        input: input ?? this.input,
        sourceLanguage: sourceLanguage ?? this.sourceLanguage,
        targetLanguage: targetLanguage ?? this.targetLanguage,
        defaultTargetLanguage:
            defaultTargetLanguage ?? this.defaultTargetLanguage,
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
        loaded: loaded ?? this.loaded,
      );
}

final appControllerProvider = NotifierProvider<AppController, AppState>(
  AppController.new,
);

// 统一处理识别、模型准备、设备端翻译和本地数据变更。
class AppController extends Notifier<AppState> {
  int _request = 0;
  Future<void>? _initialization;

  @override
  AppState build() {
    Future.microtask(initialize);
    return const AppState();
  }

  Future<void> initialize() => _initialization ??= _load();

  Future<void> _load() async {
    try {
      final store = ref.read(localStoreProvider);
      final target = await store.getSetting('default_target') ?? 'zh';
      final themeName = await store.getSetting('theme_mode') ?? 'system';
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
    _request++;
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
    _request++;
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
    _request++;
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
    if (targetChanged) _request++;
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
    _request++;
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

  Future<void> translate({bool wifiOnly = true}) async {
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
    state = state.copyWith(
      phase: TranslationPhase.detecting,
      failure: TranslationFailure.none,
      message: '正在识别输入语言',
      result: null,
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
      final models = ref.read(translationModelProvider);
      for (final code in {source, target}) {
        state = state.copyWith(
          phase: TranslationPhase.checkingModel,
          message: '正在检查离线模型',
        );
        final downloaded = await models.isDownloaded(code);
        if (!ref.mounted || request != _request) return;
        if (!downloaded) {
          state = state.copyWith(
            phase: TranslationPhase.downloadingModel,
            message: '正在准备离线翻译模型',
          );
          await models.download(code, wifiOnly: wifiOnly);
          if (!ref.mounted || request != _request) return;
        }
      }
      state = state.copyWith(
        phase: TranslationPhase.translating,
        message: '正在设备端翻译',
      );
      final service = ref.read(translationServiceProvider);
      final translated = await service.translate(
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
    } catch (_) {
      if (ref.mounted && request == _request) {
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
        );
      }
    }
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
    _request++;
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
