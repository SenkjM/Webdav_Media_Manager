import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../theme/app_theme.dart';

class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  String _versionLabel = '…';

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((info) {
      if (!mounted) return;
      setState(() {
        _versionLabel = '${info.version}+${info.buildNumber}';
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.nearBlack,
      appBar: AppBar(title: const Text('关于')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            'Webdav Media Manager',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            '版本 $_versionLabel',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: AppColors.accent,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            'CI 预发布写入 versionName（含短 hash）与递增 versionCode，可覆盖安装。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          const Text(
            '浏览网盘目录，下载到本地缓存后播放。',
          ),
          const SizedBox(height: 24),
          Text('作者与致谢', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          const Text('实现：Grok Bot'),
          const Text('创意与需求框架：SenkjM'),
          const SizedBox(height: 24),
          Text('许可证', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          const Text(
            '本项目采用 GNU Affero General Public License v3.0（AGPL-3.0）授权。\n\n'
            '你可以自由使用、修改与分发本软件，但若发布修改版，或通过网络提供基于本软件的服务，'
            '必须按 AGPL-3.0 公开对应完整源代码。完整文本见仓库 LICENSE 文件。',
          ),
          const SizedBox(height: 24),
          Text(
            'https://github.com/SenkjM/WEBDAV-music-player',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
