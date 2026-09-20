import 'package:flutter/material.dart';

import '../models/webdav_item.dart';

class TrackStatusChip extends StatelessWidget {
  const TrackStatusChip({super.key, required this.state, this.progress});

  final TrackUiState state;
  final double? progress;

  @override
  Widget build(BuildContext context) {
    final (label, color, icon) = switch (state) {
      TrackUiState.queued => ('排队', Colors.blueGrey, Icons.schedule),
      TrackUiState.downloading => (
          '下载中',
          Colors.orange,
          Icons.downloading,
        ),
      TrackUiState.ready => ('就绪', Colors.green, Icons.check_circle_outline),
      TrackUiState.playing => ('播放中', Colors.deepPurple, Icons.equalizer),
      TrackUiState.error => ('错误', Colors.red, Icons.error_outline),
    };

    return Chip(
      avatar: Icon(icon, size: 16, color: color),
      label: Text(
        state == TrackUiState.downloading && progress != null
            ? '$label ${(progress! * 100).toStringAsFixed(0)}%'
            : label,
        style: const TextStyle(fontSize: 12),
      ),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      backgroundColor: color.withValues(alpha: 0.12),
      side: BorderSide.none,
    );
  }
}
