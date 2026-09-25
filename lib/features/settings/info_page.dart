import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:xiaoan_tsl/l10n/app_localizations.dart';

// 公开政策与 Google Play 商店列表使用同一地址。
const privacyPolicyUrl = 'https://jbksy.cn/xiaoan-privacy.html';

// 设置页说明内容的类型。
enum InfoKind { privacy, about }

// 显示应用隐私边界和从安装包读取的版本信息。
class InfoPage extends StatelessWidget {
  const InfoPage({super.key, required this.kind});

  final InfoKind kind;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final title =
        kind == InfoKind.privacy ? l10n.privacyPolicyLabel : l10n.aboutAppLabel;

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: kind == InfoKind.privacy
            ? [
                Text(l10n.privacyParagraph1),
                const SizedBox(height: 14),
                Text(l10n.privacyParagraph2),
                const SizedBox(height: 14),
                Text(l10n.privacyParagraph3),
                const SizedBox(height: 14),
                Text(l10n.privacyParagraph4),
                const SizedBox(height: 14),
                Text(l10n.privacyParagraph5),
                const SizedBox(height: 14),
                const _PrivacyPolicyLink(),
              ]
            : [
                Text(l10n.aboutParagraph1),
                const SizedBox(height: 14),
                Text(l10n.aboutParagraph2),
                const SizedBox(height: 14),
                FutureBuilder<PackageInfo>(
                  future: PackageInfo.fromPlatform(),
                  builder: (context, snapshot) => Text(
                    snapshot.hasData
                        ? l10n.versionLabel(
                            snapshot.data!.version,
                            snapshot.data!.buildNumber,
                          )
                        : l10n.loadingVersion,
                  ),
                ),
              ],
      ),
    );
  }
}

// 点击后用系统浏览器打开公开的完整隐私政策。
class _PrivacyPolicyLink extends StatelessWidget {
  const _PrivacyPolicyLink();

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.centerLeft,
        child: TextButton(
          onPressed: () async {
            try {
              if (await launchUrl(
                Uri.parse(privacyPolicyUrl),
                mode: LaunchMode.externalApplication,
              )) {
                return;
              }
            } catch (_) {
              // 无浏览器或系统拒绝打开时，向用户显示可复制的网址。
            }
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(context.l10n.cannotOpenUrlNotice)),
              );
            }
          },
          child: const Text(privacyPolicyUrl),
        ),
      );
}
