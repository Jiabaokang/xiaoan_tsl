import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import 'package:xiaoan_tsl/app.dart';
import 'package:xiaoan_tsl/core/database/database_provider.dart';
import 'package:xiaoan_tsl/core/database/local_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final directory = await getApplicationDocumentsDirectory();
    final store = await LocalStore.open(
      legacyFile: File(path.join(directory.path, 'translation_history.json')),
    );
    runApp(
      ProviderScope(
        overrides: [localStoreProvider.overrideWithValue(store)],
        child: const XiaoanApp(),
      ),
    );
  } catch (_) {
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
