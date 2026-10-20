import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:xiaoan_tsl/core/theme/app_theme.dart';
import 'package:xiaoan_tsl/l10n/app_localizations.dart';

import 'screenshot_controller.dart';
import 'screenshot_result_page.dart';

// 结果窗口仅展示主引擎发送的状态；所有操作回到主引擎，避免双写历史与重复请求。
class ScreenshotWindowController extends ScreenshotController {
  // 仅在 macOS 独立结果入口中使用，原生桥将操作转发至主引擎。
  static const channel = MethodChannel('xiaoan_tsl/screenshot_window');

  @override
  ScreenshotState build() => ScreenshotState.idle;

  // 快照替换整个状态，关闭时同步清除 PNG，不能沿用旧会话字段。
  void update(Map<Object?, Object?> snapshot) {
    state = ScreenshotState(
      stage: ScreenshotStage.values.byName(snapshot['stage'] as String),
      failure: ScreenshotFailure.values.byName(snapshot['failure'] as String),
      pngBytes: snapshot['png'] as Uint8List?,
      recognizedText: snapshot['recognizedText'] as String?,
      translatedText: snapshot['translatedText'] as String?,
      confirmRequired: snapshot['confirmRequired'] as bool? ?? false,
      historySaveFailed: snapshot['historySaveFailed'] as bool? ?? false,
    );
  }

  @override
  Future<void> startCapture() => channel.invokeMethod<void>('reshoot');

  @override
  Future<void> confirmAndTranslate() => channel.invokeMethod<void>('confirm');

  @override
  Future<void> retry() => channel.invokeMethod<void>('retry');

  @override
  Future<void> dismiss() => channel.invokeMethod<void>('dismiss');
}

// 独立结果视图复用现有结果页，主题及语言由主应用同步，不读取数据库或凭据。
class ScreenshotWindowApp extends ConsumerStatefulWidget {
  const ScreenshotWindowApp({super.key});

  @override
  ConsumerState<ScreenshotWindowApp> createState() =>
      _ScreenshotWindowAppState();
}

// 接收最新展示快照并完成就绪握手，避免窗口首次打开时丢失 OCR 或译文状态。
class _ScreenshotWindowAppState extends ConsumerState<ScreenshotWindowApp> {
  ThemeMode _themeMode = ThemeMode.system;
  Locale? _locale;

  @override
  void initState() {
    super.initState();
    ScreenshotWindowController.channel.setMethodCallHandler((call) async {
      if (call.method == 'update') {
        _update(call.arguments as Map<Object?, Object?>);
      }
    });
    _ready();
  }

  Future<void> _ready() async {
    final snapshot = await ScreenshotWindowController.channel
        .invokeMapMethod<Object?, Object?>('ready');
    if (mounted && snapshot != null) _update(snapshot);
  }

  void _update(Map<Object?, Object?> snapshot) {
    (ref.read(screenshotControllerProvider.notifier)
            as ScreenshotWindowController)
        .update(snapshot);
    setState(() {
      _themeMode = ThemeMode.values.byName(snapshot['themeMode'] as String);
      final language = snapshot['locale'] as String?;
      _locale = language == null ? null : Locale(language);
    });
  }

  @override
  void dispose() {
    ScreenshotWindowController.channel.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: appTheme(Brightness.light),
    darkTheme: appTheme(Brightness.dark),
    themeMode: _themeMode,
    locale: _locale,
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: ScreenshotResultPage(
      desktopWindow: true,
      onConfigure: () =>
          ScreenshotWindowController.channel.invokeMethod<void>('configure'),
    ),
  );
}
