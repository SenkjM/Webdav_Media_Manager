import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';
import '../services/dlna_cast_service.dart';

/// DLNA 字幕选择底部弹窗。
///
/// 列出当前视频在同级目录中扫描到的字幕候选项，
/// 点击后调用 [DlnaCastService.selectSubtitle] 切换。
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

            // ── 关闭字幕 ──
            ListTile(
              leading: Icon(
                selected == null ? Icons.check : Icons.check_box_outline_blank,
                size: 20,
                color: selected == null ? scheme.primary : scheme.outlineVariant,
              ),
              title: const Text('关闭字幕'),
              onTap: () {
                cast.selectSubtitle(null);
                Navigator.of(context).pop();
              },
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
                  itemBuilder: (context, index) {
                    final hit = candidates[index];
                    final label = hit.labelFor(l10n);
                    final isSelected = selected?.path == hit.path;
                    return ListTile(
                      leading: Icon(
                        isSelected
                            ? Icons.check
                            : Icons.check_box_outline_blank,
                        size: 20,
                        color: isSelected
                            ? scheme.primary
                            : scheme.outlineVariant,
                      ),
                      title: Text(
                        label.title,
                        style: isSelected
                            ? TextStyle(color: scheme.primary)
                            : null,
                      ),
                      subtitle: label.formatTag != null
                          ? Text(label.formatTag!.toUpperCase())
                          : null,
                      onTap: () {
                        cast.selectSubtitle(hit);
                        Navigator.of(context).pop();
                      },
                    );
                  },
                ),
              ),

            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
