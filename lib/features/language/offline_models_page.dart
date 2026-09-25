import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:xiaoan_tsl/features/language/app_languages.dart';
import 'package:xiaoan_tsl/features/translate/app_controller.dart';
import 'package:xiaoan_tsl/l10n/app_localizations.dart';
import 'package:xiaoan_tsl/services/translation/model_service_provider.dart';
import 'package:xiaoan_tsl/services/translation/translate_language_code.dart';

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
  String? _failedDownloadCode;
  String? _error;

  @override
  void initState() {
    super.initState();
    _status = _loadStatus();
  }

  Future<Map<String, bool>> _loadStatus() async {
    final models = ref.read(translationModelProvider);
    final status = <String, bool>{};
    for (final code in appLanguages.keys) {
      if (code != 'auto' && translateLanguageForCode(code) != null) {
        status[code] = await models.isDownloaded(code);
      }
    }
    return status;
  }

  void _refresh() => setState(() => _status = _loadStatus());

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
      } else {
        await models.download(code, wifiOnly: wifiOnly);
      }
      if (!mounted) return;
      setState(() {
        _operatingCode = null;
        _failedDownloadCode = null;
        _status = _loadStatus();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _operatingCode = null;
        _failedDownloadCode = remove ? null : code;
        _error = remove ? l10n.deleteModelFailed : l10n.downloadModelFailed;
      });
    }
  }

  // 蜂窝网络下载需要用户明确确认，且只对本次操作生效。
  Future<void> _downloadWithMobileData(String code) async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.mobileDownloadDialogTitle),
        content: Text(l10n.mobileDownloadDialogContent),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(l10n.continueDownload),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _operate(code, remove: false, wifiOnly: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final translating = ref.watch(
      appControllerProvider.select((state) => state.phase.isBusy),
    );
    final l10n = context.l10n;

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
                  if (_failedDownloadCode != null)
                    TextButton(
                      onPressed: () =>
                          _downloadWithMobileData(_failedDownloadCode!),
                      child: Text(l10n.allowMobileDownload),
                    ),
                ],
                for (final entry in status.entries)
                  ListTile(
                    key: Key('model_${entry.key}'),
                    title: Text(l10n.languageName(entry.key)),
                    subtitle: Text(
                      entry.value
                          ? l10n.statusDownloaded
                          : l10n.statusNotDownloaded,
                    ),
                    trailing: _operatingCode == entry.key
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : entry.value
                            ? TextButton(
                                key: Key('delete_${entry.key}'),
                                onPressed: translating || _operatingCode != null
                                    ? null
                                    : () => _operate(entry.key, remove: true),
                                child: Text(l10n.deleteAction),
                              )
                            : FilledButton.tonal(
                                key: Key('download_${entry.key}'),
                                onPressed: translating || _operatingCode != null
                                    ? null
                                    : () => _operate(entry.key, remove: false),
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
