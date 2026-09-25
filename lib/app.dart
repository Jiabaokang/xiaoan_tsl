import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:xiaoan_tsl/core/router/app_router.dart';
import 'package:xiaoan_tsl/core/theme/app_theme.dart';
import 'package:xiaoan_tsl/features/translate/app_controller.dart';
import 'package:xiaoan_tsl/l10n/app_localizations.dart';

// 应用主题、多语言及声明式路由入口。
class XiaoanApp extends ConsumerWidget {
  const XiaoanApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(
      appControllerProvider.select((state) => state.themeMode),
    );
    final locale = ref.watch(
      appControllerProvider.select((state) => state.locale),
    );
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: '小安翻译',
      onGenerateTitle: (context) => context.l10n.appName,
      debugShowCheckedModeBanner: false,
      theme: appTheme(Brightness.light),
      darkTheme: appTheme(Brightness.dark),
      themeMode: themeMode,
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      localeListResolutionCallback: (locales, supportedLocales) {
        if (locales != null) {
          for (final userLocale in locales) {
            if (userLocale.languageCode == 'zh') {
              return const Locale('zh');
            }
            if (userLocale.languageCode == 'en') {
              return const Locale('en');
            }
          }
        }
        return const Locale('zh');
      },
      routerConfig: router,
    );
  }
}
