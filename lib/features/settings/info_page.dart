import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

// 设置页说明内容的类型。
enum InfoKind { privacy, about }

// 显示应用隐私边界和从安装包读取的版本信息。
class InfoPage extends StatelessWidget {
  const InfoPage({super.key, required this.kind});

  final InfoKind kind;

  @override
  Widget build(BuildContext context) {
    final title = kind == InfoKind.privacy ? '隐私说明' : '关于小安翻译';
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
