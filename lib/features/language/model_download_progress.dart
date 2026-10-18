import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:xiaoan_tsl/l10n/app_localizations.dart';
import 'package:xiaoan_tsl/services/translation/model_download_controller.dart';
import 'package:xiaoan_tsl/services/translation/model_download_status.dart';

// 返回本次下载是否仅限 Wi-Fi；关闭弹窗返回空，不发起下载。
Future<bool?> confirmModelDownload(BuildContext context, {String? code}) {
  final l10n = context.l10n;
  return showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(code == null
          ? l10n.modelDownloadRequired
          : l10n.modelDownloadTitle(l10n.languageName(code))),
      content: Text(code == null
          ? '${l10n.modelDownloadDialogContent}\n\n${l10n.modelDownloadNotice}'
          : l10n.modelDownloadNotice),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: Text(l10n.cancel),
        ),
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: Text(l10n.allowMobileDownload),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: Text(l10n.wifiDownloadAction),
        ),
      ],
    ),
  );
}

// 用状态文字配合进度条与恢复操作，未知进度保持不定动画。
class ModelDownloadProgress extends ConsumerWidget {
  const ModelDownloadProgress({super.key, required this.status, this.onRetry});

  final ModelDownloadStatus status;
  final VoidCallback? onRetry;

  Future<void> _allowMobile(BuildContext context, WidgetRef ref) async {
    final wifiOnly = await confirmModelDownload(context, code: status.code);
    if (wifiOnly != false || !context.mounted) return;
    try {
      await ref
          .read(modelDownloadsProvider.notifier)
          .allowMobileData(status.code);
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(context.l10n.modelDownloadFailure('unknown')),
      ));
    }
  }

  void _showDetails(BuildContext context) {
    final l10n = context.l10n;
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.viewDownloadDetails),
        content: SingleChildScrollView(
          child: SelectableText(status.error!.details),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () async {
              await Clipboard.setData(
                  ClipboardData(text: status.error!.details));
              if (!dialogContext.mounted) return;
              Navigator.pop(dialogContext);
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(l10n.downloadDetailsCopied),
              ));
            },
            child: Text(l10n.copyDownloadDetails),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final progress = status.progress;
    final label = switch (status.phase) {
      ModelDownloadPhase.preparing => l10n.modelPreparing,
      ModelDownloadPhase.waitingWifi => l10n.modelWaitingWifi,
      ModelDownloadPhase.waitingNetwork => l10n.modelWaitingNetwork,
      ModelDownloadPhase.downloading => progress == null
          ? l10n.modelDownloading
          : '${l10n.modelDownloading} ${(progress * 100).floor()}%',
      ModelDownloadPhase.completed => l10n.modelDownloadComplete,
      ModelDownloadPhase.failed =>
        l10n.modelDownloadFailure(status.error?.failure.name ?? 'unknown'),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          liveRegion: status.phase != ModelDownloadPhase.downloading,
          child: Text(label,
              style: status.phase == ModelDownloadPhase.failed
                  ? TextStyle(color: Theme.of(context).colorScheme.error)
                  : null),
        ),
        if (status.isActive &&
            status.phase != ModelDownloadPhase.waitingWifi &&
            status.phase != ModelDownloadPhase.waitingNetwork) ...[
          const SizedBox(height: 8),
          ExcludeSemantics(child: LinearProgressIndicator(value: progress)),
        ],
        if (status.isSlow) ...[
          const SizedBox(height: 8),
          Text(l10n.modelDownloadSlow),
        ],
        if (status.canUseMobile)
          TextButton(
            onPressed: () => _allowMobile(context, ref),
            child: Text(l10n.allowMobileDownload),
          ),
        if (status.phase == ModelDownloadPhase.failed)
          Wrap(
            spacing: 8,
            children: [
              if (onRetry != null)
                TextButton(onPressed: onRetry, child: Text(l10n.retryDownload)),
              if (status.error != null)
                TextButton(
                  onPressed: () => _showDetails(context),
                  child: Text(l10n.viewDownloadDetails),
                ),
            ],
          ),
      ],
    );
  }
}
