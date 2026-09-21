import '../utils/app_snack.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/video_settings.dart';
import '../services/settings_service.dart';
import '../theme/app_theme.dart';

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
    _bufferController.text =
        '${context.read<SettingsService>().videoBufferSizeMb}';
    AppSnack.show(context, '缓冲大小已保存，下次播放生效');
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();

    return Scaffold(
      backgroundColor: AppColors.nearBlack,
      appBar: AppBar(title: const Text('视频播放')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            '流式播放',
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(color: AppColors.accent),
          ),
          const SizedBox(height: 4),
          const Text(
            '视频直接流式播放，不下载到本地。',
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
            style: Theme.of(context).textTheme.titleMedium
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
          if (settings.videoLongPress == VideoGestureAction.toggleRate2x) ...[
            const SizedBox(height: 4),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.speed),
              title: const Text('长按临时倍速'),
              subtitle: Text(
                '按住加速到 ${settings.videoLongPressRate.toStringAsFixed(2)}×，松手恢复',
              ),
            ),
            Wrap(
              spacing: 8,
              children: [
                for (final preset in SettingsService.videoLongPressRatePresets)
                  ChoiceChip(
                    label: Text('${preset.toStringAsFixed(2)}×'),
                    selected:
                        (settings.videoLongPressRate - preset).abs() < 0.001,
                    onSelected: (_) => settings.setVideoLongPressRate(preset),
                  ),
              ],
            ),
            Slider(
              value: settings.videoLongPressRate.clamp(
                SettingsService.minVideoRate,
                SettingsService.maxVideoRate,
              ),
              min: SettingsService.minVideoRate,
              max: SettingsService.maxVideoRate,
              divisions: SettingsService.videoRateDivisions,
              label: '${settings.videoLongPressRate.toStringAsFixed(2)}×',
              onChanged: (v) => settings.setVideoLongPressRate(v),
            ),
          ],
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.slow_motion_video),
            title: const Text('默认播放倍速'),
            subtitle: Text(
              '当前 ${settings.videoLastRate.toStringAsFixed(2)}×（范围 ${SettingsService.minVideoRate.toStringAsFixed(1)}×–${SettingsService.maxVideoRate.toStringAsFixed(1)}×）',
            ),
          ),
          Slider(
            value: settings.videoLastRate.clamp(
              SettingsService.minVideoRate,
              SettingsService.maxVideoRate,
            ),
            min: SettingsService.minVideoRate,
            max: SettingsService.maxVideoRate,
            divisions: SettingsService.videoRateDivisions,
            label: '${settings.videoLastRate.toStringAsFixed(2)}×',
            onChanged: (v) => settings.setVideoLastRate(v),
          ),
          const Divider(height: 40),
          Text(
            '字幕',
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(color: AppColors.accent),
          ),
          const SizedBox(height: 4),
          const Text(
            '控件显示时画在控件条上方，隐藏时贴窗口底部。',
            style: TextStyle(color: AppColors.secondaryText, fontSize: 12),
          ),
          const SizedBox(height: 8),
          SegmentedButton<VideoSubtitlePosition>(
            showSelectedIcon: false,
            segments: [
              for (final p in VideoSubtitlePosition.values)
                ButtonSegment(value: p, label: Text(p.labelZh)),
            ],
            selected: {settings.videoSubtitlePosition},
            onSelectionChanged: (sel) =>
                settings.setVideoSubtitlePosition(sel.first),
          ),
          if (settings.videoSubtitlePosition ==
              VideoSubtitlePosition.visible) ...[
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.format_size),
              title: const Text('字幕大小'),
              subtitle: Text(
                '当前 ${settings.videoSubtitleFontSize.toStringAsFixed(0)} sp'
                '（范围 ${SettingsService.minVideoSubtitleFontSize.toStringAsFixed(0)}–'
                '${SettingsService.maxVideoSubtitleFontSize.toStringAsFixed(0)} sp）',
              ),
            ),
            Wrap(
              spacing: 8,
              children: [
                for (final preset
                    in SettingsService.videoSubtitleFontSizePresets)
                  ChoiceChip(
                    label: Text(preset.toStringAsFixed(0)),
                    selected:
                        (settings.videoSubtitleFontSize - preset).abs() < 0.001,
                    onSelected: (_) =>
                        settings.setVideoSubtitleFontSize(preset),
                  ),
              ],
            ),
            Slider(
              value: settings.videoSubtitleFontSize.clamp(
                SettingsService.minVideoSubtitleFontSize,
                SettingsService.maxVideoSubtitleFontSize,
              ),
              min: SettingsService.minVideoSubtitleFontSize,
              max: SettingsService.maxVideoSubtitleFontSize,
              divisions: 30,
              label: '${settings.videoSubtitleFontSize.toStringAsFixed(0)} sp',
              onChanged: (v) => settings.setVideoSubtitleFontSize(v),
            ),
          ],
          const Divider(height: 40),
          Text(
            '播放行为',
            style: Theme.of(context).textTheme.titleMedium
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
