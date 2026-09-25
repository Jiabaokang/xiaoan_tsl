import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

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
    final title = kind == InfoKind.privacy ? '隐私政策' : '关于小安翻译';
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: kind == InfoKind.privacy
            ? const [
                Text('小安翻译无需注册或登录。输入文字、翻译结果、历史、收藏和设置保存在本机；Android 版本已关闭系统备份。'),
                SizedBox(height: 14),
                Text(
                  '语言识别和翻译在设备端完成。首次使用某种语言时，应用会通过 Google ML Kit 下载语言模型。应用不把输入文字上传到自有服务器。',
                ),
                SizedBox(height: 14),
                Text('朗读由设备安装的语音引擎处理；复制或分享后，文字由你选择的系统功能或第三方应用处理。'),
                SizedBox(height: 14),
                Text('应用不申请麦克风、相机、位置或通讯录权限。'),
                SizedBox(height: 14),
                Text(
                  'Google ML Kit 可能向 Google 发送设备、应用及性能等诊断数据；完整的数据处理与删除说明请查看公开隐私政策。',
                ),
                SizedBox(height: 14),
                _PrivacyPolicyLink(),
              ]
            : [
                const Text('小安翻译使用设备端语言识别、翻译和系统语音朗读。'),
                const SizedBox(height: 14),
                const Text('翻译能力由 Google ML Kit 提供。'),
                const SizedBox(height: 14),
                FutureBuilder<PackageInfo>(
                  future: PackageInfo.fromPlatform(),
                  builder: (context, snapshot) => Text(
                    snapshot.hasData
                        ? '版本 ${snapshot.data!.version} (${snapshot.data!.buildNumber})'
                        : '正在读取版本信息…',
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
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('无法打开网页，请在浏览器输入页面上的网址')));
        }
      },
      child: const Text(privacyPolicyUrl),
    ),
  );
}
