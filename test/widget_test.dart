import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaoan_tsl/history_store.dart';
import 'package:xiaoan_tsl/main.dart';
import 'package:xiaoan_tsl/translation_service.dart';

// 组件测试用内存实现，避免 widget 测试的虚拟时钟等待真实磁盘 I/O。
class _MemoryHistoryStore extends HistoryStore {
  _MemoryHistoryStore() : super(File('unused'));

  List<TranslationRecord> records = [];

  @override
  Future<List<TranslationRecord>> load() async => List.of(records);

  @override
  Future<void> save(List<TranslationRecord> value) async {
    records = List.of(value);
  }
}

void main() {
  testWidgets('模拟翻译、收藏和本地历史可在重建后查看', (tester) async {
    final store = _MemoryHistoryStore();
    Widget app() => XiaoanApp(
      historyStore: store,
      translationService: DemoTranslationService(),
    );

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.text('把想说的话，\n翻译得更简单。'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('sourceInput')),
      'Hello, world!',
    );
    await tester.pump();
    await tester.ensureVisible(find.text('开始翻译'));
    await tester.tap(find.text('开始翻译'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('你好，世界！'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('你好，世界！'), findsOneWidget);

    await tester.ensureVisible(find.byTooltip('收藏译文'));
    await tester.tap(find.byTooltip('收藏译文'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('历史').last);
    await tester.pumpAndSettle();
    expect(find.text('Hello, world!'), findsOneWidget);
    expect(find.text('你好，世界！'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('收藏').last);
    await tester.pumpAndSettle();
    expect(find.text('Hello, world!'), findsOneWidget);
  });

  testWidgets('语言切换与相同语言提示', (tester) async {
    await tester.pumpWidget(
      XiaoanApp(
        historyStore: _MemoryHistoryStore(),
        translationService: DemoTranslationService(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('自动检测'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('简体中文').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('sourceInput')), '你好');
    await tester.pump();
    await tester.ensureVisible(find.text('开始翻译'));
    await tester.tap(find.text('开始翻译'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('原文与译文语言相同，请更换目标语言'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('原文与译文语言相同，请更换目标语言'), findsOneWidget);
  });

  test('本地历史文件可重新读取收藏状态', () async {
    final directory = await Directory.systemTemp.createTemp('xiaoan_test_');
    try {
      final store = HistoryStore(File('${directory.path}/history.json'));
      await store.save([
        TranslationRecord(
          sourceText: 'Hello',
          translatedText: '你好',
          sourceLanguage: 'en',
          targetLanguage: 'zh',
          createdAt: DateTime(2026, 9, 24),
          favorite: true,
        ),
      ]);
      final loaded = await store.load();
      expect(loaded.single.translatedText, '你好');
      expect(loaded.single.favorite, isTrue);
    } finally {
      await directory.delete(recursive: true);
    }
  });
}
