import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:xiaoan_tsl/features/history/history_store.dart';
import 'package:xiaoan_tsl/core/database/local_store.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('迁移旧历史只执行一次，保留收藏和旧文件', () async {
    final directory = await Directory.systemTemp.createTemp('xiaoan_db_');
    try {
      final legacy = File(
        path.join(directory.path, 'translation_history.json'),
      );
      await HistoryStore(legacy).save([
        TranslationRecord(
          sourceText: 'Hello',
          translatedText: '你好',
          sourceLanguage: 'en',
          targetLanguage: 'zh',
          createdAt: DateTime(2026, 9, 24),
          favorite: true,
        ),
      ]);
      final databasePath = path.join(directory.path, 'app.db');
      var store = await LocalStore.open(
        path: databasePath,
        legacyFile: legacy,
        factory: databaseFactoryFfi,
      );
      expect((await store.search('你好')).single.favorite, isTrue);
      expect(
        (await store.search('Hello')).single.createdAt,
        DateTime(2026, 9, 24),
      );
      await store.close();

      store = await LocalStore.open(
        path: databasePath,
        legacyFile: legacy,
        factory: databaseFactoryFfi,
      );
      expect((await store.search('')).length, 1);
      expect(await legacy.exists(), isTrue);
      await store.close();
    } finally {
      await directory.delete(recursive: true);
    }
  });

  test('损坏旧文件不被覆盖，修复后仍可导入', () async {
    final directory = await Directory.systemTemp.createTemp('xiaoan_db_');
    try {
      final legacy = File(
        path.join(directory.path, 'translation_history.json'),
      );
      await legacy.writeAsString('{broken');
      final databasePath = path.join(directory.path, 'app.db');
      await expectLater(
        LocalStore.open(
          path: databasePath,
          legacyFile: legacy,
          factory: databaseFactoryFfi,
        ),
        throwsFormatException,
      );
      expect(await legacy.readAsString(), '{broken');
      await HistoryStore(legacy).save([
        TranslationRecord(
          sourceText: 'Good morning',
          translatedText: '早上好',
          sourceLanguage: 'en',
          targetLanguage: 'zh',
          createdAt: DateTime(2026, 9, 24),
        ),
      ]);
      final store = await LocalStore.open(
        path: databasePath,
        legacyFile: legacy,
        factory: databaseFactoryFfi,
      );
      expect((await store.search('早上好')).length, 1);
      await store.close();
    } finally {
      await directory.delete(recursive: true);
    }
  });

  test('记录、收藏、搜索、删除与设置写入数据库', () async {
    final directory = await Directory.systemTemp.createTemp('xiaoan_db_');
    try {
      final databasePath = path.join(directory.path, 'app.db');
      var store = await LocalStore.open(
        path: databasePath,
        legacyFile: File(path.join(directory.path, 'none.json')),
        factory: databaseFactoryFfi,
      );
      final saved = await store.saveRecord(
        TranslationRecord(
          sourceText: 'Hello',
          translatedText: '你好',
          sourceLanguage: 'en',
          targetLanguage: 'zh',
          createdAt: DateTime.now(),
        ),
      );
      expect(saved.id, isNotEmpty);
      await store.setFavorite(saved.id, true);
      await store.close();
      store = await LocalStore.open(
        path: databasePath,
        legacyFile: File(path.join(directory.path, 'none.json')),
        factory: databaseFactoryFfi,
      );
      expect(
        (await store.search('你好', favoritesOnly: true)).single.id,
        saved.id,
      );
      await store.setSetting('target', 'en');
      expect(await store.getSetting('target'), 'en');
      await store.deleteRecord(saved.id);
      expect(await store.search(''), isEmpty);
      await store.close();
    } finally {
      await directory.delete(recursive: true);
    }
  });
}
