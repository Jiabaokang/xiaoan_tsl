import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:xiaoan_tsl/features/translate/app_controller.dart';
import 'package:xiaoan_tsl/features/language/app_languages.dart';
import 'package:xiaoan_tsl/core/database/database_provider.dart';
import 'package:xiaoan_tsl/features/history/history_store.dart';

// 历史与收藏复用同一列表，只由查询条件区分。
class RecordsPage extends ConsumerStatefulWidget {
  const RecordsPage({super.key, required this.favoritesOnly});

  final bool favoritesOnly;

  @override
  ConsumerState<RecordsPage> createState() => _RecordsPageState();
}

// 搜索条件仅属于当前列表页面，记录以数据库结果为准。
class _RecordsPageState extends ConsumerState<RecordsPage> {
  final _search = TextEditingController();
  late Future<List<TranslationRecord>> _results;

  @override
  void initState() {
    super.initState();
    _results = ref
        .read(localStoreProvider)
        .search('', favoritesOnly: widget.favoritesOnly);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _refresh() {
    setState(() {
      _results = ref
          .read(localStoreProvider)
          .search(_search.text, favoritesOnly: widget.favoritesOnly);
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(
      appControllerProvider.select((state) => state.records),
      (previous, next) => _refresh(),
    );
    final controller = ref.read(appControllerProvider.notifier);
    return Scaffold(
      appBar: AppBar(title: Text(widget.favoritesOnly ? '我的收藏' : '翻译历史')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
        children: [
          TextField(
            controller: _search,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: widget.favoritesOnly ? '搜索收藏' : '搜索原文或译文',
              border: const OutlineInputBorder(),
            ),
            onChanged: (_) => _refresh(),
          ),
          const SizedBox(height: 12),
          FutureBuilder<List<TranslationRecord>>(
            future: _results,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const ListTile(title: Text('读取记录失败，请重试'));
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final records = snapshot.data!;
              if (records.isEmpty) {
                return ListTile(
                  title: Text(
                    _search.text.isNotEmpty
                        ? '没有找到相关记录'
                        : widget.favoritesOnly
                            ? '还没有收藏'
                            : '还没有翻译记录',
                  ),
                );
              }
              return Column(
                children: [
                  for (final record in records)
                    Card(
                      child: Column(
                        children: [
                          ListTile(
                            title: Text(
                              record.sourceText,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              record.translatedText,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: () => context.go(
                              '/translate?record=${Uri.encodeQueryComponent(record.id)}',
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(14, 0, 5, 3),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '${appLanguages[record.sourceLanguage] ?? record.sourceLanguage} → ${appLanguages[record.targetLanguage] ?? record.targetLanguage} · ${record.engine == 'mlkit' ? '设备端记录' : '演示记录'}',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.labelSmall,
                                  ),
                                ),
                                IconButton(
                                  tooltip: record.favorite ? '取消收藏' : '收藏',
                                  onPressed: () =>
                                      controller.toggleFavorite(record),
                                  icon: Icon(
                                    record.favorite
                                        ? Icons.star
                                        : Icons.star_outline,
                                  ),
                                ),
                                IconButton(
                                  tooltip: '删除记录',
                                  onPressed: () =>
                                      controller.deleteRecord(record.id),
                                  icon: const Icon(Icons.delete_outline),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
