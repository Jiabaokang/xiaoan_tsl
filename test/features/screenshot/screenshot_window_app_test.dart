import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaoan_tsl/features/screenshot/screenshot_controller.dart';
import 'package:xiaoan_tsl/features/screenshot/screenshot_window_app.dart';

void main() {
  final snapshot = <String, Object?>{
    'stage': 'done',
    'failure': 'none',
    'recognizedText': 'Hello world',
    'translatedText': '你好，世界！',
    'themeMode': 'dark',
    'locale': 'zh',
  };

  for (final brightness in Brightness.values) {
    testWidgets('独立窗口接收译文和${brightness.name}主题，操作转发而不访问数据库', (tester) async {
      final calls = <String>[];
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(ScreenshotWindowController.channel, (
        call,
      ) async {
        calls.add(call.method);
        if (call.method == 'ready') {
          return {
            ...snapshot,
            'themeMode': brightness == Brightness.dark ? 'dark' : 'light',
          };
        }
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(
          ScreenshotWindowController.channel,
          null,
        ),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            screenshotControllerProvider.overrideWith(
              ScreenshotWindowController.new,
            ),
          ],
          child: const ScreenshotWindowApp(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('你好，世界！'), findsOneWidget);
      expect(
        Theme.of(tester.element(find.byType(Scaffold))).brightness,
        brightness,
      );
      await tester.tap(find.byKey(const Key('screenshotReshootButton')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('screenshotCloseButton')));
      await tester.pump();
      expect(calls, ['ready', 'reshoot', 'dismiss']);
      // 操作等待主引擎的新快照，展示引擎不自行翻译或保存历史。
      expect(find.text('你好，世界！'), findsOneWidget);
      const codec = StandardMethodCodec();
      await messenger.handlePlatformMessage(
        ScreenshotWindowController.channel.name,
        codec.encodeMethodCall(
          MethodCall('update', {
            ...snapshot,
            'stage': 'idle',
            'translatedText': null,
          }),
        ),
        (_) {},
      );
      await tester.pumpAndSettle();
      expect(find.text('你好，世界！'), findsNothing);
    });
  }

  testWidgets('英文结果窗口的配置入口转发到主窗口', (tester) async {
    final calls = <String>[];
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(ScreenshotWindowController.channel, (
      call,
    ) async {
      calls.add(call.method);
      if (call.method == 'ready') {
        return {
          ...snapshot,
          'stage': 'failed',
          'failure': 'missingCredentials',
          'locale': 'en',
        };
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(
        ScreenshotWindowController.channel,
        null,
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          screenshotControllerProvider.overrideWith(
            ScreenshotWindowController.new,
          ),
        ],
        child: const ScreenshotWindowApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Screenshot Translate'), findsOneWidget);
    await tester.tap(find.byKey(const Key('screenshotGoConfigButton')));
    await tester.pump();
    expect(calls, ['ready', 'configure']);
  });

  testWidgets('确认、重试和 Esc 由主引擎处理，窗口跟随新快照更新', (tester) async {
    final calls = <String>[];
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(ScreenshotWindowController.channel, (
      call,
    ) async {
      calls.add(call.method);
      if (call.method == 'ready') {
        return {...snapshot, 'stage': 'needsConfirm', 'confirmRequired': true};
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(
        ScreenshotWindowController.channel,
        null,
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          screenshotControllerProvider.overrideWith(
            ScreenshotWindowController.new,
          ),
        ],
        child: const ScreenshotWindowApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('screenshotConfirmTranslate')));
    await tester.pump();
    await messenger.handlePlatformMessage(
      ScreenshotWindowController.channel.name,
      const StandardMethodCodec().encodeMethodCall(
        MethodCall('update', {
          ...snapshot,
          'stage': 'failed',
          'failure': 'timeout',
        }),
      ),
      (_) {},
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('screenshotRetryButton')));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(calls, ['ready', 'confirm', 'retry', 'dismiss']);
  });
}
