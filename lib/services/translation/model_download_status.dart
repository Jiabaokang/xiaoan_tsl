import 'package:flutter/services.dart';

// 下载阶段区分网络等待与传输，完成只以 SDK 和设备查询结果为准。
enum ModelDownloadPhase {
  preparing,
  waitingWifi,
  waitingNetwork,
  downloading,
  completed,
  failed,
}

// 只使用 SDK 能确认的错误类别，未知错误保留诊断而不猜测原因。
enum ModelDownloadFailure { network, storage, integrity, unavailable, unknown }

// 可恢复的模型下载错误，同时保存原生错误信息供用户复制反馈。
class ModelDownloadException extends StateError {
  ModelDownloadException(this.failure, this.details) : super(details);

  factory ModelDownloadException.fromPlatform(PlatformException error) {
    return ModelDownloadException(
      ModelDownloadFailure.values.firstWhere(
        (value) => value.name == error.code,
        orElse: () => ModelDownloadFailure.unknown,
      ),
      '${error.code}: ${error.message ?? ''}\n${error.details ?? ''}'.trim(),
    );
  }

  final ModelDownloadFailure failure;
  final String details;
}

// 一种语言的共享下载快照；无可靠进度时 progress 为空。
class ModelDownloadStatus {
  const ModelDownloadStatus({
    required this.code,
    required this.phase,
    this.progress,
    this.canUseMobile = false,
    this.isSlow = false,
    this.error,
  });

  final String code;
  final ModelDownloadPhase phase;
  final double? progress;
  // 只有尚未交给 SDK 的任务允许变更本次网络策略。
  final bool canUseMobile;
  final bool isSlow;
  final ModelDownloadException? error;

  bool get isActive =>
      phase != ModelDownloadPhase.completed &&
      phase != ModelDownloadPhase.failed;
}

// 支持原生进度的服务额外提供事件；测试或其他服务无需伪造进度。
abstract interface class ModelDownloadEventSource {
  Stream<ModelDownloadStatus> get downloadEvents;
  Future<void> allowMobileData(String code);
}
