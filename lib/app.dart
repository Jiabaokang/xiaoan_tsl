import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:xiaoan_tsl/core/router/app_router.dart';
import 'package:xiaoan_tsl/core/theme/app_theme.dart';
import 'package:xiaoan_tsl/features/screenshot/screenshot_controller.dart';
import 'package:xiaoan_tsl/features/translate/app_controller.dart';
import 'package:xiaoan_tsl/l10n/app_localizations.dart';
import 'package:xiaoan_tsl/services/desktop/macos_desktop_service.dart';

// 桌面事件桥：全局快捷键与菜单动作只通知 Dart，这里负责启动截图与导航。
class DesktopEventBridge extends ConsumerStatefulWidget {
  const DesktopEventBridge({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<DesktopEventBridge> createState() => _DesktopEventBridgeState();
}

class _DesktopEventBridgeState extends ConsumerState<DesktopEventBridge> {
  StreamSubscription<MacosDesktopEvent>? _subscription;

  @override
  void initState() {
    super.initState();
    // 非 macOS 的事件流为空，订阅不会有副作用。
    _subscription =
        ref.read(macosDesktopServiceProvider).events.listen(_handleEvent);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  void _handleEvent(MacosDesktopEvent event) {
    switch (event) {
      case MacosDesktopEvent.screenshotHotkey:
        ref.read(screenshotControllerProvider.notifier).startCapture();
        ref.read(routerProvider).push('/screenshot-result');
      case MacosDesktopEvent.openSettings:
        ref.read(routerProvider).push('/settings');
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

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

    return DesktopEventBridge(
      child: MaterialApp.router(
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
      ),
    );
  }
}
