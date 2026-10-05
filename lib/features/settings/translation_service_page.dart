import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:xiaoan_tsl/core/network/dio_provider.dart';
import 'package:xiaoan_tsl/features/translate/app_controller.dart';
import 'package:xiaoan_tsl/l10n/app_localizations.dart';
import 'package:xiaoan_tsl/services/translation/baidu_translation_service.dart';
import 'package:xiaoan_tsl/services/translation/translation_service_provider.dart';
import 'package:xiaoan_tsl/services/translation/translation_settings.dart';

// 连接测试优先使用页面输入值，未输入时回退已保存凭据。
class _OverlayCredentials implements SecureCredentialStore {
  _OverlayCredentials(this.base, {this.appId, this.secret});

  final SecureCredentialStore base;
  final String? appId;
  final String? secret;

  @override
  Future<String?> readBaiduAppId() async {
    final override = appId;
    if (override != null && override.isNotEmpty) return override;
    return base.readBaiduAppId();
  }

  @override
  Future<String?> readBaiduSecret() async {
    final override = secret;
    if (override != null && override.isNotEmpty) return override;
    return base.readBaiduSecret();
  }

  @override
  Future<bool> hasBaiduCredentials() async {
    if ((appId?.isNotEmpty ?? false) && (secret?.isNotEmpty ?? false)) {
      return true;
    }
    return base.hasBaiduCredentials();
  }

  @override
  Future<void> writeBaiduCredentials({
    required String appId,
    required String secret,
  }) => base.writeBaiduCredentials(appId: appId, secret: secret);

  @override
  Future<void> deleteBaiduCredentials() => base.deleteBaiduCredentials();
}

// 翻译引擎选择、凭据管理与连接测试页面。
class TranslationServicePage extends ConsumerStatefulWidget {
  const TranslationServicePage({super.key});

  @override
  ConsumerState<TranslationServicePage> createState() =>
      _TranslationServicePageState();
}

// 管理凭据输入与异步操作；安全存储失败时保留输入和已知配置状态。
class _TranslationServicePageState
    extends ConsumerState<TranslationServicePage> {
  final _appId = TextEditingController();
  final _secret = TextEditingController();
  bool _secretVisible = false;
  bool _saving = false;
  bool _hasCredentials = false;
  bool _testing = false;
  String? _testError;
  String? _statusMessage;

  @override
  void initState() {
    super.initState();
    _loadState();
  }

  @override
  void dispose() {
    _appId.dispose();
    _secret.dispose();
    super.dispose();
  }

  Future<void> _loadState() async {
    try {
      final has = await ref
          .read(secureCredentialStoreProvider)
          .hasBaiduCredentials();
      if (!mounted) return;
      setState(() => _hasCredentials = has);
    } catch (_) {
      if (!mounted) return;
      setState(() => _testError = context.l10n.credentialStorageFailed);
    }
  }

  void _notice(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  // 安全存储错误不能逃逸到事件循环；失败保留输入并恢复保存按钮。
  Future<void> _saveCredentials() async {
    final appId = _appId.text.trim();
    final secret = _secret.text.trim();
    if (appId.isEmpty || secret.isEmpty) {
      _notice(context.l10n.credentialsSaveFailed);
      return;
    }
    setState(() {
      _saving = true;
      _statusMessage = null;
      _testError = null;
    });
    try {
      await ref
          .read(secureCredentialStoreProvider)
          .writeBaiduCredentials(appId: appId, secret: secret);
      if (!mounted) return;
      setState(() {
        _hasCredentials = true;
        _statusMessage = context.l10n.credentialsSaved;
        _appId.clear();
        _secret.clear();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _testError = context.l10n.credentialStorageFailed);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _deleteCredentials() async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.deleteCredentialsConfirmTitle),
        content: Text(l10n.deleteCredentialsConfirmContent),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(l10n.deleteCredentials),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _saving = true;
      _statusMessage = null;
      _testError = null;
    });
    try {
      await ref.read(secureCredentialStoreProvider).deleteBaiduCredentials();
      if (!mounted) return;
      setState(() {
        _hasCredentials = false;
        _statusMessage = l10n.credentialsDeleted;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _testError = l10n.credentialStorageFailed);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // 只提交固定短句；成功才显示通过，失败保留输入并给出恢复方式。
  Future<void> _testConnection() async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.testConnectionDialogTitle),
        content: Text(l10n.testConnectionDialogContent),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(l10n.testConnection),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _testing = true;
      _testError = null;
      _statusMessage = null;
    });
    final service = BaiduTranslationService(
      credentials: _OverlayCredentials(
        ref.read(secureCredentialStoreProvider),
        appId: _appId.text.trim(),
        secret: _secret.text.trim(),
      ),
      dio: ref.read(dioProvider),
    );
    try {
      await service.translate(
        text: 'Hello, world!',
        sourceLanguage: 'en',
        targetLanguage: 'zh',
      );
      if (!mounted) return;
      setState(() {
        _testing = false;
        _statusMessage = l10n.testPassed;
      });
    } on BaiduTranslationException catch (error) {
      if (!mounted) return;
      setState(() {
        _testing = false;
        _testError = error.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _testing = false;
        _testError = '${l10n.testFailedPrefix}${l10n.errorTranslation}';
      });
    }
  }

  List<(String, bool)> _services(TranslationPlatform platform) =>
      switch (platform) {
        TranslationPlatform.macOS => [('baidu', true), ('apple', false)],
        _ => [('mlkit', true), ('baidu', true), ('apple', false)],
      };

  String _engineLabel(AppLocalizations l10n, String engine) => switch (engine) {
    'mlkit' => l10n.engineMlkit,
    'baidu' => l10n.engineBaidu,
    'apple' => l10n.engineApple,
    _ => l10n.engineUnknownLabel,
  };

  IconData _engineIcon(String engine) => switch (engine) {
    'mlkit' => Icons.offline_bolt_outlined,
    'baidu' => Icons.cloud_outlined,
    'apple' => Icons.apple,
    _ => Icons.settings_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final platform = ref.watch(translationPlatformProvider);
    final saved = ref.watch(translationEngineProvider);
    final selected = saved.isEmpty ? defaultEngineFor(platform) : saved;
    final controller = ref.read(appControllerProvider.notifier);
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final baiduAvailable = _services(platform).any((e) => e.$1 == 'baidu');

    return Scaffold(
      appBar: AppBar(title: Text(l10n.translationServiceTitle)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
        children: [
          Card(
            child: Column(
              children: [
                RadioGroup<String>(
                  groupValue: selected,
                  onChanged: (value) {
                    if (value != null) controller.setTranslationEngine(value);
                  },
                  child: Column(
                    children: [
                      for (final entry in _services(platform))
                        RadioListTile<String>(
                          value: entry.$1,
                          enabled: entry.$2,
                          title: Text(_engineLabel(l10n, entry.$1)),
                          secondary: Icon(_engineIcon(entry.$1)),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (baiduAvailable) ...[
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.baiduCredentialsTitle,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      key: const Key('baiduAppIdField'),
                      controller: _appId,
                      decoration: InputDecoration(
                        labelText: l10n.appIdLabel,
                        hintText: _hasCredentials
                            ? l10n.secretConfiguredHint
                            : null,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      key: const Key('baiduSecretField'),
                      controller: _secret,
                      obscureText: !_secretVisible,
                      decoration: InputDecoration(
                        labelText: l10n.secretLabel,
                        hintText: _hasCredentials
                            ? l10n.secretConfiguredHint
                            : null,
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          tooltip: _secretVisible
                              ? l10n.hideSecret
                              : l10n.showSecret,
                          icon: Icon(
                            _secretVisible
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                          ),
                          onPressed: () =>
                              setState(() => _secretVisible = !_secretVisible),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        FilledButton.tonalIcon(
                          onPressed: _saving ? null : _saveCredentials,
                          icon: _saving
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.lock_outline),
                          label: Text(l10n.saveCredentials),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton(
                          onPressed: _hasCredentials && !_saving
                              ? _deleteCredentials
                              : null,
                          child: Text(l10n.deleteCredentials),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (_statusMessage != null)
                      Text(
                        _statusMessage!,
                        key: const Key('credentialsStatus'),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    if (_testError != null)
                      Text(
                        _testError!,
                        key: const Key('testError'),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      key: const Key('testConnectionButton'),
                      onPressed: _testing ? null : _testConnection,
                      icon: _testing
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.network_check),
                      label: Text(l10n.testConnection),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: ListTile(
                leading: const Icon(Icons.info_outline),
                title: Text(
                  l10n.onlineDataNotice,
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
