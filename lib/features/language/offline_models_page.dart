import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:xiaoan_tsl/features/translate/app_controller.dart';
import 'package:xiaoan_tsl/services/translation/model_service_provider.dart';
import 'package:xiaoan_tsl/services/translation/translate_language_code.dart';

import 'app_languages.dart';

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
        _error = remove ? '删除语言模型失败，请重试' : '下载语言模型失败，请检查网络后重试';
      });
    }
  }

  // 蜂窝网络下载需要用户明确确认，且只对本次操作生效。
  Future<void> _downloadWithMobileData(String code) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('使用移动网络下载模型？'),
        content: const Text('语言模型可能占用较多流量。仅本次下载允许使用移动网络。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('继续下载'),
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
    return Scaffold(
      appBar: AppBar(title: const Text('离线语言包')),
      body: SafeArea(
        child: FutureBuilder<Map<String, bool>>(
          future: _status,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('无法读取离线模型状态'),
                    TextButton(onPressed: _refresh, child: const Text('重试查询')),
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
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: Text('模型状态来自设备。首次下载默认仅使用 Wi-Fi，下载后可离线翻译。'),
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
                      child: const Text('允许移动网络下载'),
                    ),
                ],
                for (final entry in status.entries)
                  ListTile(
                    key: Key('model_${entry.key}'),
                    title: Text(appLanguages[entry.key] ?? entry.key),
                    subtitle: Text(entry.value ? '已下载' : '未下载'),
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
                            child: const Text('删除'),
                          )
                        : FilledButton.tonal(
                            key: Key('download_${entry.key}'),
                            onPressed: translating || _operatingCode != null
                                ? null
                                : () => _operate(entry.key, remove: false),
                            child: const Text('下载'),
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
