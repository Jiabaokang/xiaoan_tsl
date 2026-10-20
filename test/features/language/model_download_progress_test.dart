import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaoan_tsl/features/language/offline_models_page.dart';
import 'package:xiaoan_tsl/l10n/app_localizations.dart';
import 'package:xiaoan_tsl/services/translation/mlkit_model_service.dart';
import 'package:xiaoan_tsl/services/translation/model_download_status.dart';
import 'package:xiaoan_tsl/services/translation/model_service_provider.dart';

// 手动推进设备下载，页面本身仍使用真实确认、状态展示及共享控制器。
class _Models implements TranslationModelService, ModelDownloadEventSource {
  final events = StreamController<ModelDownloadStatus>.broadcast(sync: true);
  Completer<void> gate = Completer<void>();
  final downloaded = <String>{};
  final policies = <bool>[];

  @override
  Stream<ModelDownloadStatus> get downloadEvents => events.stream;
  @override
  Future<void> allowMobileData(String code) async {}
  @override
  Future<bool> isDownloaded(String code) async => downloaded.contains(code);
  @override
  Future<void> download(String code, {bool wifiOnly = true}) async {
    policies.add(wifiOnly);
    await gate.future;
    downloaded.add(code);
  }

  @override
  Future<void> delete(String code) async => downloaded.remove(code);
}

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('$brightness：确认可取消、等待网络无百分比、失败原因可见且可重试', (tester) async {
      final models = _Models();
      addTearDown(models.events.close);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [translationModelProvider.overrideWithValue(models)],
          child: MaterialApp(
            locale: const Locale('zh'),
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            theme: ThemeData(brightness: brightness),
            home: const OfflineModelsPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('download_zh')));
      await tester.pumpAndSettle();
      expect(find.text('下载简体中文离线语言包？'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(models.policies, isEmpty);

      await tester.tap(find.byKey(const Key('download_zh')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('仅 Wi-Fi 下载'));
      await tester.pump();
      expect(models.policies, [true]);
      models.events.add(
        const ModelDownloadStatus(
          code: 'zh',
          phase: ModelDownloadPhase.waitingWifi,
          canUseMobile: true,
        ),
      );
      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.text('等待 Wi-Fi 连接'), findsOneWidget);
      expect(find.textContaining('%'), findsNothing);
      expect(find.text('允许移动网络下载'), findsOneWidget);
      models.events.add(
        const ModelDownloadStatus(
          code: 'zh',
          phase: ModelDownloadPhase.downloading,
          progress: .42,
        ),
      );
      await tester.pump();
      expect(find.textContaining('42%'), findsOneWidget);
      models.gate.completeError(
        ModelDownloadException(
          ModelDownloadFailure.storage,
          'native storage error 101',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('设备存储空间不足'), findsOneWidget);
      await tester.tap(find.text('查看错误详情'));
      await tester.pumpAndSettle();
      expect(find.text('native storage error 101'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      models.gate = Completer<void>();
      await tester.tap(find.text('重试下载'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('允许移动网络下载'));
      await tester.pump();
      expect(models.policies, [true, false]);
      models.gate.complete();
      await tester.pumpAndSettle();
      expect(find.text('下载完成，可离线使用'), findsOneWidget);
      expect(find.byKey(const Key('delete_zh')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
