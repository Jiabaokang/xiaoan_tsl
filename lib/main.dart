import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import 'package:xiaoan_tsl/app.dart';
import 'package:xiaoan_tsl/core/database/database_provider.dart';
import 'package:xiaoan_tsl/core/database/local_store.dart';

Future<void> main() async {
  final widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  // 在异步初始化本地存储与数据库期间保活原生启动页，避免低版本系统上因切换空主题出现白屏闪烁。
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);
  try {
    final directory = await getApplicationDocumentsDirectory();
    final store = await LocalStore.open(
      legacyFile: File(path.join(directory.path, 'translation_history.json')),
    );
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
