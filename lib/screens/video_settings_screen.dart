import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/video_settings.dart';
import '../services/settings_service.dart';
import '../theme/app_theme.dart';
import 'home_shell.dart';

/// Video playback settings (WebDAV streaming parameters, gestures, background
/// playback & picture-in-picture). Reachable from the main Settings list.
class VideoSettingsScreen extends StatefulWidget {
  const VideoSettingsScreen({super.key});

  @override
  State<VideoSettingsScreen> createState() => _VideoSettingsScreenState();
}

class _VideoSettingsScreenState extends State<VideoSettingsScreen> {
  late final TextEditingController _bufferController;

  @override
  void initState() {
    super.initState();
    _bufferController = TextEditingController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _bufferController.text =
          '${context.read<SettingsService>().videoBufferSizeMb}';
    });
  }

  @override
  void dispose() {
    _bufferController.dispose();
    super.dispose();
  }

  Future<void> _applyBuffer() async {
    final mb = int.tryParse(_bufferController.text.trim());
    if (mb == null) return;
    await context.read<SettingsService>().setVideoBufferSizeMb(mb);
    if (!mounted) return;
    _bufferController.text = '${context.read<SettingsService>().videoBufferSizeMb}';
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('缓冲大小已保存，下次播放生效')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();

    return Scaffold(
      backgroundColor: AppColors.nearBlack,
      appBar: AppBar(
        leading: const DrawerMenuButton(),
        title: const Text('视频播放'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            '流式播放',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(color: AppColors.accent),
          ),
          const SizedBox(height: 4),
          const Text(
            '视频通过 media_kit 直接流式播放 WebDAV 文件，不下载到本地。',
            style: TextStyle(color: AppColors.secondaryText, fontSize: 12),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.memory_outlined),
            title: const Text('硬件解码'),
            subtitle: const Text('关闭后改用软件解码，个别设备更稳定'),
            value: settings.videoHardwareDecoding,
            onChanged: (v) => settings.setVideoHardwareDecoding(v),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.storage_outlined),
            title: const Text('缓冲大小'),
            subtitle: Text(
              '当前 ${settings.videoBufferSizeMb} MB（范围 '
              '${SettingsService.minVideoBufferMb}–'
              '${SettingsService.maxVideoBufferMb} MB）',
            ),
          ),
          Row(
            children: [
              SizedBox(
                width: 140,
                child: TextField(
                  controller: _bufferController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    isDense: true,
                    labelText: '缓冲 (MB)',
                    border: OutlineInputBorder(),
                  ),
                  onEditingComplete: _applyBuffer,
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.tonal(
                onPressed: _applyBuffer,
                child: const Text('应用'),
              ),
            ],
          ),
          const Divider(height: 40),
          Text(
            '手势',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(color: AppColors.accent),
          ),
          const SizedBox(height: 8),
          _gestureTile(
            label: '左侧双击',
            value: settings.videoLeftDoubleTap,
            onChanged: (v) => settings.setVideoLeftDoubleTap(v),
          ),
          _gestureTile(
            label: '右侧双击',
            value: settings.videoRightDoubleTap,
            onChanged: (v) => settings.setVideoRightDoubleTap(v),
          ),
          _gestureTile(
            label: '长按',
            value: settings.videoLongPress,
            onChanged: (v) => settings.setVideoLongPress(v),
          ),
          const Divider(height: 40),
          Text(
            '播放行为',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(color: AppColors.accent),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.headset_outlined),
            title: const Text('后台播放'),
            subtitle: const Text('离开播放器后继续播放声音'),
            value: settings.videoBackgroundPlayback,
            onChanged: (v) => settings.setVideoBackgroundPlayback(v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.picture_in_picture_alt_outlined),
            title: const Text('画中画（小窗）'),
            subtitle: const Text('播放控件中显示画中画按钮（Android 8+）'),
            value: settings.videoPipEnabled,
            onChanged: (v) => settings.setVideoPipEnabled(v),
          ),
        ],
      ),
    );
  }

  Widget _gestureTile({
    required String label,
    required VideoGestureAction value,
    required ValueChanged<VideoGestureAction> onChanged,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.touch_app_outlined),
      title: Text(label),
      trailing: DropdownButton<VideoGestureAction>(
        value: value,
        items: [
          for (final a in VideoGestureAction.values)
            DropdownMenuItem(value: a, child: Text(a.labelZh)),
        ],
        onChanged: (v) {
          if (v != null) onChanged(v);
        },
      ),
    );
  }
}
