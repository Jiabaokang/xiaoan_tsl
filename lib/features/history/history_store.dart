import 'dart:convert';
import 'dart:io';

// 一条本地翻译记录，保留结果来自演示还是设备端引擎。
class TranslationRecord {
  const TranslationRecord({
    this.id = '',
    required this.sourceText,
    required this.translatedText,
    required this.sourceLanguage,
    required this.targetLanguage,
    required this.createdAt,
    this.favorite = false,
    this.engine = 'demo',
  });

  final String id;
  final String sourceText;
  final String translatedText;
  final String sourceLanguage;
  final String targetLanguage;
  final DateTime createdAt;
  final bool favorite;
  final String engine;

  TranslationRecord withFavorite(bool value) => TranslationRecord(
        id: id,
        sourceText: sourceText,
        translatedText: translatedText,
        sourceLanguage: sourceLanguage,
        targetLanguage: targetLanguage,
        createdAt: createdAt,
        favorite: value,
        engine: engine,
      );

  Map<String, Object> toJson() => {
        'id': id,
        'sourceText': sourceText,
        'translatedText': translatedText,
        'sourceLanguage': sourceLanguage,
        'targetLanguage': targetLanguage,
        'createdAt': createdAt.toIso8601String(),
        'favorite': favorite,
        'engine': engine,
      };

  factory TranslationRecord.fromJson(Map<String, dynamic> json) =>
      TranslationRecord(
        id: json['id'] as String? ?? '',
        sourceText: json['sourceText'] as String,
        translatedText: json['translatedText'] as String,
        sourceLanguage: json['sourceLanguage'] as String,
        targetLanguage: json['targetLanguage'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        favorite: json['favorite'] as bool? ?? false,
        engine: json['engine'] as String? ?? 'demo',
      );
}

// 在应用文档目录读写历史；先写临时文件以避免写入中断损坏原记录。
class HistoryStore {
  const HistoryStore(this.file);

  final File file;

  Future<List<TranslationRecord>> load() async {
    if (!await file.exists()) return [];
    final data = jsonDecode(await file.readAsString()) as List<dynamic>;
    return data
        .map((item) => TranslationRecord.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<void> save(List<TranslationRecord> records) async {
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(
      jsonEncode(records.map((e) => e.toJson()).toList()),
      flush: true,
    );
    await temporary.rename(file.path);
  }
}
