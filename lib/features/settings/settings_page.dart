import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:xiaoan_tsl/features/translate/app_controller.dart';
import 'package:xiaoan_tsl/l10n/app_localizations.dart';

// 本地偏好、应用信息及国际化语言设置的第四个底部入口。
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appControllerProvider);
    final controller = ref.read(appControllerProvider.notifier);
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsTitle)),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 48),
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
            leading: const Icon(Icons.dark_mode_outlined),
            title: Text(l10n.themeModeLabel),
            subtitle: Text(
              switch (state.themeMode) {
                ThemeMode.system => l10n.themeModeSystem,
                ThemeMode.light => l10n.themeModeLight,
                ThemeMode.dark => l10n.themeModeDark,
              },
            ),
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
            subtitle: Text(
              switch (state.localeMode) {
                'zh' => l10n.languageZh,
                'en' => l10n.languageEn,
                _ => l10n.languageSystem,
              },
            ),
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
