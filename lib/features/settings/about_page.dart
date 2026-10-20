import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:xiaoan_tsl/core/widgets/app_panel.dart';
import 'package:xiaoan_tsl/l10n/app_localizations.dart';

/// 项目自身的源码地址，与第三方依赖列表分别展示。
const projectSourceUrl = 'https://github.com/Jiabaokang/xiaoan_tsl';

/// 品牌化关于小安翻译主页面。
///
/// 遵循 Material 3 与设计规范，呈现：
/// 1. 顶部品牌 Header：应用图标、当前语言的应用名与动态版本号；
/// 2. 产品定位卡片：展示轻量、纯本地、注重隐私的定位介绍；
/// 3. 核心特性卡片组：离线双向翻译（Google ML Kit）、本地私密存储与本地语音朗读；
/// 4. 技术支持与服务卡片组：项目源码、第三方开源库与隐私政策入口；
/// 5. 底部版权声明 Footer。
class AboutPage extends StatelessWidget {
  const AboutPage({
    super.key,
    this.packageInfoFuture,
    this.onNavigateToDependencies,
    this.onNavigateToPrivacy,
    this.sourceUrlLauncher,
  });

  /// 可选注入的 PackageInfo Future，方便单元测试定制版本号。
  final Future<PackageInfo>? packageInfoFuture;

  /// 点击“第三方开源库与组件”时的导航回调，测试时可拦截，未指定时默认使用 [GoRouter] 跳转 `/about/dependencies`。
  final VoidCallback? onNavigateToDependencies;

  /// 点击“隐私政策”时的导航回调，测试时可拦截，未指定时默认使用 [GoRouter] 跳转 `/privacy`。
  final VoidCallback? onNavigateToPrivacy;

  /// 可注入的源码链接打开器，默认使用系统外部浏览器。
  final Future<bool> Function(Uri url, {LaunchMode mode})? sourceUrlLauncher;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.aboutAppLabel)),
      body: SingleChildScrollView(
        // 滚动留白叠加系统边衬，避免末项和横屏内容被系统区域遮挡。
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16) +
            MediaQuery.paddingOf(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _AboutBrandHeader(packageInfoFuture: packageInfoFuture),
            const SizedBox(height: 16),
            _AboutTaglineCard(tagline: l10n.aboutTagline),
            const SizedBox(height: 16),
            const _AboutFeaturesCard(),
            const SizedBox(height: 16),
            _AboutServicesCard(
              onNavigateToDependencies: onNavigateToDependencies,
              onNavigateToPrivacy: onNavigateToPrivacy,
              sourceUrlLauncher: sourceUrlLauncher,
            ),
            const SizedBox(height: 24),
            _AboutFooter(copyrightNotice: l10n.copyrightNotice),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

/// 顶部品牌 Header 组件，展示应用图标、当前语言的单行名称与动态版本号。
class _AboutBrandHeader extends StatelessWidget {
  const _AboutBrandHeader({this.packageInfoFuture});

  /// 可选注入的版本号 Future。
  final Future<PackageInfo>? packageInfoFuture;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = context.l10n;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(
                    alpha: theme.brightness == Brightness.dark ? 0.3 : 0.08,
                  ),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Image.asset(
              'assets/branding/app_icon_128.png',
              width: 76,
              height: 76,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            l10n.appName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          FutureBuilder<PackageInfo>(
            future: packageInfoFuture ?? PackageInfo.fromPlatform(),
            builder: (context, snapshot) {
              final versionText = snapshot.hasData
                  ? l10n.versionLabel(
                      snapshot.data!.version,
                      snapshot.data!.buildNumber,
                    )
                  : l10n.loadingVersion;
              return Text(
                versionText,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// 产品理念与定位口号卡片。
class _AboutTaglineCard extends StatelessWidget {
  const _AboutTaglineCard({required this.tagline});

  /// 产品定位文案。
  final String tagline;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return AppPanel(
      tinted: true,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: Icon(
                Icons.auto_awesome_outlined,
                size: 20,
                color: scheme.primary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                tagline,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurface,
                  height: 1.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 核心特性卡片组组件，展示三大核心功能。
class _AboutFeaturesCard extends StatelessWidget {
  const _AboutFeaturesCard();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return AppPanel(
      child: Column(
        children: [
          _AboutFeatureItem(
            icon: Icons.bolt_outlined,
            title: l10n.aboutFeatureOfflineTitle,
            description: l10n.aboutFeatureOfflineDesc,
          ),
          const Divider(height: 1, indent: 64),
          _AboutFeatureItem(
            icon: Icons.lock_outline,
            title: l10n.aboutFeaturePrivacyTitle,
            description: l10n.aboutFeaturePrivacyDesc,
          ),
          const Divider(height: 1, indent: 64),
          _AboutFeatureItem(
            icon: Icons.volume_up_outlined,
            title: l10n.aboutFeatureTtsTitle,
            description: l10n.aboutFeatureTtsDesc,
          ),
        ],
      ),
    );
  }
}

/// 单项特性条目展示组件。
class _AboutFeatureItem extends StatelessWidget {
  const _AboutFeatureItem({
    required this.icon,
    required this.title,
    required this.description,
  });

  /// 特性图标。
  final IconData icon;

  /// 特性标题。
  final String title;

  /// 特性详细描述。
  final String description;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: scheme.primaryContainer.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: 20, color: scheme.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 技术支持与服务卡片组组件，提供项目源码、第三方依赖及隐私政策入口。
class _AboutServicesCard extends StatelessWidget {
  const _AboutServicesCard({
    this.onNavigateToDependencies,
    this.onNavigateToPrivacy,
    this.sourceUrlLauncher,
  });

  /// 第三方依赖页面导航回调。
  final VoidCallback? onNavigateToDependencies;

  /// 隐私政策页面导航回调。
  final VoidCallback? onNavigateToPrivacy;

  /// 项目源码外部链接打开器。
  final Future<bool> Function(Uri url, {LaunchMode mode})? sourceUrlLauncher;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = context.l10n;

    return AppPanel(
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 4,
              ),
              leading: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Icon(
                  Icons.code_outlined,
                  size: 20,
                  color: scheme.primary,
                ),
              ),
              title: Text(
                l10n.projectSourceLabel,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: const Text('MIT · GitHub'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () async {
                final launcher = sourceUrlLauncher ?? launchUrl;
                try {
                  if (await launcher(
                    Uri.parse(projectSourceUrl),
                    mode: LaunchMode.externalApplication,
                  )) {
                    return;
                  }
                } catch (_) {
                  // 浏览器不可用时留在当前页面并提示用户。
                }
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(l10n.cannotOpenUrlNotice)),
                  );
                }
              },
            ),
            const Divider(height: 1, indent: 64),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 4,
              ),
              leading: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Icon(
                  Icons.extension_outlined,
                  size: 20,
                  color: scheme.primary,
                ),
              ),
              title: Text(
                l10n.openSourceDependenciesLabel,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
                l10n.openSourceDependenciesSubtitle,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () {
                if (onNavigateToDependencies != null) {
                  onNavigateToDependencies!();
                } else {
                  try {
                    context.push('/about/dependencies');
                  } catch (_) {
                    // 无路由上下文环境容错
                  }
                }
              },
            ),
            const Divider(height: 1, indent: 64),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 4,
              ),
              leading: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Icon(
                  Icons.security_outlined,
                  size: 20,
                  color: scheme.primary,
                ),
              ),
              title: Text(
                l10n.privacyPolicyLabel,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () {
                if (onNavigateToPrivacy != null) {
                  onNavigateToPrivacy!();
                } else {
                  try {
                    context.push('/privacy');
                  } catch (_) {
                    // 无路由上下文环境容错
                  }
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// 底部版权声明组件。
class _AboutFooter extends StatelessWidget {
  const _AboutFooter({required this.copyrightNotice});

  /// 版权信息文本。
  final String copyrightNotice;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Center(
      child: Text(
        copyrightNotice,
        style: theme.textTheme.bodySmall?.copyWith(color: scheme.outline),
        textAlign: TextAlign.center,
      ),
    );
  }
}
