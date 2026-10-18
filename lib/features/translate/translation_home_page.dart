import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:xiaoan_tsl/core/widgets/app_panel.dart';
import 'package:xiaoan_tsl/features/translate/app_controller.dart';
import 'package:xiaoan_tsl/l10n/app_localizations.dart';
import 'package:xiaoan_tsl/features/language/model_download_progress.dart';
import 'package:xiaoan_tsl/services/translation/model_download_controller.dart';
import 'package:xiaoan_tsl/services/sharing/sharing_service.dart';
import 'package:xiaoan_tsl/services/speech/speech_service_provider.dart';
import 'package:xiaoan_tsl/services/speech/tts_service.dart';

// 翻译首页只负责输入和显示；状态由 Riverpod 控制器保存。
class TranslationHomePage extends ConsumerStatefulWidget {
  const TranslationHomePage({super.key, this.recordId});

  final String? recordId;

  @override
  ConsumerState<TranslationHomePage> createState() =>
      _TranslationHomePageState();
}

// 输入控制器与可恢复的应用状态保持同步。
class _TranslationHomePageState extends ConsumerState<TranslationHomePage> {
  final _input = TextEditingController();
  Timer? _translationTimer;
  bool _speaking = false;
  int _speechRequest = 0;
  SpeechService? _activeSpeech;

  @override
  void initState() {
    super.initState();
    _input.text = ref.read(appControllerProvider).input;
    _loadRecord(widget.recordId);
  }

  @override
  void didUpdateWidget(covariant TranslationHomePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.recordId != widget.recordId) _loadRecord(widget.recordId);
  }

  void _loadRecord(String? id) {
    if (id == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(appControllerProvider.notifier).openRecordById(id);
    });
  }

  @override
  void dispose() {
    _translationTimer?.cancel();
    _speechRequest++;
    if (_speaking) {
      _activeSpeech?.stop();
    }
    _input.dispose();
    super.dispose();
  }

  void _notice(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  // 连续输入只在停顿后翻译，避免每个字符都触发模型与历史写入。
  void _scheduleTranslation() {
    _translationTimer?.cancel();
    if (ref.read(appControllerProvider).input.trim().isEmpty) return;
    _translationTimer = Timer(const Duration(milliseconds: 600), () {
      if (!mounted) return;
      final state = ref.read(appControllerProvider);
      if (state.loaded && state.result == null) {
        ref.read(appControllerProvider.notifier).translate();
      }
    });
  }

  // 输入变化立即撤销旧结果，再安排本次自动翻译。
  void _onInputChanged(String value) {
    ref.read(appControllerProvider.notifier).setInput(value);
    _scheduleTranslation();
  }

  // 新朗读请求先停止旧语音，完成回调只允许更新当前请求。
  Future<void> _speak(String text, String? languageCode) async {
    final l10n = context.l10n;
    if (languageCode == null || languageCode == 'auto') {
      _notice(l10n.selectLanguageFirstNotice);
      return;
    }
    final request = ++_speechRequest;
    final speech = ref.read(speechServiceProvider);
    _activeSpeech = speech;
    try {
      if (_speaking) await speech.stop();
      if (!mounted || request != _speechRequest) return;
      setState(() => _speaking = true);
      await speech.speak(text: text, languageCode: languageCode);
    } catch (error) {
      if (mounted && request == _speechRequest) {
        _notice(
          error is UnsupportedError
              ? error.message ?? l10n.cannotSpeakNotice
              : l10n.ttsFailedNotice,
        );
      }
    } finally {
      if (mounted && request == _speechRequest) {
        setState(() => _speaking = false);
      }
    }
  }

  Future<void> _stopSpeech() async {
    final l10n = context.l10n;
    ++_speechRequest;
    setState(() => _speaking = false);
    try {
      await _activeSpeech?.stop();
    } catch (_) {
      if (mounted) _notice(l10n.stopSpeechFailedNotice);
    }
  }

  // 缺少模型时由用户确认本次下载，移动网络也可使用。
  Future<void> _confirmModelDownload() async {
    final wifiOnly = await confirmModelDownload(context);
    if (wifiOnly != null && mounted) {
      await ref.read(appControllerProvider.notifier).translate(
            downloadMissing: true,
            wifiOnly: wifiOnly,
          );
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(
      appControllerProvider.select((state) => state.phase),
      (previous, next) {
        if (next == TranslationPhase.modelDownloadRequired) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted &&
                ref.read(appControllerProvider).phase ==
                    TranslationPhase.modelDownloadRequired) {
              _confirmModelDownload();
            }
          });
        }
      },
    );
    ref.listen(
      appControllerProvider.select(
        (state) => (state.sourceLanguage, state.targetLanguage),
      ),
      (previous, next) {
        if (ref.read(appControllerProvider).result == null) {
          _scheduleTranslation();
        }
      },
    );
    ref.listen(appControllerProvider.select((state) => state.input), (
      previous,
      next,
    ) {
      if (_input.text != next) {
        _input.value = TextEditingValue(
          text: next,
          selection: TextSelection.collapsed(offset: next.length),
        );
      }
    });
    final state = ref.watch(appControllerProvider);
    final controller = ref.read(appControllerProvider.notifier);
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final reversed = state.sourceLanguage != 'auto' &&
        state.detectedLanguage == state.targetLanguage;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: theme.scaffoldBackgroundColor,
        title: Row(
          children: [
            // 首页品牌图标与 Android、iOS 桌面图标共用同一版设计。
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.asset(
                'assets/branding/app_icon_128.png',
                key: const Key('appBrandIcon'),
                width: 31,
                height: 31,
                fit: BoxFit.cover,
                semanticLabel: l10n.brandIconSemantics,
              ),
            ),
            const SizedBox(width: 9),
            Text(l10n.appName,
                style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
          children: [
            AppPanel(
              child: Row(
                children: [
                  Expanded(
                    child: _languageButton(
                      l10n.sourceLanguageLabel,
                      reversed ? state.targetLanguage : state.sourceLanguage,
                      () => context.push(
                        reversed
                            ? '/languages?mode=target'
                            : '/languages?mode=source',
                      ),
                    ),
                  ),
                  Expanded(
                    child: Center(
                      key: const Key('swapLanguageSlot'),
                      child: IconButton(
                        tooltip: l10n.swapLanguagesTooltip,
                        icon: const Icon(Icons.swap_horiz),
                        onPressed: controller.swapLanguages,
                      ),
                    ),
                  ),
                  Expanded(
                    child: _languageButton(
                      l10n.targetLanguageLabel,
                      reversed ? state.sourceLanguage : state.targetLanguage,
                      () => context.push(
                        reversed
                            ? '/languages?mode=source'
                            : '/languages?mode=target',
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 13),
            AppPanel(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          l10n.inputTextLabel,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          state.detectedLanguage == null
                              ? l10n.waitingForInput
                              : l10n.detectedAs(
                                  l10n.languageName(state.detectedLanguage!),
                                ),
                          style: theme.textTheme.labelSmall,
                        ),
                      ],
                    ),
                    TextField(
                      key: const Key('sourceInput'),
                      controller: _input,
                      maxLength: 5000,
                      minLines: 2,
                      maxLines: 5,
                      decoration: InputDecoration(
                        hintText: l10n.inputHint,
                        border: InputBorder.none,
                        counterText: '',
                      ),
                      onChanged: _onInputChanged,
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '${state.input.length} / 5000',
                          style: theme.textTheme.labelSmall,
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: _speaking
                                  ? l10n.stopSpeakingTooltip
                                  : l10n.readSourceTooltip,
                              icon: Icon(
                                _speaking
                                    ? Icons.stop
                                    : Icons.volume_up_outlined,
                              ),
                              onPressed: _speaking
                                  ? _stopSpeech
                                  : state.input.trim().isEmpty
                                      ? null
                                      : () => _speak(
                                            state.input,
                                            state.detectedLanguage ??
                                                (state.sourceLanguage == 'auto'
                                                    ? null
                                                    : state.sourceLanguage),
                                          ),
                            ),
                            IconButton(
                              tooltip: l10n.clearInputTooltip,
                              icon: const Icon(Icons.close),
                              onPressed: () => _onInputChanged(''),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 13),
            FilledButton.icon(
              onPressed: state.input.trim().isEmpty ||
                      state.phase.isBusy ||
                      !state.loaded
                  ? null
                  : state.phase == TranslationPhase.modelDownloadRequired
                      ? _confirmModelDownload
                      : controller.translate,
              icon: state.phase.isBusy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.arrow_forward),
              label: Text(
                state.phase == TranslationPhase.modelDownloadRequired
                    ? l10n.modelDownloadRequired
                    : state.phase.isBusy
                        ? state.localizedMessage(l10n)
                        : state.phase == TranslationPhase.success
                            ? l10n.translateAgain
                            : l10n.startTranslation,
              ),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(51),
              ),
            ),
            if ((state.phase == TranslationPhase.downloadingModel ||
                    state.failure == TranslationFailure.modelDownload) &&
                state.downloadingModelCode != null)
              Consumer(builder: (context, ref, child) {
                final download = ref
                    .watch(modelDownloadsProvider)[state.downloadingModelCode];
                if (download == null) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          '${l10n.languageName(download.code)} · ${l10n.modelDownloadStep(state.modelDownloadIndex + 1, state.modelDownloadCodes.length)}'),
                      const SizedBox(height: 8),
                      ModelDownloadProgress(status: download),
                    ],
                  ),
                );
              }),
            if (state.phase == TranslationPhase.error &&
                state.failure != TranslationFailure.unsupportedLanguage &&
                state.failure != TranslationFailure.detection &&
                state.failure != TranslationFailure.config) ...[
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: state.failure == TranslationFailure.modelDownload
                    ? _confirmModelDownload
                    : controller.translate,
                child: Text(l10n.retryTranslation),
              ),
            ],
            if (state.phase == TranslationPhase.error &&
                state.failure == TranslationFailure.config) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => context.push('/translation-service'),
                icon: const Icon(Icons.tune),
                label: Text(l10n.goToTranslationService),
              ),
            ],
            const SizedBox(height: 13),
            AppPanel(
              tinted: true,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 10, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          l10n.translationResultLabel,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          state.localizedMessage(l10n),
                          style: theme.textTheme.labelSmall,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 86,
                      child: Align(
                        alignment: Alignment.topLeft,
                        child: SelectableText(
                          state.result?.translatedText ??
                              (state.phase == TranslationPhase.error
                                  ? state.localizedMessage(l10n)
                                  : l10n.translationPlaceholder),
                          style: state.result == null
                              ? theme.textTheme.bodyMedium
                              : theme.textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                        ),
                      ),
                    ),
                    if (state.result != null)
                      Text(
                        switch (state.result!.engine) {
                          'demo' => l10n.demoDisclaimer,
                          'baidu' => l10n.baiduDisclaimer,
                          'apple' => l10n.appleDisclaimer,
                          _ => l10n.googleDisclaimer,
                        },
                        style: theme.textTheme.labelSmall,
                      ),
                    Divider(color: theme.colorScheme.outlineVariant),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            state.result == null
                                ? '—'
                                : '${l10n.languageName(state.result!.sourceLanguage)} → ${l10n.languageName(state.result!.targetLanguage)}',
                            style: theme.textTheme.labelSmall,
                          ),
                        ),
                        IconButton(
                          tooltip: _speaking
                              ? l10n.stopSpeakingTooltip
                              : l10n.readTargetTooltip,
                          icon: Icon(
                            _speaking ? Icons.stop : Icons.volume_up_outlined,
                          ),
                          onPressed: _speaking
                              ? _stopSpeech
                              : state.result == null
                                  ? null
                                  : () => _speak(
                                        state.result!.translatedText,
                                        state.result!.targetLanguage,
                                      ),
                        ),
                        IconButton(
                          tooltip: state.result?.favorite == true
                              ? l10n.unfavoriteTranslationTooltip
                              : l10n.favoriteTranslationTooltip,
                          onPressed: state.result?.id.isNotEmpty == true
                              ? () => controller.toggleFavorite(state.result!)
                              : null,
                          icon: Icon(
                            state.result?.favorite == true
                                ? Icons.star
                                : Icons.star_outline,
                          ),
                        ),
                        IconButton(
                          tooltip: l10n.copyTranslationTooltip,
                          icon: const Icon(Icons.copy_outlined),
                          onPressed: state.result == null
                              ? null
                              : () async {
                                  await SharingService.copyTranslation(
                                    state.result!.translatedText,
                                  );
                                  if (context.mounted) {
                                    _notice(l10n.copiedNotice);
                                  }
                                },
                        ),
                        IconButton(
                          tooltip: l10n.shareTranslationTooltip,
                          icon: const Icon(Icons.share_outlined),
                          onPressed: state.result == null
                              ? null
                              : () async {
                                  final result = state.result!;
                                  await SharingService.shareTranslation(
                                    sourceText: result.sourceText,
                                    translatedText: result.translatedText,
                                  );
                                },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _languageButton(String caption, String code, VoidCallback onTap) {
    final l10n = context.l10n;
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(caption, style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 3),
          Text(
            l10n.languageName(code),
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}
