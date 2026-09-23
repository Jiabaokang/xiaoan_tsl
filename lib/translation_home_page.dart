import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import 'history_store.dart';
import 'translation_service.dart';

const _languages = <String, String>{
  'auto': '自动检测',
  'zh': '简体中文',
  'en': 'English',
  'ja': '日本語',
  'ko': '한국어',
  'fr': 'Français',
  'de': 'Deutsch',
  'es': 'Español',
  'pt': 'Português',
  'it': 'Italiano',
  'ru': 'Русский',
};

// 翻译首页及本地历史、收藏入口。
class TranslationHomePage extends StatefulWidget {
  const TranslationHomePage({
    super.key,
    required this.historyStore,
    required this.translationService,
  });

  final HistoryStore historyStore;
  final TranslationService translationService;

  @override
  State<TranslationHomePage> createState() => _TranslationHomePageState();
}

// 保持输入、模拟结果和本地记录的页面状态。
class _TranslationHomePageState extends State<TranslationHomePage> {
  final _input = TextEditingController();
  final _search = TextEditingController();
  List<TranslationRecord> _records = [];
  TranslationRecord? _result;
  String _source = 'auto';
  String _target = 'zh';
  String? _detected;
  String _status = '等待翻译';
  int _tab = 0;
  int _request = 0;
  bool _busy = false;
  bool _storageReady = false;
  Future<void> _pendingSave = Future.value();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _input.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final records = await widget.historyStore.load();
      if (mounted) {
        setState(() {
          _records = records;
          _storageReady = true;
        });
      }
    } catch (_) {
      if (mounted) _notice('读取本地历史失败，当前不会覆盖原记录');
    }
  }

  Future<void> _save() async {
    if (!_storageReady) return;
    final snapshot = List<TranslationRecord>.of(_records);
    _pendingSave = _pendingSave
        .catchError((_) {})
        .then((_) => widget.historyStore.save(snapshot));
    try {
      await _pendingSave;
    } catch (_) {
      if (mounted) _notice('保存本地历史失败，请检查设备存储');
    }
  }

  void _notice(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  void _inputChanged() {
    setState(() {
      _request++;
      _busy = false;
      _result = null;
      _status = '等待翻译';
      _detected = null;
    });
  }

  String? _detect(String text) {
    if (RegExp(r'[\u3040-\u30ff]').hasMatch(text)) return 'ja';
    if (RegExp(r'[\uac00-\ud7af]').hasMatch(text)) return 'ko';
    if (RegExp(r'[\u4e00-\u9fff]').hasMatch(text)) return 'zh';
    if (RegExp(r'[a-zA-Z]').hasMatch(text) && text.trim().length > 3) {
      return 'en';
    }
    return null;
  }

  Future<void> _chooseLanguage(bool source) async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.7,
            child: Column(
              children: [
                Text(
                  source ? '选择原文语言' : '选择译文语言',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: ListView(
                    children: [
                      for (final language in _languages.entries)
                        if (source || language.key != 'auto')
                          ListTile(
                            title: Text(language.value),
                            trailing:
                                (source ? _source : _target) == language.key
                                ? const Icon(Icons.check)
                                : null,
                            onTap: () => Navigator.pop(context, language.key),
                          ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (selected == null || !mounted) return;
    setState(() {
      if (source) {
        _source = selected;
        _detected = null;
      } else {
        _target = selected;
      }
      _request++;
      _result = null;
      _status = '等待翻译';
    });
  }

  void _swap() {
    final resolved = _source == 'auto' ? _detected : _source;
    if (resolved == null) {
      _notice('请先翻译或手动选择原文语言');
      return;
    }
    setState(() {
      final oldTarget = _target;
      _target = resolved;
      _source = oldTarget;
      _detected = null;
      _request++;
      if (_result != null) _input.text = _result!.translatedText;
      _result = null;
      _status = '等待翻译';
    });
  }

  Future<void> _translate() async {
    final text = _input.text.trim();
    if (text.isEmpty || _busy) return;
    final source = _source == 'auto' ? _detect(text) : _source;
    if (source == null) {
      setState(() => _status = '无法判断语言，请手动选择原文语言');
      return;
    }
    if (source == _target) {
      setState(() => _status = '原文与译文语言相同，请更换目标语言');
      return;
    }
    final request = ++_request;
    setState(() {
      _busy = true;
      _status = '正在生成模拟译文';
      _result = null;
    });
    try {
      final translated = await widget.translationService.translate(
        text: text,
        sourceLanguage: source,
        targetLanguage: _target,
      );
      if (!mounted || request != _request) return;
      final recent = _records.where(
        (record) =>
            record.sourceText == text &&
            record.sourceLanguage == source &&
            record.targetLanguage == _target &&
            DateTime.now().difference(record.createdAt).inSeconds < 60,
      );
      final record = TranslationRecord(
        sourceText: text,
        translatedText: translated,
        sourceLanguage: source,
        targetLanguage: _target,
        createdAt: DateTime.now(),
        favorite: recent.isNotEmpty && recent.first.favorite,
      );
      setState(() {
        _busy = false;
        _detected = source;
        _status = '模拟翻译完成';
        _result = record;
        if (_storageReady) {
          _records.removeWhere(
            (item) =>
                item.sourceText == text &&
                item.sourceLanguage == source &&
                item.targetLanguage == _target &&
                DateTime.now().difference(item.createdAt).inSeconds < 60,
          );
          _records.insert(0, record);
        }
      });
      await _save();
    } catch (_) {
      if (mounted && request == _request) {
        setState(() {
          _busy = false;
          _status = '翻译失败，请重试';
        });
      }
    }
  }

  void _favorite(TranslationRecord record) {
    final index = _records.indexOf(record);
    if (index < 0) return;
    final updated = record.withFavorite(!record.favorite);
    setState(() {
      _records[index] = updated;
      if (identical(_result, record)) _result = updated;
    });
    _save();
    _notice(updated.favorite ? '已加入收藏' : '已取消收藏');
  }

  void _openRecord(TranslationRecord record) {
    setState(() {
      _tab = 0;
      _source = record.sourceLanguage;
      _target = record.targetLanguage;
      _input.text = record.sourceText;
      _result = record;
      _status = '来自历史';
    });
  }

  Future<void> _clearHistory() async {
    if (_records.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空翻译历史？'),
        content: const Text('收藏也会一并删除，此操作无法撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _records.clear();
      _result = null;
    });
    await _save();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: theme.scaffoldBackgroundColor,
        title: Row(
          children: [
            Container(
              width: 31,
              height: 31,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '安',
                style: TextStyle(
                  color: theme.colorScheme.onPrimary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 9),
            const Text('小安翻译', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(width: 8),
            Text('演示版', style: theme.textTheme.labelSmall),
          ],
        ),
      ),
      body: SafeArea(
        child: IndexedStack(
          index: _tab,
          children: [
            _translationView(theme),
            _recordView(false, theme),
            _recordView(true, theme),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (index) => setState(() {
          _tab = index;
          _search.clear();
        }),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.translate), label: '翻译'),
          NavigationDestination(icon: Icon(Icons.history), label: '历史'),
          NavigationDestination(icon: Icon(Icons.star_outline), label: '收藏'),
        ],
      ),
    );
  }

  Widget _translationView(ThemeData theme) => ListView(
    padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
    children: [
      Text(
        '随时翻译 · 轻松记住',
        style: TextStyle(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: 7),
      Text(
        '把想说的话，\n翻译得更简单。',
        style: theme.textTheme.headlineSmall?.copyWith(
          fontWeight: FontWeight.bold,
          height: 1.25,
        ),
      ),
      const SizedBox(height: 6),
      Text('文字留在设备中，常用表达随手收藏。', style: theme.textTheme.bodySmall),
      const SizedBox(height: 18),
      _Panel(
        child: Row(
          children: [
            Expanded(
              child: _languageButton(
                '原文语言',
                _source,
                () => _chooseLanguage(true),
              ),
            ),
            IconButton(
              tooltip: '交换语言',
              onPressed: _swap,
              icon: const Icon(Icons.swap_horiz),
            ),
            Expanded(
              child: _languageButton(
                '译文语言',
                _target,
                () => _chooseLanguage(false),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 13),
      _Panel(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    '输入文字',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    _detected == null ? '等待输入' : '检测为 ${_languages[_detected]}',
                    style: theme.textTheme.labelSmall,
                  ),
                ],
              ),
              TextField(
                key: const Key('sourceInput'),
                controller: _input,
                maxLength: 5000,
                maxLines: 5,
                minLines: 2,
                decoration: const InputDecoration(
                  hintText: '在这里输入要翻译的内容…',
                  border: InputBorder.none,
                  counterText: '',
                ),
                onChanged: (_) => _inputChanged(),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${_input.text.length} / 5000',
                    style: theme.textTheme.labelSmall,
                  ),
                  IconButton(
                    tooltip: '清空输入',
                    onPressed: () {
                      _input.clear();
                      _inputChanged();
                    },
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 13),
      FilledButton.icon(
        onPressed: _input.text.trim().isEmpty || _busy ? null : _translate,
        icon: _busy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.arrow_forward),
        label: Text(_busy ? '正在翻译…' : '开始翻译'),
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(51)),
      ),
      const SizedBox(height: 8),
      Text(
        '当前使用模拟译文，未下载或接入 ML Kit 模型',
        textAlign: TextAlign.center,
        style: theme.textTheme.labelSmall,
      ),
      const SizedBox(height: 12),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final sample in [
              'Hello, world!',
              'Good morning',
              '谢谢你的帮助',
              'How are you?',
            ])
              Padding(
                padding: const EdgeInsets.only(right: 7),
                child: ActionChip(
                  label: Text(sample),
                  onPressed: () {
                    _input.text = sample;
                    _source = 'auto';
                    _target = RegExp(r'[\u4e00-\u9fff]').hasMatch(sample)
                        ? 'en'
                        : 'zh';
                    _inputChanged();
                  },
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: 13),
      _Panel(
        tinted: true,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 10, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    '翻译结果',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Text(_status, style: theme.textTheme.labelSmall),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 86,
                child: Align(
                  alignment: Alignment.topLeft,
                  child: SelectableText(
                    _result?.translatedText ?? '译文会显示在这里',
                    style: _result == null
                        ? theme.textTheme.bodyMedium
                        : theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                  ),
                ),
              ),
              Divider(color: theme.colorScheme.outlineVariant),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _result == null
                          ? '—'
                          : '${_languages[_result!.sourceLanguage]} → ${_languages[_result!.targetLanguage]}',
                      style: theme.textTheme.labelSmall,
                    ),
                  ),
                  IconButton(
                    tooltip: _result?.favorite == true ? '取消收藏' : '收藏译文',
                    onPressed: _result == null || !_storageReady
                        ? null
                        : () => _favorite(_result!),
                    icon: Icon(
                      _result?.favorite == true
                          ? Icons.star
                          : Icons.star_outline,
                    ),
                  ),
                  IconButton(
                    tooltip: '复制译文',
                    onPressed: _result == null
                        ? null
                        : () async {
                            await Clipboard.setData(
                              ClipboardData(text: _result!.translatedText),
                            );
                            if (mounted) _notice('已复制译文');
                          },
                    icon: const Icon(Icons.copy_outlined),
                  ),
                  IconButton(
                    tooltip: '分享译文',
                    onPressed: _result == null
                        ? null
                        : () async {
                            final result = _result!;
                            await Share.share(
                              '${result.sourceText}\n\n${result.translatedText}\n\n— 小安翻译',
                            );
                          },
                    icon: const Icon(Icons.share_outlined),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 8),
      Text('示例译文仅供交互演示，不代表真实翻译效果。', style: theme.textTheme.labelSmall),
    ],
  );

  Widget _languageButton(String caption, String code, VoidCallback onTap) =>
      TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(caption, style: Theme.of(context).textTheme.labelSmall),
            const SizedBox(height: 3),
            Text(
              _languages[code]!,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
      );

  Widget _recordView(bool favorites, ThemeData theme) {
    final query = _search.text.trim().toLowerCase();
    final records = _records
        .where(
          (record) =>
              (!favorites || record.favorite) &&
              (query.isEmpty ||
                  record.sourceText.toLowerCase().contains(query) ||
                  record.translatedText.toLowerCase().contains(query)),
        )
        .toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                favorites ? '我的收藏' : '翻译历史',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            if (!favorites && _records.isNotEmpty)
              TextButton(onPressed: _clearHistory, child: const Text('清空')),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _search,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search),
            hintText: favorites ? '搜索收藏' : '搜索原文或译文',
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        if (records.isEmpty)
          _Panel(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Center(
                child: Text(
                  query.isNotEmpty
                      ? '没有找到相关记录'
                      : favorites
                      ? '还没有收藏'
                      : '还没有翻译记录',
                ),
              ),
            ),
          ),
        for (final record in records)
          Padding(
            padding: const EdgeInsets.only(bottom: 9),
            child: _Panel(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(13, 8, 8, 5),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    InkWell(
                      onTap: () => _openRecord(record),
                      child: SizedBox(
                        width: double.infinity,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              record.sourceText,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              record.translatedText,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const Divider(),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${_languages[record.sourceLanguage]} → ${_languages[record.targetLanguage]}',
                            style: theme.textTheme.labelSmall,
                          ),
                        ),
                        IconButton(
                          tooltip: record.favorite ? '取消收藏' : '收藏',
                          onPressed: () => _favorite(record),
                          icon: Icon(
                            record.favorite ? Icons.star : Icons.star_outline,
                          ),
                        ),
                        IconButton(
                          tooltip: '删除记录',
                          onPressed: () {
                            setState(() {
                              _records.remove(record);
                              if (identical(_result, record)) _result = null;
                            });
                            _save();
                          },
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// 首页语言栏、输入卡片、结果卡片及记录复用的圆角容器。
class _Panel extends StatelessWidget {
  const _Panel({required this.child, this.tinted = false});
  final Widget child;
  final bool tinted;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: tinted
            ? scheme.primaryContainer.withValues(alpha: 0.48)
            : scheme.surface,
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(20),
      ),
      child: child,
    );
  }
}
