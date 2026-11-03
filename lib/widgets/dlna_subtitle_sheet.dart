import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';
import '../services/dlna_cast_service.dart';
import '../utils/app_snack.dart';
import '../utils/subtitle_sidecar.dart';
import 'dlna_subtitle_switch_dialog.dart';

/// DLNA 字幕选择底部弹窗。
///
/// 列出当前视频的字幕候选项：同级目录扫描到的外置字幕，以及（HLS 投屏时）
/// Rust 从容器里探测到的内置字幕轨。点击后调用
/// [DlnaCastService.selectSubtitle] 切换；位图字幕（PGS/DVD）无法经 HLS
/// 投送，行内禁用并说明原因（契约 task-11 §3–§5）。
class DlnaSubtitleSheet extends StatelessWidget {
  const DlnaSubtitleSheet({
    super.key,
    required this.cast,
  });

  final DlnaCastService cast;

  static void show(BuildContext context, DlnaCastService cast) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => DlnaSubtitleSheet(cast: cast),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final candidates = cast.subtitleCandidates;
    final selected = cast.selectedSubtitle;
    final status = cast.subtitleStatus;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.5,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── 标题栏 ──
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                children: [
                  Icon(Icons.subtitles_outlined, size: 20, color: scheme.primary),
                  const SizedBox(width: 8),
                  Text('字幕', style: Theme.of(context).textTheme.titleMedium),
                ],
              ),
            ),
            const Divider(height: 1),

            // ── 字幕准备提示（Rust `subtitle_status`；旧版 .so 无此字段时不显示）──
            if (status != null && status.hasNotice)
              _SubtitleStatusHints(status: status),

            // ── 关闭字幕 ──
            ListTile(
              leading: Icon(
                selected == null ? Icons.check : Icons.check_box_outline_blank,
                size: 20,
                color: selected == null ? scheme.primary : scheme.outlineVariant,
              ),
              title: const Text('关闭字幕'),
              onTap: () => _select(context, null),
            ),

            // ── 候选列表 ──
            if (candidates.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  '未找到匹配的字幕文件',
                  style: Theme.of(context).textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: candidates.length,
                  itemBuilder: (context, index) =>
                      _buildTile(context, l10n, candidates[index]),
                ),
              ),

            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// 选中字幕或关闭字幕。
  ///
  /// 播放中（`cast.isActive`）先弹二次确认：切换会让渲染器重新加载播放并二次
  /// seek，取消时**不发任何命令**、保留本弹窗。失败时**保留弹窗**并用 SnackBar
  /// 说明原因（例如位图字幕被 Rust 拒绝），不再像以前那样静默关闭。
  Future<void> _select(BuildContext context, SidecarHit? hit) async {
    final result = await cast.selectSubtitle(
      hit,
      confirmReload: () => DlnaSubtitleSwitchDialog.show(context),
    );
    if (!context.mounted) return;
    switch (result.status) {
      case DlnaSubtitleSelectStatus.cancelled:
        return;
      case DlnaSubtitleSelectStatus.failed:
        AppSnack.show(context, result.message ?? '切换字幕失败', error: true);
        return;
      case DlnaSubtitleSelectStatus.applied:
        final resumedAt = result.resumedAt;
        if (resumedAt != null) {
          AppSnack.show(
            context,
            '已跳回原播放位置 ${_formatPosition(resumedAt)}',
          );
        }
        Navigator.of(context).pop();
    }
  }

  /// 把跳回的原播放位置格式化成 `mm:ss` / `h:mm:ss` 提示。
  static String _formatPosition(Duration position) {
    final hours = position.inHours;
    final minutes = position.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = position.inSeconds.remainder(60).toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }

  Widget _buildTile(
    BuildContext context,
    AppLocalizations l10n,
    SidecarHit hit,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isSelected = cast.selectedSubtitle?.path == hit.path;
    final blocked = hit.bitmapUnsupported;
    final label = hit.labelFor(l10n);
    final format = _subtitleFormatTag(hit);
    // 契约 task-21 §2：内置轨优先显示容器标题，其次语言中文名，最后「轨道 N」；
    // 外置字幕仍用文件名解析出的语言。
    final languageName = subtitleLanguageName(hit.languageCode);
    final titleText = hit.trackLanguageLabel ?? label.title;
    final languageDetail = hit.embedded &&
            languageName != null &&
            languageName != titleText
        ? languageName
        : null;

    final String kindText;
    final Color kindColor;
    if (blocked) {
      kindText = format == null ? '位图 · 不支持' : '位图 · $format · 不支持';
      kindColor = scheme.error;
    } else if (hit.embedded) {
      kindText = format == null ? '内置' : '内置 · $format';
      kindColor = scheme.primary;
    } else {
      kindText = format == null ? '外置' : '外置 · $format';
      kindColor = scheme.onSurfaceVariant;
    }

    return ListTile(
      enabled: !blocked,
      leading: Icon(
        blocked
            ? Icons.block
            : isSelected
                ? Icons.check
                : Icons.check_box_outline_blank,
        size: 20,
        color: blocked
            ? scheme.error
            : isSelected
                ? scheme.primary
                : scheme.outlineVariant,
      ),
      title: Text(
        titleText,
        style: isSelected
            ? TextStyle(color: scheme.primary)
            : blocked
                ? TextStyle(color: scheme.onSurfaceVariant)
                : null,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _SubtitleKindBadge(text: kindText, color: kindColor),
              if (languageDetail != null) ...[
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    languageDetail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ],
          ),
          if (blocked)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                '投屏无法显示位图字幕，请改用文本字幕或直通模式',
                style: textTheme.bodySmall?.copyWith(color: scheme.error),
              ),
            ),
        ],
      ),
      onTap: blocked ? null : () => _select(context, hit),
    );
  }
}

/// 弹窗顶部的字幕准备提示行。
class _SubtitleStatusHints extends StatelessWidget {
  const _SubtitleStatusHints({required this.status});

  final DlnaSubtitleStatus status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final rows = <Widget>[
      if (status.message != null)
        _hintRow(
          context,
          icon: Icons.info_outline,
          text: status.message!,
          color: Colors.orange.shade800,
        ),
      if (status.bitmapNote != null)
        _hintRow(
          context,
          icon: Icons.image_not_supported_outlined,
          text: status.bitmapNote!,
          color: scheme.onSurfaceVariant,
        ),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: row,
            ),
        ],
      ),
    );
  }

  Widget _hintRow(
    BuildContext context, {
    required IconData icon,
    required String text,
    required Color color,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: color),
          ),
        ),
      ],
    );
  }
}

/// 候选字幕类型小标签：内置 / 外置 / 位图（不支持）。
class _SubtitleKindBadge extends StatelessWidget {
  const _SubtitleKindBadge({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

/// 把 Rust 的 libav codec 名 / 文件扩展名归一成简短格式标签。
String? _subtitleFormatTag(SidecarHit hit) {
  final raw = (hit.codec ?? hit.format).trim();
  if (raw.isEmpty) return null;
  switch (raw.toLowerCase()) {
    case 'subrip':
    case 'srt':
      return 'SRT';
    case 'mov_text':
      return 'MOV_TEXT';
    case 'webvtt':
    case 'vtt':
      return 'VTT';
    case 'hdmv_pgs_subtitle':
    case 'pgs':
      return 'PGS';
    case 'dvd_subtitle':
    case 'dvdsub':
      return 'DVD';
    case 'dvb_subtitle':
      return 'DVB';
    case 'xsub':
      return 'XSUB';
    default:
      return raw.toUpperCase();
  }
}
