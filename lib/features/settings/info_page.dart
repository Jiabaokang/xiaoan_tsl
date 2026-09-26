import 'package:flutter/material.dart';

import 'package:xiaoan_tsl/features/settings/about_page.dart';
import 'package:xiaoan_tsl/features/settings/privacy_policy_page.dart';

export 'about_page.dart' show AboutPage;
export 'open_source_licenses_page.dart' show OpenSourceLicensesPage;
export 'privacy_policy_page.dart' show privacyPolicyUrl, PrivacyPolicyPage;

/// 设置页说明内容的类型兼容枚举。
enum InfoKind {
  /// 隐私政策类型。
  privacy,

  /// 关于应用类型。
  about,
}

/// 兼容旧版入口的说明信息页面转发层。
///
/// 保留历史 [InfoPage] 类签名与路由兼容性，根据传入的 [kind]
/// 自动转发呈现结构化卡片式的 [PrivacyPolicyPage] 或品牌化的 [AboutPage]，
/// 保证已有调用代码及测试平滑过渡无破坏。
class InfoPage extends StatelessWidget {
  /// 构造兼容转发页面实例。
  const InfoPage({super.key, required this.kind});

  /// 说明页面类型（隐私政策或关于页面）。
  final InfoKind kind;

  @override
  Widget build(BuildContext context) {
    return kind == InfoKind.privacy
        ? const PrivacyPolicyPage()
        : const AboutPage();
  }
}
