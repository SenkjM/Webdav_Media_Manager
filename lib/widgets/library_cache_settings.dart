import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/generated/app_localizations.dart';
import '../models/cache_policy.dart';
import '../providers/app_state.dart';
import '../utils/app_snack.dart';
import '../utils/audio_extensions.dart';

/// 库设置子页共用的「缓存」区块。
///
/// 音乐库与漫画库各挂一份，只有 [kind] 不同：缓存占用、过期清理、容量上限、
/// 手动全部清理四项完全一致，保证两页排版一致。
class LibraryCacheSettings extends StatefulWidget {
  const LibraryCacheSettings({super.key, required this.kind});

  final CacheKind kind;

  @override
  State<LibraryCacheSettings> createState() => _LibraryCacheSettingsState();
}

class _LibraryCacheSettingsState extends State<LibraryCacheSettings> {
  final TextEditingController _days = TextEditingController();
  final TextEditingController _hours = TextEditingController();
  final TextEditingController _maxMb = TextEditingController();

  int _bytes = 0;
  bool _loading = true;

  bool get _isMusic => widget.kind == CacheKind.music;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _syncFromSettings();
      unawaited(_refreshSize());
    });
  }

  @override
  void dispose() {
    _days.dispose();
    _hours.dispose();
    _maxMb.dispose();
    super.dispose();
  }

  void _syncFromSettings() {
    final settings = context.read<AppState>().settings;
    final hours = _isMusic
        ? settings.customRetentionHours
        : settings.mangaCustomRetentionHours;
    _days.text = '${hours ~/ 24}';
    _hours.text = '${hours % 24}';
    _maxMb.text =
        '${_isMusic ? settings.musicCacheMaxMb : settings.mangaCacheMaxMb}';
  }

  Future<void> _refreshSize() async {
    if (mounted) setState(() => _loading = true);
    final cache = context.read<AppState>().cache;
    final bytes = await cache.cacheSizeFor(widget.kind);
    if (!mounted) return;
    setState(() {
      _bytes = bytes;
      _loading = false;
    });
  }

  Future<void> _applyCustom() async {
    final days = int.tryParse(_days.text.trim()) ?? 0;
    final hours = int.tryParse(_hours.text.trim()) ?? 0;
    final total = Duration(hours: days * 24 + hours);
    final app = context.read<AppState>();
    if (_isMusic) {
      await app.setCustomRetentionDuration(total);
    } else {
      await app.setMangaCustomRetentionDuration(total);
    }
    if (!mounted) return;
    _syncFromSettings();
  }

  Future<void> _applyMaxMb() async {
    final mb = int.tryParse(_maxMb.text.trim()) ?? 0;
    final app = context.read<AppState>();
    if (_isMusic) {
      await app.setMusicCacheMaxMb(mb);
    } else {
      await app.setMangaCacheMaxMb(mb);
    }
    if (!mounted) return;
    _syncFromSettings();
  }

  Future<void> _clearAll() async {
    final l10n = AppLocalizations.of(context)!;
    final app = context.read<AppState>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.cacheClearAll),
        content: Text(l10n.cacheClearAllConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.confirm),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final removed = _isMusic
        ? await app.manualClearCache()
        : await app.manualClearMangaCache();
    if (!mounted) return;
    AppSnack.show(context, l10n.cacheClearedFiles(removed));
    await _refreshSize();
  }

  String _summaryText(AppLocalizations l10n, CacheExpiryPolicy policy) {
    final duration = policy.effectiveDuration;
    if (duration == null) return l10n.autoCleanupDisabled;
    final days = duration.inHours ~/ 24;
    final hours = duration.inHours % 24;
    if (days > 0 && hours > 0) return l10n.retentionDaysHours(days, hours);
    if (days > 0) return l10n.retentionDays(days);
    return l10n.retentionHours(hours);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final app = context.watch<AppState>();
    final settings = app.settings;
    final retention = _isMusic ? settings.retention : settings.mangaRetention;
    final policy = _isMusic
        ? settings.musicCacheExpiryPolicy
        : settings.mangaCacheExpiryPolicy;
    final hintStyle = theme.textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(height: 32),
        Text(
          l10n.cacheRetentionSection,
          style: theme.textTheme.titleMedium?.copyWith(color: scheme.primary),
        ),
        const SizedBox(height: 4),
        Text(l10n.cacheRetentionHint, style: hintStyle),
        const SizedBox(height: 8),
        Card(
          margin: EdgeInsets.zero,
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 12),
            leading: const Icon(Icons.sd_storage_outlined),
            title: Text(l10n.currentCacheUsage),
            subtitle: Text(_loading ? l10n.calculating : formatByteSize(_bytes)),
            trailing: IconButton(
              tooltip: l10n.refresh,
              icon: const Icon(Icons.refresh),
              onPressed: () => unawaited(_refreshSize()),
            ),
          ),
        ),
        const SizedBox(height: 12),
        SegmentedButton<CacheRetention>(
          segments: [
            for (final option in CacheRetention.values)
              ButtonSegment<CacheRetention>(
                value: option,
                label: Text(option.label(l10n)),
              ),
          ],
          selected: {retention},
          showSelectedIcon: false,
          onSelectionChanged: (selection) {
            final next = selection.first;
            if (_isMusic) {
              unawaited(app.setRetention(next));
            } else {
              unawaited(app.setMangaRetention(next));
            }
          },
        ),
        if (retention == CacheRetention.custom) ...[
          const SizedBox(height: 12),
          Text(l10n.customRetentionHint, style: hintStyle),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _days,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: l10n.days,
                    isDense: true,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _hours,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: l10n.hours,
                    isDense: true,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () => unawaited(_applyCustom()),
                child: Text(l10n.apply),
              ),
            ],
          ),
        ],
        const SizedBox(height: 8),
        Text(_summaryText(l10n, policy), style: hintStyle),
        const SizedBox(height: 20),
        Text(
          l10n.cacheSizeCapSection,
          style: theme.textTheme.titleMedium?.copyWith(color: scheme.primary),
        ),
        const SizedBox(height: 4),
        Text(l10n.cacheSizeCapHint, style: hintStyle),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _maxMb,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: l10n.musicCacheMaxMb,
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: () => unawaited(_applyMaxMb()),
              child: Text(l10n.apply),
            ),
          ],
        ),
        const SizedBox(height: 20),
        OutlinedButton.icon(
          onPressed: () => unawaited(_clearAll()),
          icon: const Icon(Icons.delete_sweep_outlined),
          label: Text(l10n.cacheClearAll),
        ),
      ],
    );
  }
}
