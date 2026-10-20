import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:xiaoan_tsl/core/database/database_provider.dart';
import 'package:xiaoan_tsl/features/history/history_store.dart';
import 'package:xiaoan_tsl/features/translate/app_controller.dart';
import 'package:xiaoan_tsl/l10n/app_localizations.dart';

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
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.favoritesOnly ? l10n.favoritesTitle : l10n.recordsTitle,
        ),
      ),
      body: ListView(
        // 滚动留白叠加系统边衬，避免末项和横屏内容被系统区域遮挡。
        padding:
            const EdgeInsets.fromLTRB(18, 8, 18, 24) +
            MediaQuery.paddingOf(context),
        children: [
          TextField(
            controller: _search,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: widget.favoritesOnly
                  ? l10n.searchFavoritesHint
                  : l10n.searchRecordsHint,
              border: const OutlineInputBorder(),
            ),
            onChanged: (_) => _refresh(),
          ),
          const SizedBox(height: 12),
          FutureBuilder<List<TranslationRecord>>(
            future: _results,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return ListTile(title: Text(l10n.readRecordsFailed));
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final records = snapshot.data!;
              if (records.isEmpty) {
                return ListTile(
                  title: Text(
                    _search.text.isNotEmpty
                        ? l10n.noRecordsFound
                        : widget.favoritesOnly
                        ? l10n.emptyFavorites
                        : l10n.emptyRecords,
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
                                    '${l10n.languageName(record.sourceLanguage)} → ${l10n.languageName(record.targetLanguage)} · ${l10n.engineName(record.engine)}',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.labelSmall,
                                  ),
                                ),
                                IconButton(
                                  tooltip: record.favorite
                                      ? l10n.unfavoriteTooltip
                                      : l10n.favoriteTooltip,
                                  onPressed: () =>
                                      controller.toggleFavorite(record),
                                  icon: Icon(
                                    record.favorite
                                        ? Icons.star
                                        : Icons.star_outline,
                                  ),
                                ),
                                IconButton(
                                  tooltip: l10n.deleteRecordTooltip,
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
