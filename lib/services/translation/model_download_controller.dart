import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'mlkit_model_service.dart';
import 'model_download_status.dart';
import 'model_service_provider.dart';

// 不随页面销毁，首页和语言包列表复用同一份任务及失败信息。
final modelDownloadsProvider =
    NotifierProvider<ModelDownloadController, Map<String, ModelDownloadStatus>>(
      ModelDownloadController.new,
    );

// 合并重复下载并订阅原生状态，等待过久仅提示，不伪装为底层取消。
class ModelDownloadController
    extends Notifier<Map<String, ModelDownloadStatus>> {
  final _pending = <String, Future<void>>{};
  final _slowTimers = <String, Timer>{};
  late TranslationModelService _models;

  @override
  Map<String, ModelDownloadStatus> build() {
    _models = ref.read(translationModelProvider);
    final source = _models;
    final subscription = source is ModelDownloadEventSource
        ? (source as ModelDownloadEventSource).downloadEvents.listen(
            _onUpdate,
            // 下载结果由方法调用决定，事件通道错误不能冒充下载失败。
            onError: (Object _) {},
          )
        : null;
    ref.onDispose(() {
      unawaited(subscription?.cancel());
      for (final timer in _slowTimers.values) {
        timer.cancel();
      }
    });
    return {};
  }

  // 所有调用者等待同一 Future，离页不会取消 SDK 任务或重复发起下载。
  Future<void> download(String code, {bool wifiOnly = true}) {
    final existing = _pending[code];
    if (existing != null) return existing;
    state = {
      ...state,
      code: ModelDownloadStatus(
        code: code,
        phase: ModelDownloadPhase.preparing,
      ),
    };
    _armSlowNotice(code);
    final future = _download(code, wifiOnly: wifiOnly);
    _pending[code] = future;
    return future;
  }

  Future<void> _download(String code, {required bool wifiOnly}) async {
    try {
      await _models.download(code, wifiOnly: wifiOnly);
      if (!await _models.isDownloaded(code)) {
        throw ModelDownloadException(
          ModelDownloadFailure.unknown,
          'SDK 已返回完成，但设备上尚未找到语言模型',
        );
      }
      if (ref.mounted) {
        state = {
          ...state,
          code: ModelDownloadStatus(
            code: code,
            phase: ModelDownloadPhase.completed,
            progress: 1,
          ),
        };
      }
    } catch (error) {
      final failure = error is ModelDownloadException
          ? error
          : ModelDownloadException(
              ModelDownloadFailure.unknown,
              error.toString(),
            );
      if (ref.mounted) {
        state = {
          ...state,
          code: ModelDownloadStatus(
            code: code,
            phase: ModelDownloadPhase.failed,
            error: failure,
          ),
        };
      }
      throw failure;
    } finally {
      _slowTimers.remove(code)?.cancel();
      _pending.remove(code);
    }
  }

  // 删除成功后移除历史快照，不能把已删除的语言包继续显示为可用。
  void forget(String code) {
    if (state[code]?.isActive == true) return;
    state = {...state}..remove(code);
  }

  Future<void> allowMobileData(String code) async {
    final source = _models;
    if (state[code]?.canUseMobile != true ||
        source is! ModelDownloadEventSource) {
      return;
    }
    await (source as ModelDownloadEventSource).allowMobileData(code);
  }

  void _onUpdate(ModelDownloadStatus update) {
    if (!ref.mounted || !update.isActive) return;
    final previous = state[update.code];
    if (previous == null || !previous.isActive) return;
    final raw = update.progress;
    final progress = raw != null && raw.isFinite && raw >= 0 && raw <= 1
        ? math.max(previous.progress ?? 0, math.min(raw, .99))
        : previous.progress;
    state = {
      ...state,
      update.code: ModelDownloadStatus(
        code: update.code,
        phase: update.phase,
        progress: progress,
        canUseMobile: update.canUseMobile,
        isSlow: progress == previous.progress && update.phase == previous.phase
            ? previous.isSlow
            : false,
      ),
    };
    if (progress != previous.progress || update.phase != previous.phase) {
      _armSlowNotice(update.code);
    }
  }

  void _armSlowNotice(String code) {
    _slowTimers.remove(code)?.cancel();
    _slowTimers[code] = Timer(const Duration(seconds: 45), () {
      final current = state[code];
      if (current == null ||
          !current.isActive ||
          current.phase == ModelDownloadPhase.waitingWifi ||
          current.phase == ModelDownloadPhase.waitingNetwork) {
        return;
      }
      state = {
        ...state,
        code: ModelDownloadStatus(
          code: code,
          phase: current.phase,
          progress: current.progress,
          canUseMobile: current.canUseMobile,
          isSlow: true,
        ),
      };
    });
  }
}
