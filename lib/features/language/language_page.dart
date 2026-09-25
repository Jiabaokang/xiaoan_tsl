import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:xiaoan_tsl/features/language/app_languages.dart';
import 'package:xiaoan_tsl/features/translate/app_controller.dart';
import 'package:xiaoan_tsl/l10n/app_localizations.dart';

// 原文、译文和默认译文共用的可搜索语言选择页。
class LanguagePage extends ConsumerStatefulWidget {
  const LanguagePage({super.key, required this.mode});

  final String mode;

  @override
  ConsumerState<LanguagePage> createState() => _LanguagePageState();
}

// 本地搜索词只影响当前语言页。
class _LanguagePageState extends ConsumerState<LanguagePage> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final mode =
        const {'source', 'target', 'default-target'}.contains(widget.mode)
            ? widget.mode
            : 'source';
    final appState = ref.watch(appControllerProvider);
    final l10n = context.l10n;
    final reversed = appState.sourceLanguage != 'auto' &&
        appState.detectedLanguage == appState.targetLanguage;
    final selected = switch (mode) {
      'target' => appState.targetLanguage,
      'default-target' => appState.defaultTargetLanguage,
      _ => appState.sourceLanguage,
    };
    final title = switch (mode) {
      'target' =>
        reversed ? l10n.selectSourceLanguage : l10n.selectTargetLanguage,
      'default-target' => l10n.defaultTargetLanguage,
      _ => reversed ? l10n.selectTargetLanguage : l10n.selectSourceLanguage,
    };
    final languages = appLanguages.entries.where(
      (entry) {
        if (entry.key == 'auto') return false;
        final localizedName = l10n.languageName(entry.key).toLowerCase();
        final rawName = entry.value.toLowerCase();
        final code = entry.key.toLowerCase();
        final q = _query.toLowerCase();
        return localizedName.contains(q) ||
            rawName.contains(q) ||
            code.contains(q);
      },
    );

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: TextField(
                autofocus: false,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: l10n.searchLanguageHint,
                  border: const OutlineInputBorder(),
                ),
                onChanged: (value) => setState(() => _query = value.trim()),
              ),
            ),
            Expanded(
              child: ListView(
                children: [
                  if (languages.isEmpty)
                    ListTile(title: Text(l10n.noLanguageFound)),
                  for (final language in languages)
                    ListTile(
                      title: Text(l10n.languageName(language.key)),
                      trailing: selected == language.key
                          ? const Icon(Icons.check)
                          : null,
                      onTap: () async {
                        final controller = ref.read(
                          appControllerProvider.notifier,
                        );
                        if (mode == 'source') {
                          controller.setSourceLanguage(language.key);
                        } else if (mode == 'target') {
                          controller.setTargetLanguage(language.key);
                        } else {
                          await controller.setDefaultTargetLanguage(
                            language.key,
                          );
                        }
                        if (context.mounted) context.pop();
                      },
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
