import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaoan_tsl/services/translation/mlkit_model_service.dart';
import 'package:xiaoan_tsl/services/translation/model_download_controller.dart';
import 'package:xiaoan_tsl/services/translation/model_download_status.dart';
import 'package:xiaoan_tsl/services/translation/model_service_provider.dart';

// 控制原生完成与进度事件，验证共享任务的去重、恢复和完成边界。
class _Models implements TranslationModelService, ModelDownloadEventSource {
  final events = StreamController<ModelDownloadStatus>.broadcast(sync: true);
  final gate = Completer<void>();
  final downloaded = <String>{};
  int starts = 0;
  String? mobileCode;

  @override
  Stream<ModelDownloadStatus> get downloadEvents => events.stream;
  @override
  Future<void> allowMobileData(String code) async => mobileCode = code;
  @override
  Future<bool> isDownloaded(String code) async => downloaded.contains(code);
  @override
  Future<void> download(String code, {bool wifiOnly = true}) async {
    starts++;
    await gate.future;
  }

  @override
  Future<void> delete(String code) async => downloaded.remove(code);
}

void main() {
  late _Models models;
  late ProviderContainer container;
  setUp(() {
    models = _Models();
    container = ProviderContainer(overrides: [
      translationModelProvider.overrideWithValue(models),
    ]);
  });
  tearDown(() async {
    container.dispose();
    await models.events.close();
  });

  test('同一模型复用任务，真实进度不足以宣布可用，SDK完成后仍查询设备', () async {
    final controller = container.read(modelDownloadsProvider.notifier);
    final first = controller.download('ja');
    final second = controller.download('ja');
    expect(models.starts, 1);
    models.events.add(const ModelDownloadStatus(
      code: 'ja',
      phase: ModelDownloadPhase.downloading,
      progress: 1,
    ));
    expect(container.read(modelDownloadsProvider)['ja']!.progress, .99);
    expect(container.read(modelDownloadsProvider)['ja']!.isActive, isTrue);
    models.downloaded.add('ja');
    models.gate.complete();
    await Future.wait([first, second]);
    expect(container.read(modelDownloadsProvider)['ja']!.phase,
        ModelDownloadPhase.completed);
  });

  test('原生下载完成但设备没有模型时显示失败而非已下载', () async {
    final pending =
        container.read(modelDownloadsProvider.notifier).download('ja');
    final assertion =
        expectLater(pending, throwsA(isA<ModelDownloadException>()));
    models.gate.complete();
    await assertion;
    expect(container.read(modelDownloadsProvider)['ja']!.phase,
        ModelDownloadPhase.failed);
  });

  test('等待Wi-Fi可切换本次网络策略，失败保留原始诊断', () async {
    final controller = container.read(modelDownloadsProvider.notifier);
    final pending = controller.download('ja');
    models.events.add(const ModelDownloadStatus(
      code: 'ja',
      phase: ModelDownloadPhase.waitingWifi,
      canUseMobile: true,
    ));
    await controller.allowMobileData('ja');
    expect(models.mobileCode, 'ja');
    const detail = 'MLKit error 101: disk full';
    final assertion =
        expectLater(pending, throwsA(isA<ModelDownloadException>()));
    models.gate.completeError(ModelDownloadException(
      ModelDownloadFailure.storage,
      detail,
    ));
    await assertion;
    final status = container.read(modelDownloadsProvider)['ja']!;
    expect(status.error!.failure, ModelDownloadFailure.storage);
    expect(status.error!.details, detail);
    expect(status.canUseMobile, isFalse);
  });

  test('无有效进度时不伪造百分比，离开消费者不丢失任务', () async {
    final subscription = container.listen(modelDownloadsProvider, (_, _) {});
    final pending =
        container.read(modelDownloadsProvider.notifier).download('ja');
    models.events.add(const ModelDownloadStatus(
      code: 'ja',
      phase: ModelDownloadPhase.downloading,
      progress: double.nan,
    ));
    subscription.close();
    await pumpEventQueue();
    expect(container.read(modelDownloadsProvider)['ja']!.progress, isNull);
    models.downloaded.add('ja');
    models.gate.complete();
    await pending;
    expect(models.starts, 1);
  });
}
