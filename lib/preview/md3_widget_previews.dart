import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

import '../l10n/generated/app_localizations.dart';
import '../models/app_theme_mode.dart';
import '../theme/app_theme.dart';
import '../widgets/meta_text.dart';
import '../widgets/theme_settings_section.dart';

/// Widget Previewer only. Production screens and `main.dart` must not import
/// this file. Fake rows live here so they are not reachable from the app.

PreviewLocalizationsData previewZhLocalizations() {
  return PreviewLocalizationsData(
    locale: const Locale('zh'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
  );
}

@Preview(
  name: '主题设置',
  size: Size(420, 280),
  localizations: previewZhLocalizations,
)
Widget previewThemeSettings() {
  if (!kDebugMode) return const SizedBox.shrink();
  return const _SeedThemeHost(child: _ThemeControls());
}

@Preview(
  name: '列表次要信息',
  size: Size(420, 280),
  localizations: previewZhLocalizations,
)
Widget previewSecondaryRows() {
  if (!kDebugMode) return const SizedBox.shrink();
  return const _SeedThemeHost(child: _FakeRows());
}

class _ThemeControls extends StatelessWidget {
  const _ThemeControls();

  @override
  Widget build(BuildContext context) {
    final host = context.findAncestorStateOfType<_SeedThemeHostState>()!;
    return ThemeSettingsSection(
      mode: host.mode,
      onModeChanged: host.setMode,
      seed: host.seed,
      onSeedChanged: host.setSeed,
    );
  }
}

class _FakeRows extends StatelessWidget {
  const _FakeRows();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      children: [
        const ListTile(
          leading: Icon(Icons.folder_rounded),
          title: Text('Night'),
        ),
        ListTile(
          leading: const Icon(Icons.audiotrack),
          title: const Text('track.flac'),
          subtitle: MetaText('4.2 MB · ${l10n.netTapDownload}'),
        ),
        ListTile(
          leading: const Icon(Icons.queue_music),
          title: const Text('通勤'),
          subtitle: MetaText(l10n.playlistTrackCount(12)),
        ),
      ],
    );
  }
}

class _SeedThemeHost extends StatefulWidget {
  const _SeedThemeHost({required this.child});

  final Widget child;

  @override
  State<_SeedThemeHost> createState() => _SeedThemeHostState();
}

class _SeedThemeHostState extends State<_SeedThemeHost> {
  AppThemeMode mode = AppThemeMode.light;
  Color seed = AppTheme.defaultSeed;

  void setMode(AppThemeMode value) => setState(() => mode = value);

  void setSeed(Color value) => setState(() => seed = value);

  @override
  Widget build(BuildContext context) {
    final platformDark =
        MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    final dark = switch (mode) {
      AppThemeMode.dark => true,
      AppThemeMode.light => false,
      AppThemeMode.system => platformDark,
    };
    final theme = dark ? AppTheme.darkFrom(seed) : AppTheme.lightFrom(seed);
    return Theme(
      data: theme,
      child: Material(color: theme.colorScheme.surface, child: widget.child),
    );
  }
}
