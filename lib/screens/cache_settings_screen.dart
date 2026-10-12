import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/generated/app_localizations.dart';
import '../models/cache_policy.dart';
import '../providers/app_state.dart';
import '../services/library_service.dart';
import '../services/settings_service.dart';
import '../theme/app_theme.dart';
import '../utils/app_snack.dart';
import '../utils/audio_extensions.dart';

/// 音乐缓存占用、保留时长与手动清理。自定义天数要手填，所以收进二级页。
class CacheSettingsScreen extends StatefulWidget {
  const CacheSettingsScreen({super.key});

  @override
  State<CacheSettingsScreen> createState() => _CacheSettingsScreenState();
}

class _CacheSettingsScreenState extends State<CacheSettingsScreen> {
  late final TextEditingController _customDaysController;
  late final TextEditingController _customHoursController;
  late final TextEditingController _maxMbController;
  int? _cacheBytes;
  int? _mangaCacheBytes;
  bool _cacheSizeLoading = false;
  late final TextEditingController _mangaMaxMbController;

  @override
  void initState() {
    super.initState();
    _customDaysController = TextEditingController();
    _customHoursController = TextEditingController();
    _maxMbController = TextEditingController();
    _mangaMaxMbController = TextEditingController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncCustomFieldsFromSettings();
      _syncMaxMbFromSettings();
      _syncMangaMaxMbFromSettings();
      _refreshCacheSize();
    });
  }

  @override
  void dispose() {
    _customDaysController.dispose();
    _customHoursController.dispose();
    _maxMbController.dispose();
    _mangaMaxMbController.dispose();
    super.dispose();
  }

  void _syncCustomFieldsFromSettings() {
    final settings = context.read<SettingsService>();
    final total = settings.customRetentionHours;
    _customDaysController.text = '${total ~/ 24}';
    _customHoursController.text = '${total % 24}';
  }

  void _syncMaxMbFromSettings() {
    final settings = context.read<SettingsService>();
    _maxMbController.text = '${settings.musicCacheMaxMb}';
  }

  void _syncMangaMaxMbFromSettings() {
    final settings = context.read<SettingsService>();
    _mangaMaxMbController.text = '${settings.mangaCacheMaxMb}';
  }

  Future<void> _applyMangaMaxMb() async {
    final raw = int.tryParse(_mangaMaxMbController.text.trim()) ?? 0;
    await context.read<SettingsService>().setMangaCacheMaxMb(raw);
    if (!mounted) return;
    _syncMangaMaxMbFromSettings();
    final maxMb = context.read<SettingsService>().mangaCacheMaxMb;
    if (maxMb > 0) {
      await context.read<AppState>().cache.evictMangaToMaxBytes(
        maxBytes: maxMb * 1024 * 1024,
      );
    }
  }

  Future<void> _applyMaxMb() async {
    final raw = int.tryParse(_maxMbController.text.trim()) ?? 0;
    await context.read<AppState>().setMusicCacheMaxMb(raw);
    if (!mounted) return;
    _syncMaxMbFromSettings();
  }

  Future<void> _refreshCacheSize() async {
    setState(() => _cacheSizeLoading = true);
    try {
      final cache = context.read<AppState>().cache;
      final bytes = await cache.cacheSizeBytes();
      final mangaBytes = await cache.mangaCacheSizeBytes();
      if (!mounted) return;
      setState(() {
        _cacheBytes = bytes;
        _mangaCacheBytes = mangaBytes;
        _cacheSizeLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _cacheSizeLoading = false);
    }
  }

  Future<void> _applyCustomRetention() async {
    final days = int.tryParse(_customDaysController.text.trim()) ?? 0;
    final hours = int.tryParse(_customHoursController.text.trim()) ?? 0;
    var totalHours = days * 24 + hours;
    if (totalHours < 1) totalHours = 1;
    await context.read<AppState>().setCustomRetentionDuration(
      Duration(hours: totalHours),
    );
    if (!mounted) return;
    _syncCustomFieldsFromSettings();
  }

  String _customRetentionSummary(SettingsService settings) {
    final l10n = AppLocalizations.of(context)!;
    final total = settings.customRetentionHours;
    final days = total ~/ 24;
    final hours = total % 24;
    if (days > 0 && hours > 0) return l10n.retentionDaysHours(days, hours);
    if (days > 0) return l10n.retentionDays(days);
    return l10n.retentionHours(hours);
  }

  Future<void> _clearCache() async {
    final n = await context.read<AppState>().manualClearCache();
    if (!mounted) return;
    final libCount = context.read<LibraryService>().count;
    await _refreshCacheSize();
    if (!mounted) return;
    AppSnack.show(
      context,
      AppLocalizations.of(context)!.cacheCleared(n, libCount),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(title: Text(l10n.cacheCleanup)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(l10n.cacheCleanupHint),
          const SizedBox(height: 12),
          Card(
            color: Theme.of(context).colorScheme.surfaceContainer,
            child: ListTile(
              leading: const Icon(
                Icons.sd_storage_outlined,
                color: AppColors.accent,
              ),
              title: Text(l10n.currentCacheUsage),
              subtitle: Text(
                _cacheSizeLoading
                    ? l10n.calculating
                    : (_cacheBytes == null
                          ? l10n.unknown
                          : formatByteSize(_cacheBytes!)),
              ),
              trailing: IconButton(
                tooltip: l10n.refresh,
                icon: const Icon(Icons.refresh),
                onPressed: _cacheSizeLoading ? null : _refreshCacheSize,
              ),
            ),
          ),
          const SizedBox(height: 8),
          SegmentedButton<CacheRetention>(
            showSelectedIcon: false,
            segments: [
              for (final r in CacheRetention.values)
                ButtonSegment(value: r, label: Text(r.label(l10n))),
            ],
            selected: {settings.retention},
            onSelectionChanged: (s) {
              final next = s.first;
              context.read<AppState>().setRetention(next);
              if (next == CacheRetention.custom) {
                _syncCustomFieldsFromSettings();
              }
            },
          ),
          if (settings.retention == CacheRetention.custom) ...[
            const SizedBox(height: 12),
            Text(
              l10n.customRetentionHint,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                SizedBox(
                  width: 88,
                  child: TextField(
                    controller: _customDaysController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      isDense: true,
                      labelText: l10n.days,
                      border: const OutlineInputBorder(),
                    ),
                    onEditingComplete: _applyCustomRetention,
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 88,
                  child: TextField(
                    controller: _customHoursController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      isDense: true,
                      labelText: l10n.hours,
                      border: const OutlineInputBorder(),
                    ),
                    onEditingComplete: _applyCustomRetention,
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.tonal(
                  onPressed: _applyCustomRetention,
                  child: Text(l10n.apply),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              _customRetentionSummary(settings),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          if (settings.retention == CacheRetention.never) ...[
            const SizedBox(height: 8),
            Text(
              l10n.autoCleanupDisabled,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 16),
          Text(
            l10n.musicCacheMaxCapacity,
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(color: Theme.of(context).colorScheme.primary),
          ),
          const SizedBox(height: 4),
          Text(
            l10n.musicCacheMaxCapacityHint,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              SizedBox(
                width: 120,
                child: TextField(
                  controller: _maxMbController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    isDense: true,
                    labelText: l10n.musicCacheMaxMb,
                    border: const OutlineInputBorder(),
                  ),
                  onEditingComplete: _applyMaxMb,
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.tonal(
                onPressed: _applyMaxMb,
                child: Text(l10n.apply),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            settings.musicCacheMaxMb <= 0
                ? l10n.musicCacheUnlimited
                : '${settings.musicCacheMaxMb} MB',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 24),
          Text(
            l10n.mangaCacheSection,
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(color: Theme.of(context).colorScheme.primary),
          ),
          const SizedBox(height: 8),
          Card(
            color: Theme.of(context).colorScheme.surfaceContainer,
            child: ListTile(
              leading: const Icon(Icons.menu_book_outlined),
              title: Text(l10n.mangaCacheSizeLabel),
              subtitle: Text(
                _cacheSizeLoading
                    ? l10n.calculating
                    : (_mangaCacheBytes == null
                          ? l10n.unknown
                          : formatByteSize(_mangaCacheBytes!)),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              SizedBox(
                width: 120,
                child: TextField(
                  controller: _mangaMaxMbController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    isDense: true,
                    labelText: l10n.mangaCacheMaxMb,
                    border: const OutlineInputBorder(),
                  ),
                  onEditingComplete: _applyMangaMaxMb,
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.tonal(
                onPressed: _applyMangaMaxMb,
                child: Text(l10n.apply),
              ),
            ],
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _clearCache,
            icon: const Icon(Icons.cleaning_services_outlined),
            label: Text(l10n.clearAudioCache),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: Text(l10n.clearMangaCache),
                  content: Text(l10n.clearMangaCacheConfirm),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: Text(l10n.cancel),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: Text(l10n.confirm),
                    ),
                  ],
                ),
              );
              if (ok != true || !mounted) return;
              await context.read<AppState>().cache.clearAllMangaCache();
              if (!mounted) return;
              await _refreshCacheSize();
              if (!mounted) return;
              AppSnack.show(context, l10n.clearMangaCache);
            },
            icon: const Icon(Icons.menu_book_outlined),
            label: Text(l10n.clearMangaCache),
          ),
        ],
      ),
    );
  }
}
