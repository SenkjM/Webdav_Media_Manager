import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../providers/app_state.dart';
import '../services/dlna_cast_service.dart';
import '../utils/app_snack.dart';
import 'dlna_compat_sheet.dart';
import 'dlna_subtitle_sheet.dart';

// ─────────────────────────────────────────────────────────────
//  常量
// ─────────────────────────────────────────────────────────────

/// 收起态气泡尺寸（宽 = 进度条 28 + 左右内边距 20；
/// 高 = 图标 24 + 间距 6 + 进度条 3 + 上下内边距 18）。
/// 用于把首次出现的小窗精确摆在屏幕右侧、垂直居中。
const double _kCollapsedBubbleWidth = 48.0;
const double _kCollapsedBubbleHeight = 51.0;

/// 收起态小窗距屏幕左右边缘的安全边距（首现位置与拖动吸附共用）。
const double _kCollapsedBubbleEdge = 12.0;

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
/// * 非 idle → 根据 [_expanded] 在「可拖动悬浮小窗」与「底部全宽卡片」间切换。
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
  double _right = 0;
  double _bottom = 0;

  /// 本次会话是否已按屏幕尺寸算过小窗初始位置（会话结束后复位）。
  bool _bubblePositionInitialized = false;

  /// 服务层会话复位监听：进入设备搜索 / 停止投屏时把本地 UI 一起收回初始值。
  DlnaCastService? _cast;

  /// 进度条拖动中的覆盖值（null = 未拖动，显示服务的真实进度）
  double? _seekOverride;
  Timer? _seekSettle;

  /// 拖动结束后进度条保持新位置的时长。
  ///
  /// 渲染器收到 Seek 后要重新拉播放列表并重启一段转码作业（约 1 s 节流 +
  /// 缓冲），远长于旧的 900 ms；提前清掉覆盖值会让进度条「弹回定位前的
  /// 位置」。真实位置一旦追平（见 [_progress]）会立即清除，不等这个超时。
  static const _seekSettleTimeout = Duration(seconds: 15);
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
  void didChangeDependencies() {
    super.didChangeDependencies();
    final cast = context.read<DlnaCastService>();
    if (identical(cast, _cast)) return;
    _cast?.removeListener(_onCastChanged);
    _cast = cast..addListener(_onCastChanged);
  }

  @override
  void dispose() {
    _cast?.removeListener(_onCastChanged);
    _cast = null;
    _seekSettle?.cancel();
    _expandCtrl.dispose();
    super.dispose();
  }

  /// 服务层回到 idle（停止投屏 / 进入新的设备搜索）时复位本地 UI 状态。
  ///
  /// 展开态、进度覆盖值与拖动过的气泡位置都属于「上一次会话」，下一次投屏
  /// 必须从小窗的初始位置重新开始，否则搜索面板后面还留着上一次的投屏界面。
  void _onCastChanged() {
    final cast = _cast;
    if (cast == null || cast.state != DlnaCastState.idle) return;
    if (!mounted) return;
    setState(() {
      _expanded = false;
      _expandCtrl.value = 0;
      _autoExpandConsumed = false;
      _bubblePositionInitialized = false;
      _seekSettle?.cancel();
      _seekSettle = null;
      _seekOverride = null;
    });
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

  /// 每段投屏会话只自动展开一次。
  bool _autoExpandConsumed = false;

  /// 点「投送」/ 预热开始 / 出错时自动展开卡面，让预热面板立刻可见。
  ///
  /// 用户手动收起后不再抢回焦点（[_autoExpandConsumed]），直到会话回到 idle。
  /// 这是契约 task-21 §1「点下去立刻进入预热面板」的一半：前半段由服务层
  /// 的乐观 `preparing` 状态提供，这里保证卡面不是一直缩成气泡。
  void _maybeAutoExpand(DlnaCastService cast) {
    if (_autoExpandConsumed || _expanded) return;
    final active = cast.preparing ||
        cast.phase == 'warming' ||
        cast.phase == 'failed' ||
        cast.state == DlnaCastState.error;
    if (!active) return;
    _autoExpandConsumed = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _expanded) return;
      setState(() => _expanded = true);
      _expandCtrl.forward();
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
    // 松开时吸附到左侧或右侧（按小窗真实宽度，不再用最大宽度估算）。
    final centerX = screenWidth - _right - _kCollapsedBubbleWidth / 2;
    setState(() {
      if (centerX < screenWidth / 2) {
        // 吸附左侧：right 较大
        _right = screenWidth - _kCollapsedBubbleWidth - _kCollapsedBubbleEdge;
      } else {
        // 吸附右侧
        _right = _kCollapsedBubbleEdge;
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
      _autoExpandConsumed = false;
      return const SizedBox.shrink();
    }

    _maybeAutoExpand(cast);

    // 收起态小窗第一次出现时贴在屏幕右侧、垂直居中：水平靠边避免挡住画面，
    // 垂直居中避免和底部投屏面板 / MiniPlayer 重叠；同一会话内用户拖过的位置继续保留。
    if (!_bubblePositionInitialized) {
      final size = MediaQuery.sizeOf(context);
      _bubblePositionInitialized = true;
      _right = _kCollapsedBubbleEdge;
      _bottom = ((size.height - _kCollapsedBubbleHeight) / 2)
          .clamp(0.0, double.infinity);
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
          // 收起态：可拖动悬浮小窗（首次出现在屏幕右侧、垂直居中）
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
    // §3 预热阶段：气泡用沙漏图标 + 不确定进度条，提示「正在准备投屏」。
    // 点下投送的瞬间（`preparing`）同样显示，避免会话建立期间看着像卡住。
    final isWarming = cast.phase == 'warming' || cast.preparing;
    final isWarmFailed = cast.phase == 'failed';
    final bubbleColor = isError || isWarmFailed
        ? scheme.errorContainer
        : isWarming
            ? scheme.secondaryContainer
            : scheme.primaryContainer;
    final iconColor = isError || isWarmFailed
        ? scheme.onErrorContainer
        : isWarming
            ? scheme.onSecondaryContainer
            : scheme.onPrimaryContainer;

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
                    isWarmFailed
                        ? Icons.error_outline
                        : isWarming
                            ? Icons.hourglass_top_rounded
                            : (isError ? Icons.cast : Icons.cast_connected),
                    color: iconColor,
                    size: 24,
                  ),
                  if (isError || isWarmFailed)
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
                    value: isError || isWarmFailed
                        ? 0
                        : isWarming
                            ? (cast.playlistReady ? 1.0 : null)
                            : progress,
                    minHeight: 3,
                    backgroundColor:
                        iconColor.withValues(alpha: 0.25),
                    color: isError || isWarmFailed
                        ? scheme.error
                        : iconColor,
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
    final isWarmFailed = cast.phase == 'failed';
    // §3 预热：`phase == "warming"` 只测速 + 本地生成播放列表，暂不投送；
    // `phase == "failed"` 显示转码失败原因与 §7.5 诊断日志。
    // 旧版 `.so` 不返回 phase（服务已降级为 playing），不会进入这两个分支。
    // `preparing`（task-21 §1）覆盖「已点投送、Rust 还没返回 phase」的窗口。
    final preparing = cast.preparing && !isWarmFailed && !isError;
    final isWarming = cast.phase == 'warming' || preparing;
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
                else if (isWarmFailed)
                  // ── 预热失败（§3 phase:"failed"）：错误全文 + 诊断日志 ──
                  _WarmingFailedPanel(cast: cast, onCollapse: _collapse)
                else if (preparing)
                  // ── 已点投送、会话仍在建立（task-21 §1）：立刻给不确定进度 ──
                  _PreparingPanel(cast: cast, onCollapse: _collapse)
                else if (isWarming)
                  // ── 预热中（§3）：实时测速 / 播放列表就绪 / 投送 ──
                  _WarmingPanel(cast: cast, onCollapse: _collapse)
                else ...[
                  // ── §4 HLS 点播化遥测：转码速度 + 运行状态 ──────
                  _CastTelemetry(cast: cast),

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

                      // 字幕按钮（有候选时显示；纯音频投送没有字幕，隐藏）
                      if (cast.subtitleCandidates.isNotEmpty &&
                          !cast.isAudioOnly)
                        TextButton.icon(
                          onPressed: () =>
                              DlnaSubtitleSheet.show(context, cast),
                          icon: Icon(
                            cast.selectedSubtitle != null
                                ? Icons.subtitles
                                : Icons.subtitles_outlined,
                            size: 16,
                            color: cast.selectedSubtitle != null
                                ? scheme.primary
                                : scheme.onSurfaceVariant,
                          ),
                          label: Text(
                            cast.selectedSubtitle != null ? '字幕' : '字幕',
                            style: TextStyle(
                              color: cast.selectedSubtitle != null
                                  ? scheme.primary
                                  : scheme.onSurfaceVariant,
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
//  HLS 点播化遥测行（契约 hls-vod-transcode-cache §4）
// ─────────────────────────────────────────────────────────────

/// 播放中的转码遥测行：转码速度 + 按需运行状态徽标 + 定位精度提示。
///
/// 只在有数据时渲染：旧版 `.so`（不返回 `run_state` / `alignment`）与直通
/// 会话（无转码）都保持原布局，不额外占一行。
class _CastTelemetry extends StatelessWidget {
  const _CastTelemetry({required this.cast});

  final DlnaCastService cast;

  @override
  Widget build(BuildContext context) {
    // 直通投屏没有转码作业（Rust 仍会报 `run_state:"idle"`），不显示遥测。
    if (cast.provider == 'direct') return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final speed = cast.transcodeSpeed;
    final runState = cast.runState;
    final label = _runStateLabel(runState);
    final showSpeed = speed > 0;
    final drift = cast.driftMs.abs();
    final errorText = runState == 'error' ? cast.errorText : null;
    if (!showSpeed && label == null && drift <= 500 && errorText == null) {
      return const SizedBox.shrink();
    }

    final speedColor = !showSpeed
        ? scheme.onSurfaceVariant
        : speed >= 1
            ? Colors.green.shade600
            : Colors.orange.shade700;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (showSpeed) ...[
                Icon(
                  Icons.speed_rounded,
                  size: 14,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                Text(
                  '${speed.toStringAsFixed(2)}×',
                  style: textTheme.labelSmall?.copyWith(
                    color: speedColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              if (showSpeed && label != null) const SizedBox(width: 8),
              if (label != null) _runStateBadge(context, runState, label),
              if (cast.alignmentLabel.isNotEmpty) ...[
                const SizedBox(width: 8),
                Text(
                  '定位：${cast.alignmentLabel}',
                  style: textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
              const Spacer(),
              if (cast.cacheHits > 0)
                Text(
                  '缓存命中 ${cast.cacheHits}',
                  style: textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
          // 产出位置与计划网格的偏差（正常情况下不超过一个分片）。
          if (drift > 500)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                '产出与网格偏差 ${(drift / 1000).toStringAsFixed(1)} 秒',
                style: textTheme.labelSmall?.copyWith(
                  color: Colors.orange.shade700,
                ),
              ),
            ),
          if (errorText != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                errorText,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: textTheme.labelSmall?.copyWith(
                  color: scheme.error,
                ),
              ),
            ),
        ],
      ),
    );
  }

  String? _runStateLabel(String runState) {
    switch (runState) {
      case 'active':
        return '活动';
      case 'idle':
        return '闲置';
      case 'error':
        return '错误';
      default:
        return null;
    }
  }

  Widget _runStateBadge(BuildContext context, String runState, String label) {
    final scheme = Theme.of(context).colorScheme;
    Color bg;
    Color fg;
    String tooltip;
    switch (runState) {
      case 'active':
        bg = scheme.secondaryContainer;
        fg = scheme.onSecondaryContainer;
        tooltip = '正在转码后续片段';
      case 'idle':
        bg = scheme.surfaceContainerHighest;
        fg = scheme.onSurfaceVariant;
        tooltip = '已追平播放进度，等待播放推进后再转码';
      case 'error':
        bg = scheme.errorContainer;
        fg = scheme.onErrorContainer;
        tooltip = '转码作业出错';
      default:
        bg = scheme.surfaceContainerHighest;
        fg = scheme.onSurfaceVariant;
        tooltip = '';
    }
    return Tooltip(
      message: tooltip,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: fg,
            fontSize: 10,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  会话建立中（乐观预热，契约 task-21 §1）
// ─────────────────────────────────────────────────────────────

/// 已点「投送」、Rust 还没返回 `phase` 时的过渡面板。
///
/// 会话建立（驱动解析、代理启动、时长探测、字幕扫描）可能要数秒；这里立刻
/// 显示不确定进度与「正在准备缓存预热…」，等 Rust 的 `phase:"warming"` /
/// `"playing"` 到达后由服务层自动切走，避免用户对着裸转圈等。
class _PreparingPanel extends StatelessWidget {
  const _PreparingPanel({required this.cast, required this.onCollapse});

  final DlnaCastService cast;
  final VoidCallback onCollapse;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2.2,
                color: scheme.primary,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              '正在准备缓存预热…',
              style: textTheme.titleSmall?.copyWith(
                color: scheme.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          '正在建立投屏会话、探测媒体时长与字幕，随后开始测速。',
          style: textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            TextButton(
              onPressed: () {
                onCollapse();
                cast.stop();
              },
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                '取消',
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
              ),
            ),
            const Spacer(),
            FilledButton.icon(
              onPressed: null,
              icon: const Icon(Icons.cast, size: 18),
              label: const Text('等待就绪…'),
            ),
          ],
        ),
        _CollapseHandle(onTap: onCollapse),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  预热 / 测速面板（契约 dlna-warmup-ffi §3、§7.5）
// ─────────────────────────────────────────────────────────────

/// 预热中（`phase == "warming"`）的面板：
/// 实时转码速度、播放列表生成进度、编码器信息与「投送」按钮。
///
/// 所有遥测字段都由服务层容错解析：旧版 `.so` 不返回这些字段时，
/// 服务直接把 phase 降级为 `playing`，本面板不会出现。
class _WarmingPanel extends StatelessWidget {
  const _WarmingPanel({required this.cast, required this.onCollapse});

  final DlnaCastService cast;
  final VoidCallback onCollapse;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final ready = cast.playlistReady;
    final realtime = cast.estimatedRealtime;
    final speed = cast.encodeSpeed;
    final speedColor = realtime == false
        ? Colors.orange.shade700
        : realtime == true
            ? Colors.green.shade600
            : scheme.onSurfaceVariant;

    final encoder = _encoderLabel(cast);
    final fallbackLine = _hardwareFallbackLine(cast);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── 测速行 ─────────────────────────────────────────
        Row(
          children: [
            Icon(Icons.speed_rounded, size: 18, color: scheme.primary),
            const SizedBox(width: 8),
            Text(
              realtime == null ? '测速中…' : '转码速度',
              style: textTheme.labelMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              speed > 0 ? '${speed.toStringAsFixed(2)}×' : '--',
              style: textTheme.titleMedium?.copyWith(
                color: speedColor,
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            Text(
              '已编码 ${_fmtEncodeSeconds(cast.encodeContentMs)}',
              style: textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),

        if (realtime == false) ...[
          const SizedBox(height: 4),
          Text(
            '低于实时，播放可能卡顿，建议改用直通或更低预设',
            style: textTheme.labelSmall?.copyWith(
              color: Colors.orange.shade700,
            ),
          ),
        ],

        const SizedBox(height: 10),

        // ── 播放列表状态 ───────────────────────────────────
        Row(
          children: [
            Icon(
              ready
                  ? Icons.check_circle_outline
                  : Icons.movie_creation_outlined,
              size: 16,
              color: ready ? scheme.primary : scheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                ready
                    ? '播放列表已就绪（${cast.segments} 个片段）'
                    : '正在本地生成播放列表…',
                style: textTheme.labelMedium?.copyWith(
                  color: ready ? scheme.primary : scheme.onSurfaceVariant,
                ),
              ),
            ),
            if (!ready)
              SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: scheme.onSurfaceVariant,
                ),
              ),
          ],
        ),

        // ── 编码器（§7.5）───────────────────────────────────
        if (encoder != null) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                Icons.memory_rounded,
                size: 16,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  encoder,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.labelMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ],
        if (fallbackLine != null)
          Padding(
            padding: const EdgeInsets.only(left: 22, top: 2),
            child: Text(
              fallbackLine,
              style: textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant.withValues(alpha: 0.85),
              ),
            ),
          ),

        // ── 转码警告（§7.5）─────────────────────────────────
        if (cast.encodeWarnings.isNotEmpty) ...[
          const SizedBox(height: 8),
          _WarmingWarnings(warnings: cast.encodeWarnings),
        ],

        // ── 字幕准备提示（task-11 §6）───────────────────────
        if (cast.subtitleStatus?.hasNotice ?? false) ...[
          const SizedBox(height: 8),
          _SubtitleStatusNotes(status: cast.subtitleStatus!),
        ],

        // ── 诊断日志（默认折叠）─────────────────────────────
        _WarmingDiagnostics(lines: cast.diagnostics),

        const SizedBox(height: 8),

        // ── 操作行 ─────────────────────────────────────────
        Row(
          children: [
            TextButton(
              onPressed: () {
                onCollapse();
                cast.stop();
              },
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                '取消',
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontSize: 13,
                ),
              ),
            ),
            const Spacer(),
            FilledButton.icon(
              onPressed: ready ? () => cast.castNow() : null,
              icon: const Icon(Icons.cast, size: 18),
              label: Text(ready ? '投送' : '等待就绪…'),
            ),
          ],
        ),

        if (cast.error != null) ...[
          const SizedBox(height: 6),
          Text(
            cast.error!,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: textTheme.labelSmall?.copyWith(
              color: Colors.orange.shade700,
            ),
          ),
        ],

        _CollapseHandle(onTap: onCollapse),
      ],
    );
  }
}

/// 预热失败（`phase == "failed"`）面板：错误全文 + 警告 + 自动展开诊断日志。
class _WarmingFailedPanel extends StatelessWidget {
  const _WarmingFailedPanel({required this.cast, required this.onCollapse});

  final DlnaCastService cast;
  final VoidCallback onCollapse;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final error = cast.errorText ?? '转码失败（Rust 未提供具体原因）';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
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
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 120),
                      child: SingleChildScrollView(
                        child: SelectableText(
                          error,
                          style: textTheme.bodySmall?.copyWith(
                            color: scheme.onErrorContainer,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    iconSize: 16,
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 28, minHeight: 28),
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
              if (cast.renderer != null) ...[
                const SizedBox(height: 8),
                FilledButton.tonalIcon(
                  onPressed: () async {
                    final appState = context.read<AppState>();
                    await DlnaCompatSheet.show(
                      context,
                      cast.renderer!,
                      appState.dmrPrefs,
                    );
                  },
                  icon: const Icon(Icons.tune, size: 16),
                  label: const Text('兼容性设置'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(double.infinity, 36),
                    backgroundColor: scheme.error.withValues(alpha: 0.1),
                    foregroundColor: scheme.error,
                  ),
                ),
              ],
            ],
          ),
        ),

        if (cast.encodeMode != 'remux')
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              '可尝试改用「直通」预设重试',
              style: textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),

        if (cast.encodeWarnings.isNotEmpty) ...[
          const SizedBox(height: 8),
          _WarmingWarnings(warnings: cast.encodeWarnings),
        ],

        // 字幕准备提示（task-11 §6）：失败时同样展示，便于判断是不是字幕问题。
        if (cast.subtitleStatus?.hasNotice ?? false) ...[
          const SizedBox(height: 8),
          _SubtitleStatusNotes(status: cast.subtitleStatus!),
        ],

        // 失败时自动展开诊断日志，用户不用再点一次。
        _WarmingDiagnostics(lines: cast.diagnostics, autoExpand: true),

        _CollapseHandle(onTap: onCollapse),
      ],
    );
  }
}

/// 转码警告列表：橙色，最多展示 3 行，其余折叠为「…」。
class _WarmingWarnings extends StatelessWidget {
  const _WarmingWarnings({required this.warnings});

  final List<String> warnings;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final color = Colors.orange.shade700;
    final shown = warnings.take(3).toList();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final warning in shown)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 1),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.warning_amber_rounded, size: 14, color: color),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      warning,
                      style: textTheme.labelSmall?.copyWith(color: color),
                    ),
                  ),
                ],
              ),
            ),
          if (warnings.length > 3)
            Padding(
              padding: const EdgeInsets.only(left: 20, top: 2),
              child: Text(
                '…',
                style: textTheme.labelSmall?.copyWith(color: color),
              ),
            ),
        ],
      ),
    );
  }
}

/// 字幕准备提示（Rust `subtitle_status`，契约 task-11 §6）。
///
/// 侧车扫描失败 / 超时时显示 `message`，位图字幕（PGS/DVD）无法经 HLS
/// 投送时显示 `bitmap_note`。两者都为 null 时整个组件不渲染。
class _SubtitleStatusNotes extends StatelessWidget {
  const _SubtitleStatusNotes({required this.status});

  final DlnaSubtitleStatus status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final message = status.message;
    final bitmapNote = status.bitmapNote;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (message != null)
          _noteRow(
            context,
            icon: Icons.info_outline,
            text: '字幕：$message',
            color: Colors.orange.shade700,
            textTheme: textTheme,
          ),
        if (bitmapNote != null)
          _noteRow(
            context,
            icon: Icons.image_not_supported_outlined,
            text: '字幕：$bitmapNote',
            color: scheme.onSurfaceVariant,
            textTheme: textTheme,
          ),
      ],
    );
  }

  Widget _noteRow(
    BuildContext context, {
    required IconData icon,
    required String text,
    required Color color,
    required TextTheme textTheme,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: textTheme.labelSmall?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}

/// 诊断日志折叠区（§7.5）：等宽字体、可选中、可滚动、「复制」到剪贴板。
///
/// [autoExpand] 为 true 时（预热失败）默认展开。
class _WarmingDiagnostics extends StatefulWidget {
  const _WarmingDiagnostics({
    required this.lines,
    this.autoExpand = false,
  });

  final List<String> lines;
  final bool autoExpand;

  @override
  State<_WarmingDiagnostics> createState() => _WarmingDiagnosticsState();
}

class _WarmingDiagnosticsState extends State<_WarmingDiagnostics> {
  late bool _open = widget.autoExpand;

  @override
  Widget build(BuildContext context) {
    final lines = widget.lines;
    if (lines.isEmpty) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final text = lines.join('\n');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () => setState(() => _open = !_open),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Icon(
                  _open
                      ? Icons.expand_more_rounded
                      : Icons.chevron_right_rounded,
                  size: 18,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 2),
                Text(
                  '诊断日志（${lines.length} 行）',
                  style: textTheme.labelMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                if (_open)
                  IconButton(
                    iconSize: 16,
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 28, minHeight: 28),
                    icon: Icon(
                      Icons.copy,
                      size: 14,
                      color: scheme.onSurfaceVariant,
                    ),
                    tooltip: '复制诊断日志',
                    onPressed: () {
                      // Flutter 3.x Clipboard
                      // ignore: deprecated_member_use
                      Clipboard.setData(ClipboardData(text: text));
                      AppSnack.show(context, '已复制到剪贴板');
                    },
                  ),
              ],
            ),
          ),
        ),
        if (_open)
          Container(
            constraints: const BoxConstraints(maxHeight: 160),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Scrollbar(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(8),
                child: SelectableText(
                  text,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    height: 1.35,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// 面板底部的收起箭头（与常规控制条保持一致）。
class _CollapseHandle extends StatelessWidget {
  const _CollapseHandle({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.center,
      child: GestureDetector(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Icon(
            Icons.keyboard_arrow_down_rounded,
            color: scheme.onSurfaceVariant,
            size: 24,
          ),
        ),
      ),
    );
  }
}

/// 编码方式一行文案：`封装直转 (remux)` / `H.264 软编 libx264 · AAC`。
///
/// 字段缺失时返回 null（不显示该行）。
String? _encoderLabel(DlnaCastService cast) {
  final mode = cast.encodeMode;
  if (mode == 'remux') return '封装直转 (remux)';

  final video = cast.videoEncoder;
  final audio = cast.audioEncoder;
  final parts = <String>[];
  if (video != null && video.isNotEmpty) {
    parts.add(_videoEncoderLabel(video));
  }
  if (audio != null && audio.isNotEmpty) {
    parts.add(_audioEncoderLabel(audio));
  }
  if (parts.isNotEmpty) return parts.join(' · ');
  return mode == 'transcode' ? '实时转码' : null;
}

String _videoEncoderLabel(String name) {
  final n = name.toLowerCase();
  if (n.contains('libx264')) return 'H.264 软编 $name';
  if (n.contains('libx265')) return 'H.265 软编 $name';
  if (n.contains('x264') || n.contains('h264') || n.contains('avc')) {
    return 'H.264 硬编 $name';
  }
  if (n.contains('x265') || n.contains('h265') || n.contains('hevc')) {
    return 'H.265 硬编 $name';
  }
  return name;
}

String _audioEncoderLabel(String name) {
  if (name.toLowerCase() == 'copy') return '音频直拷';
  return name.toUpperCase();
}

/// 硬件回退提示（灰色小字）。
///
/// Rust 的 `encode_warnings` 已经带原文时优先展示警告列表，避免重复；
/// 否则用 `encode_mode == transcode` + 软编器名推导。
String? _hardwareFallbackLine(DlnaCastService cast) {
  if (cast.encodeMode != 'transcode') return null;
  if (cast.encodeWarnings.any(_isHardwareFallbackWarning)) return null;
  final video = cast.videoEncoder?.toLowerCase() ?? '';
  if (video.contains('libx264') ||
      video.contains('libx265') ||
      video.contains('libvpx')) {
    return '硬件编码器不可用，已回退软件编码';
  }
  return null;
}

bool _isHardwareFallbackWarning(String warning) {
  final w = warning.toLowerCase();
  return w.contains('回退') ||
      w.contains('fallback') ||
      w.contains('不可用') ||
      w.contains('unavailable');
}

/// 「已编码 x.x 秒」：小于 10 秒保留一位小数，之后取整。
String _fmtEncodeSeconds(int ms) {
  final seconds = ms / 1000;
  if (seconds < 10) return '${seconds.toStringAsFixed(1)} 秒';
  return '${seconds.round()} 秒';
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
                    // 音频投送队列用音乐图标，不再一律显示视频文件。
                    isCurrent
                        ? Icons.play_arrow_rounded
                        : item.isAudio
                            ? Icons.audiotrack
                            : Icons.video_file,
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
