import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:xiaoan_tsl/features/translate/app_controller.dart';
import 'package:xiaoan_tsl/features/language/app_languages.dart';

// 本地偏好和应用信息的第四个底部入口。
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appControllerProvider);
    final controller = ref.read(appControllerProvider.notifier);
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(18, 14, 18, 4),
            child: Text('翻译偏好'),
          ),
          ListTile(
            leading: const Icon(Icons.translate),
            title: const Text('默认目标语言'),
            subtitle: Text(appLanguages[state.defaultTargetLanguage] ?? '简体中文'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/languages?mode=default-target'),
          ),
          ListTile(
            leading: const Icon(Icons.dark_mode_outlined),
            title: const Text('外观模式'),
            trailing: DropdownButton<ThemeMode>(
              value: state.themeMode,
              underline: const SizedBox.shrink(),
              items: const [
                DropdownMenuItem(value: ThemeMode.system, child: Text('跟随系统')),
                DropdownMenuItem(value: ThemeMode.light, child: Text('浅色')),
                DropdownMenuItem(value: ThemeMode.dark, child: Text('深色')),
              ],
              onChanged: (mode) {
                if (mode != null) controller.setThemeMode(mode);
              },
            ),
          ),
          ListTile(
            leading: const Icon(Icons.download_outlined),
            title: const Text('离线语言包'),
            subtitle: const Text('查看、下载或删除设备端模型'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/offline-models'),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: const Text('清空翻译历史'),
            onTap: state.records.isEmpty
                ? null
                : () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('清空翻译历史？'),
                        content: const Text('收藏也会一并删除，此操作无法撤销。'),
                        actions: [
                          TextButton(
                            onPressed: () => context.pop(false),
                            child: const Text('取消'),
                          ),
                          TextButton(
                            onPressed: () => context.pop(true),
                            child: const Text('清空'),
                          ),
                        ],
                      ),
                    );
                    if (confirmed == true) await controller.clearHistory();
                  },
          ),
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: const Text('隐私说明'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/privacy'),
          ),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('关于小安翻译'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/about'),
          ),
        ],
      ),
    );
  }
}
