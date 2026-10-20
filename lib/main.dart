import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import 'package:xiaoan_tsl/app.dart';
import 'package:xiaoan_tsl/core/database/database_provider.dart';
import 'package:xiaoan_tsl/core/database/local_store.dart';
import 'package:xiaoan_tsl/services/desktop/macos_desktop_service.dart';
import 'package:xiaoan_tsl/services/translation/translation_settings.dart';

Future<void> main() async {
  final widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  // 在异步初始化本地存储与数据库期间保活原生启动页，避免低版本系统上因切换空主题出现白屏闪烁。
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);
  try {
    final directory = await getApplicationDocumentsDirectory();
    final store = await LocalStore.open(
      legacyFile: File(path.join(directory.path, 'translation_history.json')),
    );
    // macOS 启动完成后恢复全局截图快捷键配置；注册冲突不阻塞启动，可在设置页重选。
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.macOS) {
      final shortcut =
          await store.getSetting(TranslationSettingKeys.screenshotShortcut) ??
          'Control+Option+T';
      try {
        await MacosDesktopChannel().updateShortcut(shortcut);
      } catch (_) {
        // 冲突或通道未就绪时保留原状，设置页会提示重新选择。
      }
    }
    // 异步初始化完成，允许渲染首帧并移除原生启动屏。
    FlutterNativeSplash.remove();
    runApp(
      ProviderScope(
        overrides: [localStoreProvider.overrideWithValue(store)],
        child: const XiaoanApp(),
      ),
    );
  } catch (_) {
    // 异常情况下同样移除启动页，进入兜底错误提示界面。
    FlutterNativeSplash.remove();
    // 旧历史异常时保留原文件，避免以空数据启动后覆盖用户记录。
    runApp(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('本地历史读取失败。原文件已保留，请检查设备存储后重试。'),
            ),
          ),
        ),
      ),
    );
  }
}

// 独立结果引擎已废弃：原位覆盖面板由原生 NSView 渲染，不再启动第二个 Flutter Engine。
// 保留入口避免原生侧未清理的旧引用在运行时崩溃。
@pragma('vm:entry-point')
void screenshotWindowMain() {
  // 已被原生覆盖面板替代，此入口不再实际使用。
}
