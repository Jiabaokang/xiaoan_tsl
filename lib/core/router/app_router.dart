import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import 'package:xiaoan_tsl/features/favorites/favorites_page.dart';
import 'package:xiaoan_tsl/features/language/language_page.dart';
import 'package:xiaoan_tsl/features/language/offline_models_page.dart';
import 'package:xiaoan_tsl/features/history/records_page.dart';
import 'package:xiaoan_tsl/features/settings/about_page.dart';
import 'package:xiaoan_tsl/features/settings/open_source_licenses_page.dart';
import 'package:xiaoan_tsl/features/settings/privacy_policy_page.dart';
import 'package:xiaoan_tsl/features/settings/settings_page.dart';
import 'package:xiaoan_tsl/features/translate/translation_home_page.dart';
import 'package:xiaoan_tsl/l10n/app_localizations.dart';

// 四个入口各保留独立导航栈，次级页面使用根导航。
final routerProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    initialLocation: '/translate',
    routes: [
      GoRoute(path: '/', redirect: (context, state) => '/translate'),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) {
          final theme = Theme.of(context);
          final barColor = theme.colorScheme.surfaceContainer;
          return AnnotatedRegion<SystemUiOverlayStyle>(
            value: SystemUiOverlayStyle(
              systemNavigationBarColor: barColor,
              systemNavigationBarIconBrightness:
                  theme.brightness == Brightness.light
                      ? Brightness.dark
                      : Brightness.light,
              systemNavigationBarContrastEnforced: false,
            ),
            child: Scaffold(
              body: shell,
              bottomNavigationBar: NavigationBar(
                backgroundColor: barColor,
                selectedIndex: shell.currentIndex,
                onDestinationSelected: (index) => shell.goBranch(index),
                destinations: [
                  NavigationDestination(
                    icon: const Icon(Icons.translate),
                    label: context.l10n.navTranslate,
                  ),
                  NavigationDestination(
                    icon: const Icon(Icons.history),
                    label: context.l10n.navHistory,
                  ),
                  NavigationDestination(
                    icon: const Icon(Icons.star_outline),
                    label: context.l10n.navFavorites,
                  ),
                  NavigationDestination(
                    icon: const Icon(Icons.settings_outlined),
                    label: context.l10n.navSettings,
                  ),
                ],
              ),
            ),
          );
        },
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/translate',
                builder: (context, state) => TranslationHomePage(
                  recordId: state.uri.queryParameters['record'],
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/history',
                builder: (context, state) =>
                    const RecordsPage(favoritesOnly: false),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/favorites',
                builder: (context, state) => const FavoritesPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/settings',
                builder: (context, state) => const SettingsPage(),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/languages',
        builder: (context, state) =>
            LanguagePage(mode: state.uri.queryParameters['mode'] ?? 'source'),
      ),
      GoRoute(
        path: '/offline-models',
        builder: (context, state) => const OfflineModelsPage(),
      ),
      GoRoute(
        path: '/privacy',
        builder: (context, state) => const PrivacyPolicyPage(),
      ),
      GoRoute(
        path: '/about',
        builder: (context, state) => const AboutPage(),
      ),
      GoRoute(
        path: '/about/dependencies',
        builder: (context, state) => const OpenSourceLicensesPage(),
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      appBar: AppBar(title: Text(context.l10n.pageNotFoundTitle)),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(context.l10n.pageNotFound),
            TextButton(
              onPressed: () => context.go('/translate'),
              child: Text(context.l10n.returnToHome),
            ),
          ],
        ),
      ),
    ),
  );
  ref.onDispose(router.dispose);
  return router;
});
