import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'history_store.dart';
import 'translation_home_page.dart';
import 'translation_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final directory = await getApplicationDocumentsDirectory();
  runApp(
    XiaoanApp(
      historyStore: HistoryStore(
        File('${directory.path}/translation_history.json'),
      ),
      translationService: DemoTranslationService(),
    ),
  );
}

// 应用入口，使用系统主题自动切换浅色与深色。
class XiaoanApp extends StatelessWidget {
  const XiaoanApp({
    super.key,
    required this.historyStore,
    required this.translationService,
  });

  final HistoryStore historyStore;
  final TranslationService translationService;

  @override
  Widget build(BuildContext context) {
    ThemeData theme(Brightness brightness) {
      final scheme = ColorScheme.fromSeed(
        seedColor: const Color(0xFF315F49),
        brightness: brightness,
      );
      return ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        scaffoldBackgroundColor: brightness == Brightness.light
            ? const Color(0xFFF7F8F5)
            : const Color(0xFF15211F),
      );
    }

    return MaterialApp(
      title: '小安翻译',
      debugShowCheckedModeBanner: false,
      theme: theme(Brightness.light),
      darkTheme: theme(Brightness.dark),
      home: TranslationHomePage(
        historyStore: historyStore,
        translationService: translationService,
      ),
    );
  }
}
