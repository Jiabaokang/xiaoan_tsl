import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:xiaoan_tsl/core/database/database_provider.dart';
import 'package:xiaoan_tsl/features/history/history_store.dart';
import 'package:xiaoan_tsl/features/translate/app_controller.dart';
import 'package:xiaoan_tsl/services/desktop/macos_desktop_service.dart';
import 'package:xiaoan_tsl/services/language/language_detection_provider.dart';
import 'package:xiaoan_tsl/services/translation/baidu_translation_service.dart';
import 'package:xiaoan_tsl/services/translation/translation_service.dart';
import 'package:xiaoan_tsl/services/translation/translation_service_provider.dart';

// 截图会话阶段；取消不进入 failed，直接回 idle。
enum ScreenshotStage {
  idle,
  capturing,
  ocr,
  needsConfirm,
  translating,
  done,
  failed
}

// 截图翻译失败分类；页面据此选择本地化文案。
enum ScreenshotFailure {
  none,
  permissionDenied,
  captureFailed,
  invalidData,
  ocrFailed,
  noText,
  tooLong,
  missingCredentials,
  timeout,
  translationFailed,
  unsupported,
}

// 一次截图翻译会话的状态；pngBytes 在关闭与 Esc 时释放。
class ScreenshotState {
  const ScreenshotState({
    required this.stage,
    this.failure = ScreenshotFailure.none,
    this.pngBytes,
    this.selection,
    this.displayId,
    this.recognizedText,
    this.translatedText,
    this.confirmRequired = false,
    this.historySaveFailed = false,
  });

  static const idle = ScreenshotState(stage: ScreenshotStage.idle);

  final ScreenshotStage stage;
  final ScreenshotFailure failure;

  // 选区截图 PNG 字节；done/failed 阶段仍保留用于展示。
  final Uint8List? pngBytes;

  // 选区与所在显示器（左下原点 point 坐标，与原生一致）。
  final Rect? selection;
  final int? displayId;

  // OCR 原文与译文；截图固定 en → zh。
  final String? recognizedText;
  final String? translatedText;

  // 语言不确定时等待用户确认“按英文翻译”。
  final bool confirmRequired;

  // 译文已生成但历史保存失败（不阻断展示）。
  final bool historySaveFailed;

  bool get busy =>
      stage == ScreenshotStage.capturing ||
      stage == ScreenshotStage.ocr ||
      stage == ScreenshotStage.translating;

  ScreenshotState copyWith({
    ScreenshotStage? stage,
    ScreenshotFailure? failure,
    Uint8List? pngBytes,
    Rect? selection,
    int? displayId,
    String? recognizedText,
    String? translatedText,
    bool? confirmRequired,
    bool? historySaveFailed,
  }) {
    return ScreenshotState(
      stage: stage ?? this.stage,
      failure: failure ?? this.failure,
      pngBytes: pngBytes ?? this.pngBytes,
      selection: selection ?? this.selection,
      displayId: displayId ?? this.displayId,
      recognizedText: recognizedText ?? this.recognizedText,
      translatedText: translatedText ?? this.translatedText,
      confirmRequired: confirmRequired ?? this.confirmRequired,
      historySaveFailed: historySaveFailed ?? this.historySaveFailed,
    );
  }
}

// 截图翻译会话控制器：捕获 → OCR → 语言确认 → 固定 en→zh 翻译 → 保存历史。
// 新截图、服务切换都会使旧会话失效，晚到的响应既不显示也不写入历史。
final screenshotControllerProvider =
    NotifierProvider<ScreenshotController, ScreenshotState>(
  ScreenshotController.new,
);

class ScreenshotController extends Notifier<ScreenshotState> {
  ScreenshotController({
    this.translateTimeout = const Duration(seconds: 30),
  });

  // 翻译调用超时；测试可注入更短时长。
  final Duration translateTimeout;

  // 会话序号：新截图、服务切换与关闭都会递增，用于丢弃晚到响应。
  int _session = 0;

  // 请求开始固定的服务实例，避免截图与翻译之间服务切换。
  TranslationService? _fixedService;

  @override
  ScreenshotState build() {
    // 服务偏好变化时让截图会话立即失效，旧响应不得显示或写入历史。
    ref.listen(translationEngineProvider, (previous, next) {
      if (previous == next) return;
      _session++;
      _fixedService = null;
      state = const ScreenshotState(stage: ScreenshotStage.idle);
    });
    return ScreenshotState.idle;
  }

  // 开始一次新截图：先明确取消旧会话再开启新会话，符合重复触发规则。
  Future<void> startCapture() async {
    final desktop = ref.read(macosDesktopServiceProvider);
    _session++;
    final session = _session;
    _fixedService = ref.read(translationServiceProvider);
    try {
      await desktop.cancelCapture('shot-${session - 1}');
    } catch (_) {
      // 首次触发或通道未就绪时忽略。
    }
    state = const ScreenshotState(stage: ScreenshotStage.capturing);
    try {
      final result = await desktop.captureRegion('shot-$session');
      if (!ref.mounted || session != _session) return;
      if (result.cancelled) {
        state = ScreenshotState.idle;
        return;
      }
      final png = result.pngBytes;
      final selection = result.selection;
      final displayId = result.displayId;
      if (png == null ||
          png.isEmpty ||
          selection == null ||
          displayId == null) {
        _fail(ScreenshotFailure.invalidData, session);
        return;
      }
      state = ScreenshotState(
        stage: ScreenshotStage.ocr,
        pngBytes: png,
        selection: selection,
        displayId: displayId,
      );
      // 结果窗口定位在原生侧完成；失败不影响识别流程。
      try {
        await desktop.showResultWindow(
          displayId: displayId,
          selection: selection,
        );
      } catch (_) {}
      await _recognize(session);
    } on MacosDesktopPermissionException {
      _fail(ScreenshotFailure.permissionDenied, session);
    } on MacosDesktopPlatformUnsupportedException {
      _fail(ScreenshotFailure.unsupported, session);
    } catch (_) {
      _fail(ScreenshotFailure.captureFailed, session);
    }
  }

  Future<void> _recognize(int session) async {
    final png = state.pngBytes;
    if (png == null) return;
    try {
      final text = await ref
          .read(macosDesktopServiceProvider)
          .recognizeText('shot-$session', png);
      if (!ref.mounted || session != _session) return;
      final trimmed = text.trim();
      if (trimmed.isEmpty) {
        _fail(ScreenshotFailure.noText, session);
        return;
      }
      if (trimmed.length > 5000) {
        _fail(ScreenshotFailure.tooLong, session);
        return;
      }
      state = ScreenshotState(
        stage: ScreenshotStage.needsConfirm,
        pngBytes: png,
        selection: state.selection,
        displayId: state.displayId,
        recognizedText: trimmed,
      );
      final detected =
          await ref.read(languageDetectionProvider).identify(trimmed);
      if (!ref.mounted || session != _session) return;
      if (detected != 'en') {
        // 低置信度或非英文先提示；用户明确“按英文翻译”后才发请求。
        state = state.copyWith(confirmRequired: true);
      } else {
        await _translate(session);
      }
    } on MacosDesktopOcrException {
      _fail(ScreenshotFailure.ocrFailed, session);
    } catch (_) {
      _fail(ScreenshotFailure.ocrFailed, session);
    }
  }

  // 用户确认“按英文翻译”。
  Future<void> confirmAndTranslate() async {
    if (state.stage != ScreenshotStage.needsConfirm) return;
    await _translate(_session);
  }

  // 重试复用已识别原文，不重复截图与 OCR。
  Future<void> retry() async {
    if (state.stage != ScreenshotStage.failed) return;
    if (state.recognizedText == null || state.recognizedText!.isEmpty) return;
    await _translate(_session);
  }

  Future<void> _translate(int session) async {
    final text = state.recognizedText;
    if (text == null || text.isEmpty) return;
    state = state.copyWith(
      stage: ScreenshotStage.translating,
      confirmRequired: false,
    );
    final service = (_fixedService ?? ref.read(translationServiceProvider))!;
    try {
      final translated = await service
          .translate(text: text, sourceLanguage: 'en', targetLanguage: 'zh')
          .timeout(translateTimeout);
      if (!ref.mounted || session != _session) return;
      state = state.copyWith(
        stage: ScreenshotStage.done,
        translatedText: translated,
      );
      await _saveHistory(session, service.engineId);
    } on BaiduConfigException {
      _fail(ScreenshotFailure.missingCredentials, session);
    } on TimeoutException {
      _fail(ScreenshotFailure.timeout, session);
    } catch (_) {
      _fail(ScreenshotFailure.translationFailed, session);
    }
  }

  Future<void> _saveHistory(int session, String engine) async {
    final record = TranslationRecord(
      sourceText: state.recognizedText ?? '',
      translatedText: state.translatedText ?? '',
      sourceLanguage: 'en',
      targetLanguage: 'zh',
      createdAt: DateTime.now(),
      engine: engine,
    );
    try {
      await ref.read(localStoreProvider).saveRecord(record);
      if (!ref.mounted || session != _session) return;
      // 历史页数据由 AppController 统一持有，保存后刷新。
      await ref.read(appControllerProvider.notifier).refreshRecords();
      if (!ref.mounted || session != _session) return;
    } catch (_) {
      if (!ref.mounted || session != _session) return;
      state = state.copyWith(historySaveFailed: true);
    }
  }

  // 关闭结果页：取消进行中的捕获并释放截图内存。
  Future<void> dismiss() async {
    _session++;
    _fixedService = null;
    try {
      await ref
          .read(macosDesktopServiceProvider)
          .cancelCapture('shot-$_session');
    } catch (_) {}
    state = ScreenshotState.idle;
  }

  void _fail(ScreenshotFailure failure, int session) {
    if (!ref.mounted || session != _session) return;
    state = state.copyWith(stage: ScreenshotStage.failed, failure: failure);
  }
}
