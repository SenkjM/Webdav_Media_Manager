import 'package:flutter/material.dart';

/// 投屏中切换字幕的二次确认弹窗。
///
/// 字幕改为「投屏开始时一次性全量投送」后，播放中切换字幕不再增量更新，而是
/// 让渲染器重新加载播放并二次 seek 回原播放位置，画面会短暂中断（契约
/// subtitle-lane-and-hwdecode §D）。所以只在投屏服务 `isActive` 的会话里让用户
/// 确认；预热 / 预览阶段直接切换，不弹。
///
/// 文案沿用本目录 DLNA 组件的惯例：直接写中文，不新增 l10n key。
class DlnaSubtitleSwitchDialog {
  const DlnaSubtitleSwitchDialog._();

  /// 弹出确认框：点「继续切换」返回 true；取消、点外部关闭或返回键都返回 false。
  static Future<bool> show(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('切换字幕'),
        content: const Text('切换字幕会让投屏重新加载当前播放，并自动跳回原播放位置，画面可能短暂中断。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('继续切换'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }
}
