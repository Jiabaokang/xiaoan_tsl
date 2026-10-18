import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:xiaoan_tsl/features/language/app_languages.dart';
import 'package:xiaoan_tsl/features/translate/app_controller.dart';
import 'package:xiaoan_tsl/l10n/app_localizations.dart';
import 'package:xiaoan_tsl/services/translation/model_service_provider.dart';
import 'package:xiaoan_tsl/services/translation/model_download_controller.dart';
import 'package:xiaoan_tsl/services/translation/model_download_status.dart';
import 'model_download_progress.dart';
import 'package:xiaoan_tsl/services/translation/translate_language_code.dart';
import 'package:xiaoan_tsl/services/translation/translation_service_provider.dart';

// 从 ML Kit 读取实时模型状态，提供下载与删除操作。
class OfflineModelsPage extends ConsumerStatefulWidget {
  const OfflineModelsPage({super.key});

  @override
  ConsumerState<OfflineModelsPage> createState() => _OfflineModelsPageState();
}

// 只缓存本次页面查询结果；重新进入或操作后再次向 SDK 查询。
class _OfflineModelsPageState extends ConsumerState<OfflineModelsPage> {
  late Future<Map<String, bool>> _status;
  String? _operatingCode;
  String? _error;

  @override
  void initState() {
    super.initState();
    _status = _loadStatus();
  }

  Future<Map<String, bool>> _loadStatus() async {
    // 不支持 ML Kit 的平台直接路由保护：不读取模型 Provider，避免创建插件对象。
    if (ref.read(translationPlatformProvider) == TranslationPlatform.macOS) {
      return const {};
    }
    final models = ref.read(translationModelProvider);
    final status = <String, bool>{};
    for (final code in appLanguages.keys) {
      if (code != 'auto' && translateLanguageForCode(code) != null) {
        status[code] = await models.isDownloaded(code);
      }
    }
    return status;
  }

  void _refresh() => setState(() {
        _status = _loadStatus();
      });

  Future<void> _operate(
    String code, {
    required bool remove,
    bool wifiOnly = true,
  }) async {
    if (_operatingCode != null) return;
    final l10n = context.l10n;
    setState(() {
      _operatingCode = code;
      _error = null;
    });
    try {
      final models = ref.read(translationModelProvider);
      if (remove) {
        await models.delete(code);
        if (mounted) ref.read(modelDownloadsProvider.notifier).forget(code);
      } else {
        await ref
            .read(modelDownloadsProvider.notifier)
            .download(code, wifiOnly: wifiOnly);
      }
      if (!mounted) return;
      setState(() {
        _operatingCode = null;
        _status = _loadStatus();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _operatingCode = null;
        _error = remove ? l10n.deleteModelFailed : null;
      });
    }
  }

  // 用户在发起任务前选择本次网络策略；离页后共享控制器继续持有任务。
  Future<void> _confirmDownload(String code) async {
    final wifiOnly = await confirmModelDownload(context, code: code);
    if (wifiOnly != null && mounted) {
      await _operate(code, remove: false, wifiOnly: wifiOnly);
    }
  }

  @override
  Widget build(BuildContext context) {
    final translating = ref.watch(
      appControllerProvider.select((state) => state.phase.isBusy),
    );
    final l10n = context.l10n;

    // 不支持 ML Kit 的平台直接展示说明，不初始化模型管理。
    if (ref.watch(translationPlatformProvider) == TranslationPlatform.macOS) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.offlineModelsLabel)),
        body: Center(child: Text(l10n.offlineModelsUnsupported)),
      );
    }

    final downloads = ref.watch(modelDownloadsProvider);
    ref.listen(modelDownloadsProvider, (previous, next) {
      if (previous != null &&
          next.entries.any((entry) =>
              previous[entry.key]?.isActive == true && !entry.value.isActive)) {
        _refresh();
      }
    });
    return Scaffold(
      appBar: AppBar(title: Text(l10n.offlineModelsLabel)),
      body: SafeArea(
        child: FutureBuilder<Map<String, bool>>(
          future: _status,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(l10n.cannotReadStatus),
                    TextButton(
                      onPressed: _refresh,
                      child: Text(l10n.retryQuery),
                    ),
                  ],
                ),
              );
            }
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            final status = snapshot.data ?? {};
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(l10n.offlineModelsPageNotice),
                ),
                if (_error != null) ...[
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                for (final entry in status.entries)
                  ListTile(
                    key: Key('model_${entry.key}'),
                    title: Text(l10n.languageName(entry.key)),
                    subtitle: downloads[entry.key] != null
                        ? Padding(
                            padding: const EdgeInsets.only(top: 8, bottom: 8),
                            child: ModelDownloadProgress(
                              status: downloads[entry.key]!,
                              onRetry: translating || _operatingCode != null
                                  ? null
                                  : () => _confirmDownload(entry.key),
                            ),
                          )
                        : Text(entry.value
                            ? l10n.statusDownloaded
                            : l10n.statusNotDownloaded),
                    trailing: entry.key == 'en' &&
                            ref.watch(translationPlatformProvider) ==
                                TranslationPlatform.ios
                        ? Text(l10n.bundledModel)
                        : _operatingCode == entry.key ||
                                downloads[entry.key]?.isActive == true ||
                                downloads[entry.key]?.phase ==
                                    ModelDownloadPhase.failed
                            ? null
                            : entry.value
                                ? TextButton(
                                    key: Key('delete_${entry.key}'),
                                    onPressed: translating ||
                                            _operatingCode != null
                                        ? null
                                        : () =>
                                            _operate(entry.key, remove: true),
                                    child: Text(l10n.deleteAction),
                                  )
                                : FilledButton.tonal(
                                    key: Key('download_${entry.key}'),
                                    onPressed:
                                        translating || _operatingCode != null
                                            ? null
                                            : () => _confirmDownload(entry.key),
                                    child: Text(l10n.downloadAction),
                                  ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
