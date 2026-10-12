import 'package:flutter/material.dart';

import 'media_library_settings_screen.dart';

/// 音频流式设置已并入媒体库设置；保留路由以免旧入口 404。
class AudioStreamSettingsScreen extends StatelessWidget {
  const AudioStreamSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) => const MediaLibrarySettingsScreen();
}
