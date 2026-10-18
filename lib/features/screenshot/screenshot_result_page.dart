import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:xiaoan_tsl/l10n/app_localizations.dart';

import 'screenshot_controller.dart';

// 截图翻译结果页：截图在上、中文译文在下；Esc 与关闭释放截图内存。
class ScreenshotResultPage extends ConsumerStatefulWidget {
  const ScreenshotResultPage({super.key, this.desktopWindow = false, this.onConfigure});

  // 独立桌面窗口由应用事件桥关闭，不操作主窗口的导航栈。
  final bool desktopWindow;
  final VoidCallback? onConfigure;

  @override
  ConsumerState<ScreenshotResultPage> createState() =>
      _ScreenshotResultPageState();
}

// 渲染会话状态并处理复制、重试与关闭；桌面模式保留主页的导航状态。
class _ScreenshotResultPageState extends ConsumerState<ScreenshotResultPage> {
  @override
  Widget build(BuildContext context) {
    final state = ref.watch(screenshotControllerProvider);
    final l10n = context.l10n;
    // 服务切换或外部关闭把会话置回 idle 时关闭本页。
    ref.listen(screenshotControllerProvider, (previous, next) {
      if (!widget.desktopWindow && next.stage == ScreenshotStage.idle &&
          previous?.stage != ScreenshotStage.idle) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
          }
        });
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.screenshotResultTitle),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            key: const Key('screenshotCloseButton'),
            icon: const Icon(Icons.close),
            tooltip: l10n.screenshotClose,
            onPressed: () {
              ref.read(screenshotControllerProvider.notifier).dismiss();
              if (!widget.desktopWindow && mounted && Navigator.of(context).canPop()) {
                Navigator.of(context).pop();
              }
            },
          ),
        ],
      ),
      body: Focus(
        autofocus: true,
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.escape) {
            ref.read(screenshotControllerProvider.notifier).dismiss();
            if (!widget.desktopWindow && mounted && Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            }
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: _buildBody(state, l10n),
      ),
    );
  }

  Widget _buildBody(ScreenshotState state, AppLocalizations l10n) {
    switch (state.stage) {
      case ScreenshotStage.idle:
        return const SizedBox.shrink();
      case ScreenshotStage.capturing:
        return _CenteredProgress(l10n.screenshotCapturing);
      case ScreenshotStage.ocr:
        return _CenteredProgress(l10n.screenshotRecognizing);
      case ScreenshotStage.translating:
        return _content(state, l10n,
            progress: _CenteredProgress(l10n.screenshotTranslating));
      case ScreenshotStage.needsConfirm:
        if (!state.confirmRequired) {
          return _content(state, l10n,
              progress: _CenteredProgress(l10n.screenshotJudgingLanguage));
        }
        return _content(
          state,
          l10n,
          footer: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(l10n.screenshotConfirmPrompt),
                const SizedBox(height: 12),
                FilledButton.icon(
                  key: const Key('screenshotConfirmTranslate'),
                  onPressed: () => ref
                      .read(screenshotControllerProvider.notifier)
                      .confirmAndTranslate(),
                  icon: const Icon(Icons.translate),
                  label: Text(l10n.screenshotTranslateAsEnglish),
                ),
              ],
            ),
          ),
        );
      case ScreenshotStage.done:
        return _content(
          state,
          l10n,
          footer: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (state.historySaveFailed)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    l10n.screenshotHistorySaveFailed,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    FilledButton.icon(
                      key: const Key('screenshotCopyButton'),
                      onPressed: () => _copy(state.translatedText ?? ''),
                      icon: const Icon(Icons.copy),
                      label: Text(l10n.screenshotCopy),
                    ),
                    OutlinedButton.icon(
                      key: const Key('screenshotReshootButton'),
                      onPressed: () => ref
                          .read(screenshotControllerProvider.notifier)
                          .startCapture(),
                      icon: const Icon(Icons.crop_free),
                      label: Text(l10n.screenshotReshoot),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      case ScreenshotStage.failed:
        return _content(
          state,
          l10n,
          footer: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _failureText(state.failure, l10n),
                  key: const Key('screenshotFailureText'),
                ),
                const SizedBox(height: 12),
                if (state.failure == ScreenshotFailure.missingCredentials)
                  FilledButton.icon(
                    key: const Key('screenshotGoConfigButton'),
                    onPressed: () {
                      if (widget.desktopWindow) {
                        widget.onConfigure?.call();
                      } else {
                        context.push('/translation-service');
                      }
                    },
                    icon: const Icon(Icons.settings),
                    label: Text(l10n.screenshotGoConfig),
                  )
                else if (state.recognizedText != null &&
                    state.recognizedText!.isNotEmpty)
                  FilledButton.icon(
                    key: const Key('screenshotRetryButton'),
                    onPressed: () =>
                        ref.read(screenshotControllerProvider.notifier).retry(),
                    icon: const Icon(Icons.refresh),
                    label: Text(l10n.screenshotRetry),
                  ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  key: const Key('screenshotFailedReshootButton'),
                  onPressed: () => ref
                      .read(screenshotControllerProvider.notifier)
                      .startCapture(),
                  icon: const Icon(Icons.crop_free),
                  label: Text(l10n.screenshotReshoot),
                ),
              ],
            ),
          ),
        );
    }
  }

  // 截图在上、原文/译文在下；长内容整体滚动。
  Widget _content(
    ScreenshotState state,
    AppLocalizations l10n, {
    Widget? progress,
    Widget? footer,
  }) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (state.pngBytes != null)
          Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 260),
                child: Image.memory(
                  state.pngBytes!,
                  fit: BoxFit.contain,
                  key: const Key('screenshotImage'),
                ),
              ),
            ),
          ),
        if (state.pngBytes != null) const SizedBox(height: 16),
        if (state.recognizedText != null) ...[
          Text(l10n.screenshotOriginalLabel,
              style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 4),
          SelectableText(
            state.recognizedText!,
            key: const Key('screenshotRecognizedText'),
          ),
          const SizedBox(height: 16),
        ],
        ?progress,
        if (state.translatedText != null) ...[
          Text(l10n.screenshotTranslatedLabel,
              style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 4),
          SelectableText(
            state.translatedText!,
            key: const Key('screenshotTranslatedText'),
          ),
        ],
        if (footer != null) ...[
          const SizedBox(height: 16),
          footer,
        ],
      ],
    );
  }

  String _failureText(ScreenshotFailure failure, AppLocalizations l10n) {
    return switch (failure) {
      ScreenshotFailure.permissionDenied => l10n.screenshotPermissionDenied,
      ScreenshotFailure.captureFailed => l10n.screenshotCaptureFailed,
      ScreenshotFailure.invalidData => l10n.screenshotInvalidData,
      ScreenshotFailure.ocrFailed => l10n.screenshotOcrFailed,
      ScreenshotFailure.noText => l10n.screenshotNoText,
      ScreenshotFailure.tooLong => l10n.screenshotTooLong,
      ScreenshotFailure.missingCredentials => l10n.screenshotMissingCredentials,
      ScreenshotFailure.timeout => l10n.screenshotTimeout,
      ScreenshotFailure.translationFailed => l10n.screenshotFailed,
      ScreenshotFailure.unsupported => l10n.screenshotPlatformUnsupported,
      ScreenshotFailure.none => '',
    };
  }

  Future<void> _copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(context.l10n.screenshotCopied)));
  }
}

// 居中进度提示。
class _CenteredProgress extends StatelessWidget {
  const _CenteredProgress(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(label),
          ],
        ),
      ),
    );
  }
}
