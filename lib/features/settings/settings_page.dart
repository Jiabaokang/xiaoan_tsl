import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:xiaoan_tsl/core/database/database_provider.dart';
import 'package:xiaoan_tsl/features/translate/app_controller.dart';
import 'package:xiaoan_tsl/services/desktop/macos_desktop_service.dart';
import 'package:xiaoan_tsl/services/translation/translation_settings.dart';
import 'package:xiaoan_tsl/l10n/app_localizations.dart';
import 'package:xiaoan_tsl/services/translation/translation_service_provider.dart';

// 本地偏好、应用信息及国际化语言设置的第四个底部入口。
class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

// 管理本机全局截图快捷键，其余偏好继续由应用控制器负责。
class _SettingsPageState extends ConsumerState<SettingsPage> {
  // null 表示沿用默认快捷键，空字符串表示用户主动关闭。
  String? _shortcut;

  @override
  void initState() {
    super.initState();
    _loadShortcut();
  }

  // 读取已保存的快捷键；未设置时沿用启动时注册的默认组合。
  Future<void> _loadShortcut() async {
    final shortcut = await ref
        .read(localStoreProvider)
        .getSetting(TranslationSettingKeys.screenshotShortcut);
    if (mounted) setState(() => _shortcut = shortcut);
  }

  void _notice(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  // macOS 快捷键选择：先注册新键成功，再保存配置；冲突保留旧注册与旧设置。
  Future<void> _changeShortcut() async {
    final l10n = context.l10n;
    final desktop = ref.read(macosDesktopServiceProvider);
    final store = ref.read(localStoreProvider);
    final options = <String, String>{
      'Control+Option+T': l10n.shortcutOptionControlOptionT,
      'Control+Shift+T': l10n.shortcutOptionControlShiftT,
      'Command+Shift+T': l10n.shortcutOptionCommandShiftT,
      'Command+Option+T': l10n.shortcutOptionCommandOptionT,
    };
    final selected = await showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text(l10n.shortcutDialogTitle),
        children: [
          for (final entry in options.entries)
            ListTile(
              key: Key('shortcutOption_${entry.key}'),
              leading: const Icon(Icons.keyboard),
              title: Text(entry.value),
              onTap: () => Navigator.pop(dialogContext, entry.key),
            ),
          ListTile(
            key: const Key('shortcutOption_disabled'),
            leading: const Icon(Icons.block),
            title: Text(l10n.shortcutDisabled),
            onTap: () => Navigator.pop(dialogContext, ''),
          ),
        ],
      ),
    );
    if (selected == null || selected == (_shortcut ?? 'Control+Option+T')) {
      return;
    }
    try {
      await desktop.updateShortcut(selected);
    } on MacosDesktopShortcutConflictException {
      _notice(l10n.shortcutConflictNotice);
      return;
    } catch (_) {
      _notice(l10n.shortcutConflictNotice);
      return;
    }
    try {
      await store.setSetting(
        TranslationSettingKeys.screenshotShortcut,
        selected,
      );
    } catch (_) {
      try {
        await desktop.updateShortcut(_shortcut ?? 'Control+Option+T');
      } catch (_) {
        // 保存失败时尽力恢复原注册；重启仍会读取磁盘中的旧配置。
      }
      _notice(l10n.shortcutSaveFailed);
      return;
    }
    if (!mounted) return;
    setState(() => _shortcut = selected.isEmpty ? '' : selected);
    _notice(l10n.shortcutSaved);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appControllerProvider);
    final controller = ref.read(appControllerProvider.notifier);
    final l10n = context.l10n;
    final platform = ref.watch(translationPlatformProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsTitle)),
      body: ListView(
        // 滚动留白叠加系统边衬，避免末项和横屏内容被系统区域遮挡。
        padding:
            const EdgeInsets.only(bottom: 48) + MediaQuery.paddingOf(context),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 4),
            child: Text(l10n.translationPreferencesSection),
          ),
          ListTile(
            leading: const Icon(Icons.translate),
            title: Text(l10n.defaultTargetLanguage),
            subtitle: Text(l10n.languageName(state.defaultTargetLanguage)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/languages?mode=default-target'),
          ),
          ListTile(
            leading: const Icon(Icons.tune),
            title: Text(l10n.translationServiceLabel),
            subtitle: Text(l10n.translationServiceSubtitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/translation-service'),
          ),
          if (platform == TranslationPlatform.macOS)
            ListTile(
              key: const Key('screenshotShortcutTile'),
              leading: const Icon(Icons.keyboard_command_key),
              title: Text(l10n.screenshotShortcutLabel),
              subtitle: Text(
                '${_shortcut == null ? l10n.shortcutOptionControlOptionT : (_shortcut!.isEmpty ? l10n.shortcutDisabled : _shortcut!.replaceAll('+', ' + '))}\n${l10n.screenshotShortcutInfo}',
              ),
              isThreeLine: true,
              trailing: const Icon(Icons.chevron_right),
              onTap: _changeShortcut,
            ),
          ListTile(
            leading: const Icon(Icons.dark_mode_outlined),
            title: Text(l10n.themeModeLabel),
            subtitle: Text(switch (state.themeMode) {
              ThemeMode.system => l10n.themeModeSystem,
              ThemeMode.light => l10n.themeModeLight,
              ThemeMode.dark => l10n.themeModeDark,
            }),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              final selected = await showDialog<ThemeMode>(
                context: context,
                builder: (dialogContext) => SimpleDialog(
                  title: Text(l10n.themeModeLabel),
                  children: [
                    SimpleDialogOption(
                      onPressed: () =>
                          Navigator.pop(dialogContext, ThemeMode.system),
                      child: Row(
                        children: [
                          Expanded(child: Text(l10n.themeModeSystem)),
                          if (state.themeMode == ThemeMode.system)
                            const Icon(Icons.check, size: 20),
                        ],
                      ),
                    ),
                    SimpleDialogOption(
                      onPressed: () =>
                          Navigator.pop(dialogContext, ThemeMode.light),
                      child: Row(
                        children: [
                          Expanded(child: Text(l10n.themeModeLight)),
                          if (state.themeMode == ThemeMode.light)
                            const Icon(Icons.check, size: 20),
                        ],
                      ),
                    ),
                    SimpleDialogOption(
                      onPressed: () =>
                          Navigator.pop(dialogContext, ThemeMode.dark),
                      child: Row(
                        children: [
                          Expanded(child: Text(l10n.themeModeDark)),
                          if (state.themeMode == ThemeMode.dark)
                            const Icon(Icons.check, size: 20),
                        ],
                      ),
                    ),
                  ],
                ),
              );
              if (selected != null) {
                await controller.setThemeMode(selected);
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.language_outlined),
            title: Text(l10n.appLanguageLabel),
            subtitle: Text(switch (state.localeMode) {
              'zh' => l10n.languageZh,
              'en' => l10n.languageEn,
              _ => l10n.languageSystem,
            }),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              final selected = await showDialog<String>(
                context: context,
                builder: (dialogContext) => SimpleDialog(
                  title: Text(l10n.appLanguageLabel),
                  children: [
                    SimpleDialogOption(
                      onPressed: () => Navigator.pop(dialogContext, 'system'),
                      child: Row(
                        children: [
                          Expanded(child: Text(l10n.languageSystem)),
                          if (state.localeMode == 'system')
                            const Icon(Icons.check, size: 20),
                        ],
                      ),
                    ),
                    SimpleDialogOption(
                      onPressed: () => Navigator.pop(dialogContext, 'zh'),
                      child: Row(
                        children: [
                          Expanded(child: Text(l10n.languageZh)),
                          if (state.localeMode == 'zh')
                            const Icon(Icons.check, size: 20),
                        ],
                      ),
                    ),
                    SimpleDialogOption(
                      onPressed: () => Navigator.pop(dialogContext, 'en'),
                      child: Row(
                        children: [
                          Expanded(child: Text(l10n.languageEn)),
                          if (state.localeMode == 'en')
                            const Icon(Icons.check, size: 20),
                        ],
                      ),
                    ),
                  ],
                ),
              );
              if (selected != null) {
                await controller.setLocaleMode(selected);
              }
            },
          ),
          if (platform != TranslationPlatform.macOS)
            ListTile(
              leading: const Icon(Icons.download_outlined),
              title: Text(l10n.offlineModelsLabel),
              subtitle: Text(l10n.offlineModelsSubtitle),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/offline-models'),
            ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: Text(l10n.clearHistoryLabel),
            onTap: state.records.isEmpty
                ? null
                : () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (dialogContext) => AlertDialog(
                        title: Text(l10n.clearHistoryDialogTitle),
                        content: Text(l10n.clearHistoryDialogContent),
                        actions: [
                          TextButton(
                            onPressed: () => dialogContext.pop(false),
                            child: Text(l10n.cancel),
                          ),
                          TextButton(
                            onPressed: () => dialogContext.pop(true),
                            child: Text(l10n.clearHistoryConfirm),
                          ),
                        ],
                      ),
                    );
                    if (confirmed == true) await controller.clearHistory();
                  },
          ),
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: Text(l10n.privacyPolicyLabel),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/privacy'),
          ),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: Text(l10n.aboutAppLabel),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/about'),
          ),
        ],
      ),
    );
  }
}
