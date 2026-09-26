import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:xiaoan_tsl/core/widgets/app_panel.dart';
import 'package:xiaoan_tsl/l10n/app_localizations.dart';

/// 公开政策与应用商店列表统一使用的在线隐私政策地址。
const privacyPolicyUrl = 'https://jbksy.cn/xiaoan-privacy.html';
const privacyPolicyUrlEn = 'https://jbksy.cn/xiaoan-privacy-en.html';

/// 按应用界面语言选择对应的公开政策页面。
String privacyPolicyUrlFor(BuildContext context) =>
    Localizations.localeOf(context).languageCode == 'en'
        ? privacyPolicyUrlEn
        : privacyPolicyUrl;

/// 打开在线完整隐私政策网页。
///
/// 支持测试时注入自定义的 [urlLauncher]，调起系统外部应用打开公开政策页面；
/// 若启动失败或系统拦截，向用户弹出 SnackBar 提示。
Future<void> openPrivacyPolicyUrl(
  BuildContext context, {
  Future<bool> Function(Uri url, {LaunchMode mode})? urlLauncher,
}) async {
  final uri = Uri.parse(privacyPolicyUrlFor(context));
  final launcher = urlLauncher ?? launchUrl;
  try {
    if (await launcher(uri, mode: LaunchMode.externalApplication)) {
      return;
    }
  } catch (_) {
    // 调起异常或无浏览器环境时的容错处理。
  }
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.cannotOpenUrlNotice)),
    );
  }
}

/// 隐私政策结构化卡片展示页面。
///
/// 遵循 Material 3 与设计规范，分为：
/// 1. 顶部生效日期徽章与无账号本地化承诺；
/// 2. 五大核心板块：数据存储边界、离线模型推理、语音与分享安全、权限最小化及诊断数据；
/// 3. 底部完整在线隐私政策外链入口。
class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({
    super.key,
    this.urlLauncher,
  });

  /// 外部链接打开器，默认调用 [launchUrl]，方便单元测试模拟跳转。
  final Future<bool> Function(Uri url, {LaunchMode mode})? urlLauncher;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.privacyPolicyLabel),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _PrivacyOverviewCard(
              effectiveDate: l10n.privacyEffectiveDate,
              subtitle: l10n.privacySubtitle,
            ),
            const SizedBox(height: 16),
            _PrivacySectionCard(
              icon: Icons.storage_outlined,
              title: l10n.privacySection1Title,
              content: l10n.privacySection1Content,
            ),
            const SizedBox(height: 12),
            _PrivacySectionCard(
              icon: Icons.memory_outlined,
              title: l10n.privacySection2Title,
              content: l10n.privacySection2Content,
            ),
            const SizedBox(height: 12),
            _PrivacySectionCard(
              icon: Icons.record_voice_over_outlined,
              title: l10n.privacySection3Title,
              content: l10n.privacySection3Content,
            ),
            const SizedBox(height: 12),
            _PrivacySectionCard(
              icon: Icons.security_outlined,
              title: l10n.privacySection4Title,
              content: l10n.privacySection4Content,
            ),
            const SizedBox(height: 12),
            _PrivacySectionCard(
              icon: Icons.analytics_outlined,
              title: l10n.privacySection5Title,
              content: l10n.privacySection5Content,
            ),
            const SizedBox(height: 16),
            _PrivacyExternalLinkCard(
              urlLauncher: urlLauncher,
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

/// 顶部概览承诺与生效日期卡片。
class _PrivacyOverviewCard extends StatelessWidget {
  const _PrivacyOverviewCard({
    required this.effectiveDate,
    required this.subtitle,
  });

  /// 隐私政策生效日期文本。
  final String effectiveDate;

  /// 核心无账号承诺说明。
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return AppPanel(
      tinted: true,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.verified_user_outlined,
                        size: 16,
                        color: scheme.primary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        effectiveDate,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: scheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              subtitle,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurface,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 核心章节结构化卡片，展示单项隐私条款。
class _PrivacySectionCard extends StatelessWidget {
  const _PrivacySectionCard({
    required this.icon,
    required this.title,
    required this.content,
  });

  /// 章节主题图标。
  final IconData icon;

  /// 章节标题。
  final String title;

  /// 章节具体说明内容。
  final String content;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return AppPanel(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    icon,
                    size: 20,
                    color: scheme.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              content,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 底部外部完整隐私政策链接卡片。
class _PrivacyExternalLinkCard extends StatelessWidget {
  const _PrivacyExternalLinkCard({
    this.urlLauncher,
  });

  /// 外部链接打开器。
  final Future<bool> Function(Uri url, {LaunchMode mode})? urlLauncher;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = context.l10n;

    return AppPanel(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => openPrivacyPolicyUrl(
                context,
                urlLauncher: urlLauncher,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Icon(
                      Icons.public_outlined,
                      size: 20,
                      color: scheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        privacyPolicyUrlFor(context),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.primary,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () => openPrivacyPolicyUrl(
                context,
                urlLauncher: urlLauncher,
              ),
              icon: const Icon(Icons.open_in_new, size: 18),
              label: Text(l10n.viewFullPrivacyPolicy),
            ),
          ],
        ),
      ),
    );
  }
}
