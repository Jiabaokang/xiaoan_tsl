import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:xiaoan_tsl/core/router/app_router.dart';
import 'package:xiaoan_tsl/core/theme/app_theme.dart';
import 'package:xiaoan_tsl/features/translate/app_controller.dart';

// 应用主题及声明式路由入口。
class XiaoanApp extends ConsumerWidget {
  const XiaoanApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(
      appControllerProvider.select((state) => state.themeMode),
    );
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: '小安翻译',
      debugShowCheckedModeBanner: false,
      theme: appTheme(Brightness.light),
      darkTheme: appTheme(Brightness.dark),
      themeMode: themeMode,
      routerConfig: router,
    );
  }
}
