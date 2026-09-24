import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:xiaoan_tsl/features/favorites/favorites_page.dart';
import 'package:xiaoan_tsl/features/language/language_page.dart';
import 'package:xiaoan_tsl/features/language/offline_models_page.dart';
import 'package:xiaoan_tsl/features/history/records_page.dart';
import 'package:xiaoan_tsl/features/settings/info_page.dart';
import 'package:xiaoan_tsl/features/settings/settings_page.dart';
import 'package:xiaoan_tsl/features/translate/translation_home_page.dart';

// 四个入口各保留独立导航栈，次级页面使用根导航。
final routerProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    initialLocation: '/translate',
    routes: [
      GoRoute(path: '/', redirect: (context, state) => '/translate'),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => Scaffold(
          body: shell,
          bottomNavigationBar: NavigationBar(
            selectedIndex: shell.currentIndex,
            onDestinationSelected: (index) => shell.goBranch(index),
            destinations: const [
              NavigationDestination(icon: Icon(Icons.translate), label: '翻译'),
              NavigationDestination(icon: Icon(Icons.history), label: '历史'),
              NavigationDestination(
                icon: Icon(Icons.star_outline),
                label: '收藏',
              ),
              NavigationDestination(
                icon: Icon(Icons.settings_outlined),
                label: '设置',
              ),
            ],
          ),
        ),
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
        builder: (context, state) => const InfoPage(kind: InfoKind.privacy),
      ),
      GoRoute(
        path: '/about',
        builder: (context, state) => const InfoPage(kind: InfoKind.about),
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      appBar: AppBar(title: const Text('页面不存在')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('找不到这个页面'),
            TextButton(
              onPressed: () => context.go('/translate'),
              child: const Text('返回翻译首页'),
            ),
          ],
        ),
      ),
    ),
  );
  ref.onDispose(router.dispose);
  return router;
});
