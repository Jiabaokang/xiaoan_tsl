import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'package:xiaoan_tsl/features/history/history_store.dart';

// SQLite 持久化入口；旧 JSON 仅在首次打开数据库时导入。
class LocalStore {
  LocalStore._(this._database);

  final Database _database;
  static final _random = Random.secure();

  static Future<LocalStore> open({
    required File legacyFile,
    String? path,
    DatabaseFactory? factory,
  }) async {
    final effectiveFactory = factory ?? databaseFactory;
    final databasePath =
        path ?? p.join(await effectiveFactory.getDatabasesPath(), 'xiaoan.db');
    final database = await effectiveFactory.openDatabase(
      databasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) async {
          await db.execute('''
            CREATE TABLE translation_records (
              id TEXT PRIMARY KEY,
              source_text TEXT NOT NULL,
              translated_text TEXT NOT NULL,
              source_language TEXT NOT NULL,
              target_language TEXT NOT NULL,
              is_favorite INTEGER NOT NULL DEFAULT 0,
              engine TEXT NOT NULL DEFAULT 'demo',
              created_at INTEGER NOT NULL,
              updated_at INTEGER NOT NULL
            )
          ''');
          await db.execute(
            'CREATE INDEX records_created_at ON translation_records(created_at DESC)',
          );
          await db.execute(
            'CREATE INDEX records_favorite ON translation_records(is_favorite, created_at DESC)',
          );
          await db.execute(
            'CREATE TABLE app_settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
          );
        },
      ),
    );
    final store = LocalStore._(database);
    try {
      await store._importLegacy(legacyFile);
      return store;
    } catch (_) {
      await database.close();
      rethrow;
    }
  }

  Future<void> _importLegacy(File legacyFile) async {
    if (await getSetting('legacy_json_imported') == '1') return;
    // 先解析整份旧文件；解析失败时不写迁移标记，也不删除原始数据。
    final records = await HistoryStore(legacyFile).load();
    await _database.transaction((transaction) async {
      for (var index = 0; index < records.length; index++) {
        final record = records[index];
        await transaction.insert(
          'translation_records',
          _recordMap(
            record,
            id: record.id.isEmpty
                ? 'legacy-$index-${record.createdAt.millisecondsSinceEpoch}'
                : record.id,
          ),
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
      await transaction.insert('app_settings', {
        'key': 'legacy_json_imported',
        'value': '1',
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  static Map<String, Object> _recordMap(
    TranslationRecord record, {
    required String id,
  }) => {
    'id': id,
    'source_text': record.sourceText,
    'translated_text': record.translatedText,
    'source_language': record.sourceLanguage,
    'target_language': record.targetLanguage,
    'is_favorite': record.favorite ? 1 : 0,
    'engine': record.engine,
    'created_at': record.createdAt.millisecondsSinceEpoch,
    'updated_at': DateTime.now().millisecondsSinceEpoch,
  };

  static TranslationRecord _fromRow(Map<String, Object?> row) =>
      TranslationRecord(
        id: row['id'] as String,
        sourceText: row['source_text'] as String,
        translatedText: row['translated_text'] as String,
        sourceLanguage: row['source_language'] as String,
        targetLanguage: row['target_language'] as String,
        favorite: row['is_favorite'] == 1,
        engine: row['engine'] as String? ?? 'demo',
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          row['created_at'] as int,
        ),
      );

  Future<List<TranslationRecord>> search(
    String query, {
    bool favoritesOnly = false,
  }) async {
    final where = <String>[];
    final args = <Object>[];
    if (favoritesOnly) where.add('is_favorite = 1');
    if (query.trim().isNotEmpty) {
      final escaped = query
          .trim()
          .replaceAll('!', '!!')
          .replaceAll('%', '!%')
          .replaceAll('_', '!_');
      where.add(
        "(source_text LIKE ? ESCAPE '!' OR translated_text LIKE ? ESCAPE '!')",
      );
      args.addAll(['%$escaped%', '%$escaped%']);
    }
    final rows = await _database.query(
      'translation_records',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'created_at DESC',
    );
    return rows.map(_fromRow).toList();
  }

  Future<TranslationRecord?> getRecord(String id) async {
    final rows = await _database.query(
      'translation_records',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : _fromRow(rows.single);
  }

  Future<TranslationRecord> saveRecord(TranslationRecord record) async {
    final now = DateTime.now();
    final recent = await _database.query(
      'translation_records',
      where:
          'source_text = ? AND source_language = ? AND target_language = ? AND engine = ? AND created_at >= ?',
      whereArgs: [
        record.sourceText,
        record.sourceLanguage,
        record.targetLanguage,
        record.engine,
        now.subtract(const Duration(minutes: 1)).millisecondsSinceEpoch,
      ],
      orderBy: 'created_at DESC',
      limit: 1,
    );
    final previous = recent.isEmpty ? null : _fromRow(recent.single);
    final id =
        previous?.id ??
        (record.id.isEmpty
            ? '${now.microsecondsSinceEpoch.toRadixString(36)}-${_random.nextInt(1 << 32).toRadixString(36)}'
            : record.id);
    final saved = TranslationRecord(
      id: id,
      sourceText: record.sourceText,
      translatedText: record.translatedText,
      sourceLanguage: record.sourceLanguage,
      targetLanguage: record.targetLanguage,
      createdAt: now,
      favorite: previous?.favorite ?? record.favorite,
      engine: record.engine,
    );
    await _database.insert(
      'translation_records',
      _recordMap(saved, id: id),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return saved;
  }

  Future<void> setFavorite(String id, bool value) => _database
      .update(
        'translation_records',
        {
          'is_favorite': value ? 1 : 0,
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: [id],
      )
      .then((_) {});

  Future<void> deleteRecord(String id) => _database
      .delete('translation_records', where: 'id = ?', whereArgs: [id])
      .then((_) {});

  Future<void> clearRecords() =>
      _database.delete('translation_records').then((_) {});

  Future<String?> getSetting(String key) async {
    final rows = await _database.query(
      'app_settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.single['value'] as String;
  }

  Future<void> setSetting(String key, String value) => _database
      .insert('app_settings', {
        'key': key,
        'value': value,
      }, conflictAlgorithm: ConflictAlgorithm.replace)
      .then((_) {});

  Future<void> close() => _database.close();
}
