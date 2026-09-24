import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:xiaoan_tsl/features/translate/app_controller.dart';
import 'package:xiaoan_tsl/features/language/app_languages.dart';

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
    final selected = switch (mode) {
      'target' => appState.targetLanguage,
      'default-target' => appState.defaultTargetLanguage,
      _ => appState.sourceLanguage,
    };
    final title = switch (mode) {
      'target' => '选择译文语言',
      'default-target' => '默认目标语言',
      _ => '选择原文语言',
    };
    final languages = appLanguages.entries.where(
      (entry) =>
          (mode == 'source' || entry.key != 'auto') &&
          (entry.value.toLowerCase().contains(_query.toLowerCase()) ||
              entry.key.contains(_query.toLowerCase())),
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
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: '搜索语言',
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) => setState(() => _query = value.trim()),
              ),
            ),
            Expanded(
              child: ListView(
                children: [
                  if (languages.isEmpty) const ListTile(title: Text('没有找到语言')),
                  for (final language in languages)
                    ListTile(
                      title: Text(language.value),
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
