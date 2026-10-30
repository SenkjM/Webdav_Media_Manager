import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../providers/app_state.dart';
import '../services/dlna_cast_service.dart';
import '../utils/app_snack.dart';
import 'dlna_compat_sheet.dart';

// ─────────────────────────────────────────────────────────────
//  常量
// ─────────────────────────────────────────────────────────────

/// 气泡距屏幕右边缘的默认距离
const double _kDefaultRight = 12.0;

/// 气泡距屏幕底部的默认距离（MiniPlayer 高度 + 安全区约 80 px）
const double _kDefaultBottom = 80.0;

/// 气泡最大宽度
const double _kBubbleMaxWidth = 280.0;

/// 展开态进度条轨道高度
const double _kTrackHeight = 4.0;

/// 展开态进度条拖动热区高度
const double _kTrackHitHeight = 20.0;

/// 展开态进度条拇指尺寸
const double _kThumbSize = 16.0;

// ─────────────────────────────────────────────────────────────
//  主 Widget
// ─────────────────────────────────────────────────────────────

/// 全局浮动 DLNA 投屏控制栏。
///
/// 由 home_shell.dart 通过 [Overlay] 插入，本身用 [Stack] + [Positioned]
/// 覆盖整个屏幕。
///
/// * `DlnaCastState.idle` → 返回 [SizedBox.shrink()]，不占位。
/// * 非 idle → 根据 [_expanded] 在「右下角气泡」与「底部全宽卡片」间切换。
class DlnaCastBar extends StatefulWidget {
  const DlnaCastBar({super.key});

  @override
  State<DlnaCastBar> createState() => _DlnaCastBarState();
}

class _DlnaCastBarState extends State<DlnaCastBar>
    with SingleTickerProviderStateMixin {
  // ── 状态 ────────────────────────────────────────────────────
  /// 是否处于展开态
  bool _expanded = false;

  /// 气泡位置（右侧、底部距屏幕边缘）
  double _right = _kDefaultRight;
  double _bottom = _kDefaultBottom;

  /// 进度条拖动中的覆盖值（null = 未拖动，显示服务的真实进度）
  double? _seekOverride;
  Timer? _seekSettle;

  static const _seekSettleTimeout = Duration(milliseconds: 900);
  static const _seekSettleTolerance = 0.02;

  // ── 动画 ────────────────────────────────────────────────────
  late final AnimationController _expandCtrl;
  late final Animation<double> _expandAnim;

  @override
  void initState() {
    super.initState();
    _expandCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _expandAnim = CurvedAnimation(
      parent: _expandCtrl,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
  }

  @override
  void dispose() {
    _seekSettle?.cancel();
    _expandCtrl.dispose();
    super.dispose();
  }

  // ── 展开 / 收起 ─────────────────────────────────────────────
  void _toggleExpand() {
    setState(() {
      _expanded = !_expanded;
      if (_expanded) {
        _expandCtrl.forward();
      } else {
        _expandCtrl.reverse();
      }
    });
  }

  void _collapse() {
    if (!_expanded) return;
    setState(() {
      _expanded = false;
      _expandCtrl.reverse();
    });
  }

  // ── 气泡拖动 ────────────────────────────────────────────────
  void _onBubblePanUpdate(DragUpdateDetails d) {
    setState(() {
      // right / bottom 是距边缘的距离，手指右移 → right 减少
      _right = (_right - d.delta.dx).clamp(0.0, double.infinity);
      _bottom = (_bottom - d.delta.dy).clamp(0.0, double.infinity);
    });
  }

  void _onBubblePanEnd(DragEndDetails d, double screenWidth) {
    // 松开时吸附到左侧或右侧
    final centerX = screenWidth - _right - _kBubbleMaxWidth / 2;
    setState(() {
      if (centerX < screenWidth / 2) {
        // 吸附左侧：right 较大
        _right = screenWidth - _kBubbleMaxWidth - 12;
      } else {
        // 吸附右侧
        _right = 12;
      }
    });
  }

  // ── 进度条拖动 ───────────────────────────────────────────────
  void _seekDragTo(double dx, double width) {
    if (width <= 0) return;
    setState(() => _seekOverride = (dx / width).clamp(0.0, 1.0));
  }

  void _seekRelease(DlnaCastService cast) {
    final value = _seekOverride;
    if (value == null) return;
    final dur = cast.duration;
    if (dur != null && dur.inMilliseconds > 0) {
      cast.seekTo(Duration(
        milliseconds: (dur.inMilliseconds * value).round(),
      ));
    }
    _seekSettle?.cancel();
    _seekSettle = Timer(_seekSettleTimeout, () {
      if (!mounted) return;
      setState(() => _seekOverride = null);
    });
  }

  /// 实时进度（服务值或拖动覆盖值）。
  /// 当服务已回报的进度足够接近 seek 目标时，提前清除 override，
  /// 避免 settle 超时期间进度条视觉停顿。
  double _progress(DlnaCastService cast) {
    final dur = cast.duration;
    final held = _seekOverride;
    if (held != null) {
      if (dur != null && dur.inMilliseconds > 0) {
        final real =
            cast.position.inMilliseconds / dur.inMilliseconds;
        if ((real - held).abs() <= _seekSettleTolerance) {
          _seekSettle?.cancel();
          _seekOverride = null;
          return real.clamp(0.0, 1.0);
        }
      }
      return held;
    }
    if (dur == null || dur.inMilliseconds <= 0) return 0.0;
    return (cast.position.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0);
  }

  // ── 时间格式化 ───────────────────────────────────────────────
  static String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:'
          '${m.toString().padLeft(2, '0')}:'
          '${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:'
        '${s.toString().padLeft(2, '0')}';
  }

  // ─────────────────────────────────────────────────────────────
  //  Build
  // ─────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final cast = context.watch<DlnaCastService>();

    // idle 时不显示任何内容
    if (cast.state == DlnaCastState.idle) {
      return const SizedBox.shrink();
    }

    return Stack(
      children: [
        if (_expanded)
          // 展开态：底部全宽卡片，覆盖 MiniPlayer
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _buildExpandedBar(context, cast),
          )
        else
          // 收起态：右下角可拖动气泡
          Positioned(
            right: _right,
            bottom: _bottom,
            child: _buildCollapsedBubble(context, cast),
          ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────
  //  收起态气泡
  // ─────────────────────────────────────────────────────────────
  Widget _buildCollapsedBubble(BuildContext context, DlnaCastService cast) {
    final scheme = Theme.of(context).colorScheme;
    final screenWidth = MediaQuery.of(context).size.width;

    final isError = cast.state == DlnaCastState.error;
    final bubbleColor =
        isError ? scheme.errorContainer : scheme.primaryContainer;
    final iconColor =
        isError ? scheme.onErrorContainer : scheme.onPrimaryContainer;

    // 进度 0..1（只读，不可拖动）
    final progress = _progress(cast);

    return GestureDetector(
      onPanUpdate: _onBubblePanUpdate,
      onPanEnd: (d) => _onBubblePanEnd(d, screenWidth),
      onTap: _toggleExpand,
      child: Material(
        color: bubbleColor,
        borderRadius: BorderRadius.circular(16),
        elevation: 8,
        shadowColor: Colors.black38,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── 投屏图标（错误时加红点角标） ──────────────
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(
                    isError ? Icons.cast : Icons.cast_connected,
                    color: iconColor,
                    size: 24,
                  ),
                  if (isError)
                    Positioned(
                      right: -3,
                      top: -3,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: scheme.error,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: bubbleColor,
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),
                ],
              ),

              const SizedBox(height: 6),

              // ── 只读细进度条 ──────────────────────────────
              SizedBox(
                width: 28,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: isError ? 0 : progress,
                    minHeight: 3,
                    backgroundColor:
                        iconColor.withValues(alpha: 0.25),
                    color: isError ? scheme.error : iconColor,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  //  展开态底部卡片
  // ─────────────────────────────────────────────────────────────
  Widget _buildExpandedBar(BuildContext context, DlnaCastService cast) {
    final scheme = Theme.of(context).colorScheme;
    final isError = cast.state == DlnaCastState.error;
    final isBuffering = cast.playbackState == DlnaPlaybackState.buffering;
    final hasPrev = cast.queue?.hasPrevious ?? false;
    final hasNext = cast.queue?.hasNext ?? false;
    final dur = cast.duration;
    final hasDuration = dur != null && dur.inMilliseconds > 0;

    // 当前进度
    final progress = _progress(cast);
    final posText = _fmt(cast.position);
    final durText = hasDuration ? _fmt(dur) : '--:--';

    return FadeTransition(
      opacity: _expandAnim,
      child: Material(
        color: scheme.surfaceContainerHigh,
        elevation: 12,
        shadowColor: Colors.black38,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── 第一行：设备名 + 文件名 + 断开按钮 ──────────
                Row(
                  children: [
                    Icon(
                      Icons.cast_connected,
                      color: scheme.primary,
                      size: 18,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      cast.renderer?.friendlyName ?? '未知设备',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: scheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        cast.currentItem?.name ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton.icon(
                      onPressed: () {
                        _collapse();
                        cast.stop();
                      },
                      icon: Icon(
                        Icons.cast_connected,
                        size: 16,
                        color: scheme.error,
                      ),
                      label: Text(
                        '断开',
                        style: TextStyle(color: scheme.error, fontSize: 13),
                      ),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 10),

                if (isError)
                  // ── 错误状态：可复制的详细错误 + 兼容性设置跳转 ──
                  _ErrorDetail(
                    error: cast.error ?? '投屏出错',
                    renderer: cast.renderer,
                  )
                else ...[
                  // ── 进度条行 ────────────────────────────────────
                  Row(
                    children: [
                      Text(
                        posText,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _ExpandedProgressBar(
                          progress: progress,
                          enabled: hasDuration,
                          onSeekStart: (v) =>
                              setState(() => _seekOverride = v),
                          onSeekUpdate: (dx, w) => _seekDragTo(dx, w),
                          onSeekEnd: () => _seekRelease(cast),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        durText,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 8),

                  // ── 控制按钮行 ─────────────────────────────────
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // 上一首（无则占位）
                      if (hasPrev)
                        IconButton(
                          icon: Icon(
                            Icons.skip_previous_rounded,
                            color: scheme.onSurface,
                          ),
                          onPressed: () => cast.playPrevious(),
                          tooltip: '上一首',
                        )
                      else
                        const SizedBox(width: 48),

                      // 后退 10 秒
                      IconButton(
                        icon: Icon(
                          Icons.replay_10_rounded,
                          color: scheme.onSurface,
                        ),
                        onPressed: hasDuration
                            ? () => cast.seekTo(
                                  Duration(
                                    milliseconds: (cast.position.inMilliseconds -
                                            10000)
                                        .clamp(0, dur.inMilliseconds),
                                  ),
                                )
                            : null,
                        tooltip: '后退 10 秒',
                      ),

                      // 播放/暂停（大按钮）
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: SizedBox(
                          width: 56,
                          height: 56,
                          child: isBuffering
                              ? Padding(
                                  padding: const EdgeInsets.all(14),
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: scheme.primary,
                                  ),
                                )
                              : FilledButton(
                                  style: FilledButton.styleFrom(
                                    shape: const CircleBorder(),
                                    backgroundColor: scheme.primary,
                                    padding: EdgeInsets.zero,
                                  ),
                                  onPressed: () => cast.playPause(),
                                  child: Icon(
                                    cast.playbackState ==
                                            DlnaPlaybackState.playing
                                        ? Icons.pause_rounded
                                        : Icons.play_arrow_rounded,
                                    color: scheme.onPrimary,
                                    size: 28,
                                  ),
                                ),
                        ),
                      ),

                      // 前进 10 秒
                      IconButton(
                        icon: Icon(
                          Icons.forward_10_rounded,
                          color: scheme.onSurface,
                        ),
                        onPressed: hasDuration
                            ? () => cast.seekTo(
                                  Duration(
                                    milliseconds: (cast.position.inMilliseconds +
                                            10000)
                                        .clamp(0, dur.inMilliseconds),
                                  ),
                                )
                            : null,
                        tooltip: '前进 10 秒',
                      ),

                      // 下一首（无则占位）
                      if (hasNext)
                        IconButton(
                          icon: Icon(
                            Icons.skip_next_rounded,
                            color: scheme.onSurface,
                          ),
                          onPressed: () => cast.playNext(),
                          tooltip: '下一首',
                        )
                      else
                        const SizedBox(width: 48),
                    ],
                  ),

                  const SizedBox(height: 4),

                  // ── 功能行：队列 + 兼容模式 ────────────────────
                  Row(
                    children: [
                      // 队列数量（若有队列）
                      if (cast.queue != null) ...[
                        TextButton.icon(
                          onPressed: () => _DlnaQueueSheet.show(context, cast),
                          icon: Icon(
                            Icons.queue_music,
                            size: 16,
                            color: scheme.onSurfaceVariant,
                          ),
                          label: Text(
                            '队列 ${cast.queue!.tracks.length} 首',
                            style: TextStyle(
                              color: scheme.onSurfaceVariant,
                              fontSize: 13,
                            ),
                          ),
                          style: TextButton.styleFrom(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 8),
                            minimumSize: Size.zero,
                            tapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                        const SizedBox(width: 4),
                      ],

                      const Spacer(),
                    ],
                  ),


                // 收起按钮
                Align(
                  alignment: Alignment.center,
                  child: GestureDetector(
                    onTap: _collapse,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: scheme.onSurfaceVariant,
                        size: 24,
                      ),
                    ),
                  ),
                ),
                ],  // else ...[
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  展开态进度条
// ─────────────────────────────────────────────────────────────

/// 展开态宽进度条，支持拖动 seek。
class _ExpandedProgressBar extends StatelessWidget {
  const _ExpandedProgressBar({
    required this.progress,
    required this.enabled,
    required this.onSeekStart,
    required this.onSeekUpdate,
    required this.onSeekEnd,
  });

  /// 当前进度 0..1
  final double progress;

  /// false 时不允许拖动（duration 未知）
  final bool enabled;

  /// 拖动开始时的初始 fraction
  final ValueChanged<double> onSeekStart;

  /// 拖动更新：dx 为手指在轨道上的 x，width 为轨道总宽
  final void Function(double dx, double width) onSeekUpdate;

  /// 拖动结束
  final VoidCallback onSeekEnd;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final value = progress.clamp(0.0, 1.0);

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final inset =
            (_kTrackHitHeight - _kTrackHeight) / 2;

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: enabled
              ? (d) => onSeekStart(
                    (d.localPosition.dx / width).clamp(0.0, 1.0),
                  )
              : null,
          onHorizontalDragUpdate: enabled
              ? (d) => onSeekUpdate(d.localPosition.dx, width)
              : null,
          onHorizontalDragEnd: enabled ? (_) => onSeekEnd() : null,
          onHorizontalDragCancel: enabled ? onSeekEnd : null,
          child: SizedBox(
            height: _kTrackHitHeight,
            width: double.infinity,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // 轨道
                Positioned.fill(
                  top: inset,
                  bottom: inset,
                  child: LinearProgressIndicator(
                    value: value,
                    minHeight: _kTrackHeight,
                    backgroundColor: scheme.outline.withValues(alpha: 0.4),
                    color: scheme.primary,
                    borderRadius: BorderRadius.circular(_kTrackHeight / 2),
                  ),
                ),

                // 拇指（仅展开态进度条常驻显示）
                Positioned(
                  left: (width * value) - _kThumbSize / 2,
                  top: (_kTrackHitHeight - _kThumbSize) / 2,
                  child: Container(
                    width: _kThumbSize,
                    height: _kThumbSize,
                    decoration: BoxDecoration(
                      color: scheme.primary,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: scheme.primary.withValues(alpha: 0.3),
                          blurRadius: 4,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  错误详情（可一键复制）
// ─────────────────────────────────────────────────────────────

class _ErrorDetail extends StatelessWidget {
  const _ErrorDetail({required this.error, this.renderer});

  final String error;
  final DlnaRenderer? renderer;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: scheme.errorContainer.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: scheme.error.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.error_outline, color: scheme.error, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: SelectableText(
                    error,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onErrorContainer,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  iconSize: 16,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  icon: Icon(Icons.copy, color: scheme.error, size: 14),
                  tooltip: '复制错误信息',
                  onPressed: () {
                    // Flutter 3.x Clipboard
                    // ignore: deprecated_member_use
                    Clipboard.setData(ClipboardData(text: error));
                    AppSnack.show(context, '已复制到剪贴板');
                  },
                ),
              ],
            ),
            // Gap 2: 跳转到兼容性设置按钮
            if (renderer != null) ...[
              const SizedBox(height: 8),
              FilledButton.tonalIcon(
                onPressed: () async {
                  final appState = context.read<AppState>();
                  await DlnaCompatSheet.show(
                    context,
                    renderer!,
                    appState.dmrPrefs,
                  );
                },
                icon: Icon(Icons.tune, size: 16),
                label: Text('兼容性设置'),
                style: FilledButton.styleFrom(
                  minimumSize: Size(double.infinity, 36),
                  backgroundColor: scheme.error.withValues(alpha: 0.1),
                  foregroundColor: scheme.error,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  队列底部面板
// ─────────────────────────────────────────────────────────────

class _DlnaQueueSheet extends StatelessWidget {
  const _DlnaQueueSheet._();

  static void show(BuildContext context, DlnaCastService cast) {
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => ChangeNotifierProvider.value(
        value: cast,
        child: const _DlnaQueueSheet._(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cast = context.watch<DlnaCastService>();
    final scheme = Theme.of(context).colorScheme;
    final queue = cast.queue;

    if (queue == null) {
      return const SizedBox.shrink();
    }

    final tracks = queue.tracks;
    final currentIndex = queue.index;

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 标题栏
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Icon(Icons.queue_music, color: scheme.primary, size: 20),
                const SizedBox(width: 8),
                Text(
                  '投屏队列 · ${tracks.length} 首',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // 列表
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: tracks.length,
              itemBuilder: (context, i) {
                final item = tracks[i];
                final isCurrent = i == currentIndex;
                return ListTile(
                  leading: Icon(
                    isCurrent ? Icons.play_arrow_rounded : Icons.video_file,
                    color: isCurrent ? scheme.primary : scheme.onSurfaceVariant,
                    size: 20,
                  ),
                  title: Text(
                    item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isCurrent ? scheme.primary : null,
                      fontWeight: isCurrent ? FontWeight.w600 : null,
                    ),
                  ),
                  onTap: () {
                    cast.playTrack(i);
                    Navigator.of(context).pop();
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
