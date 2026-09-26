import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:xiaoan_tsl/l10n/app_localizations.dart';

/// 第三方开源依赖包元数据模型，包含包名、版本约束、中英文职责描述及镜像地址计算。
class PackageDependency {
  const PackageDependency({
    required this.name,
    required this.version,
    required this.descriptionZh,
    required this.descriptionEn,
  });

  /// 包名（pub.dev 注册名）。
  final String name;

  /// pubspec.yaml 中的版本范围或语义版本约束。
  final String version;

  /// 中文职责与功能描述。
  final String descriptionZh;

  /// 英文职责与功能描述。
  final String descriptionEn;

  /// 国内 pub 镜像详情页 URL 地址。
  String get mirrorUrl => 'https://pub-web.flutter-io.cn/packages/$name';

  /// 根据本地化语言环境获取适用的说明文案。
  String localizedDescription(BuildContext context) {
    final languageCode = Localizations.localeOf(context).languageCode;
    return languageCode == 'zh' ? descriptionZh : descriptionEn;
  }
}

/// 打开指定依赖在 pub-web 上的镜像页面。
Future<void> openDependencyMirror(
  BuildContext context,
  PackageDependency pkg, {
  Future<bool> Function(Uri url, {LaunchMode mode})? urlLauncher,
}) async {
  final uri = Uri.parse(pkg.mirrorUrl);
  final launcher = urlLauncher ?? launchUrl;
  try {
    if (await launcher(uri, mode: LaunchMode.externalApplication)) {
      return;
    }
  } catch (_) {
    // 无法调起系统浏览器或 URL 解析失败时降级提示。
  }
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.cannotOpenUrlNotice)),
    );
  }
}

/// 应用运行所依赖的 13 个核心开源库列表。
const List<PackageDependency> corePackageDependencies = [
  PackageDependency(
    name: 'flutter_riverpod',
    version: '^3.4.3',
    descriptionZh: '响应式状态管理与依赖注入框架',
    descriptionEn:
        'Reactive state management and dependency injection framework',
  ),
  PackageDependency(
    name: 'go_router',
    version: '^18.0.1',
    descriptionZh: '声明式路由与页面导航系统',
    descriptionEn: 'Declarative routing and navigation system',
  ),
  PackageDependency(
    name: 'google_mlkit_translation',
    version: '^0.15.1',
    descriptionZh: '设备端离线语言机器翻译模型引擎',
    descriptionEn: 'On-device offline machine translation engine',
  ),
  PackageDependency(
    name: 'google_mlkit_language_id',
    version: '^0.15.1',
    descriptionZh: '设备端语种快速自动识别引擎',
    descriptionEn: 'On-device language identification engine',
  ),
  PackageDependency(
    name: 'sqflite',
    version: '^2.4.4',
    descriptionZh: '设备端 SQLite 关系型嵌入式数据库',
    descriptionEn: 'On-device SQLite relational embedded database',
  ),
  PackageDependency(
    name: 'flutter_tts',
    version: '^4.2.5',
    descriptionZh: '设备端文字转语音合成（TTS）直连',
    descriptionEn: 'On-device text-to-speech synthesis integration',
  ),
  PackageDependency(
    name: 'dio',
    version: '^5.11.1',
    descriptionZh: '网络传输与离线模型下载管理客户端',
    descriptionEn: 'HTTP networking client and model download management',
  ),
  PackageDependency(
    name: 'path_provider',
    version: '^2.1.5',
    descriptionZh: '跨平台沙盒文件系统路径访问支持',
    descriptionEn: 'Cross-platform sandboxed file system path provider',
  ),
  PackageDependency(
    name: 'package_info_plus',
    version: '^8.3.0',
    descriptionZh: '读取应用原生版本号与构建编号信息',
    descriptionEn: 'Application package information and version reader',
  ),
  PackageDependency(
    name: 'url_launcher',
    version: '^6.3.1',
    descriptionZh: '调用系统外部浏览器打开网页链接',
    descriptionEn: 'External application and web browser launcher',
  ),
  PackageDependency(
    name: 'share_plus',
    version: '^11.1.0',
    descriptionZh: '调用操作系统原生分享交互面板',
    descriptionEn: 'Native system share sheet integration',
  ),
  PackageDependency(
    name: 'flutter_native_splash',
    version: '^2.4.8',
    descriptionZh: '原生平台冷启动闪屏显示与管理',
    descriptionEn: 'Native cold-start splash screen management',
  ),
  PackageDependency(
    name: 'cupertino_icons',
    version: '^1.0.8',
    descriptionZh: 'iOS 风格辅助矢量界面图标集合',
    descriptionEn: 'Cupertino style vector icon set',
  ),
];

/// 第三方开源库与组件展示页面。
///
/// 列出本应用使用的核心第三方开源依赖，展示包名、版本约束与功能简介，
/// 并提供点击调用系统浏览器跳转到国内镜像详情页的功能。
class OpenSourceLicensesPage extends StatelessWidget {
  const OpenSourceLicensesPage({
    super.key,
    this.dependencies = corePackageDependencies,
    this.urlLauncher,
  });

  /// 依赖列表，默认使用 [corePackageDependencies]，测试时可注入定制数据。
  final List<PackageDependency> dependencies;

  /// 自定义 URL 打开实现，默认调用 url_launcher 的 [launchUrl]。
  final Future<bool> Function(Uri url, {LaunchMode mode})? urlLauncher;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.openSourceDependenciesTitle),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _OpenSourceHeaderNotice(notice: l10n.openSourcePageNotice),
            const SizedBox(height: 12),
            ...dependencies.asMap().entries.map((entry) {
              final index = entry.key;
              final pkg = entry.value;
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (index > 0) const Divider(height: 1, indent: 68),
                  _DependencyListTile(
                    pkg: pkg,
                    urlLauncher: urlLauncher,
                  ),
                ],
              );
            }),
          ],
        ),
      ),
    );
  }
}

/// 顶部开源许可合规提示卡片。
class _OpenSourceHeaderNotice extends StatelessWidget {
  const _OpenSourceHeaderNotice({required this.notice});

  /// 提示文案内容。
  final String notice;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline,
            size: 20,
            color: scheme.primary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              notice,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.4,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 单个第三方开源依赖列表项组件。
class _DependencyListTile extends StatelessWidget {
  const _DependencyListTile({
    required this.pkg,
    this.urlLauncher,
  });

  /// 对应的开源依赖元数据。
  final PackageDependency pkg;

  /// 自定义 URL 打开实现。
  final Future<bool> Function(Uri url, {LaunchMode mode})? urlLauncher;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: scheme.primaryContainer.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(10),
        ),
        alignment: Alignment.center,
        child: Icon(
          Icons.extension_outlined,
          color: scheme.primary,
          size: 22,
        ),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              pkg.name,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: scheme.secondaryContainer.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              pkg.version,
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSecondaryContainer,
                fontFamily: 'monospace',
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          pkg.localizedDescription(context),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
      ),
      trailing: IconButton(
        icon: const Icon(Icons.open_in_new, size: 20),
        color: scheme.primary,
        tooltip: pkg.mirrorUrl,
        onPressed: () => openDependencyMirror(
          context,
          pkg,
          urlLauncher: urlLauncher,
        ),
      ),
      onTap: () => openDependencyMirror(
        context,
        pkg,
        urlLauncher: urlLauncher,
      ),
    );
  }
}
