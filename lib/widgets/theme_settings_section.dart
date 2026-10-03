import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';
import '../models/app_theme_mode.dart';
import '../theme/app_theme.dart';

/// Theme mode and the single seed color. Matches the other settings rows.
class ThemeSettingsSection extends StatelessWidget {
  const ThemeSettingsSection({
    super.key,
    required this.mode,
    required this.onModeChanged,
    required this.seed,
    required this.onSeedChanged,
  });

  final AppThemeMode mode;
  final ValueChanged<AppThemeMode> onModeChanged;
  final Color seed;
  final ValueChanged<Color> onSeedChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.brightness_6_outlined),
          title: Text(l10n.themeMode),
          subtitle: Text(l10n.themeModeSubtitle),
          trailing: DropdownButton<AppThemeMode>(
            borderRadius: BorderRadius.circular(10),
            value: mode,
            items: [
              DropdownMenuItem(
                value: AppThemeMode.system,
                child: Text(l10n.themeModeSystem),
              ),
              DropdownMenuItem(
                value: AppThemeMode.light,
                child: Text(l10n.themeModeLight),
              ),
              DropdownMenuItem(
                value: AppThemeMode.dark,
                child: Text(l10n.themeModeDark),
              ),
            ],
            onChanged: (value) {
              if (value != null) {
                onModeChanged(value);
              }
            },
          ),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: _SeedSwatch(color: seed),
          title: Text(l10n.themeSeed),
          subtitle: Text(l10n.themeSeedSubtitle),
          onTap: () async {
            final next = await showThemeSeedDialog(context, seed);
            if (next != null) onSeedChanged(next);
          },
        ),
      ],
    );
  }
}

class _SeedSwatch extends StatelessWidget {
  const _SeedSwatch({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
    );
  }
}

/// Presets plus hue / saturation / value. One opaque seed, not a palette.
Future<Color?> showThemeSeedDialog(BuildContext context, Color current) {
  return showDialog<Color>(
    context: context,
    builder: (context) => _SeedDialog(initial: current),
  );
}

class _SeedDialog extends StatefulWidget {
  const _SeedDialog({required this.initial});

  final Color initial;

  @override
  State<_SeedDialog> createState() => _SeedDialogState();
}

class _SeedDialogState extends State<_SeedDialog> {
  static const _presets = <Color>[
    AppTheme.defaultSeed,
    Color(0xFF1565C0),
    Color(0xFF6A1B9A),
    Color(0xFFE65100),
    Color(0xFFC62828),
    Color(0xFF2E7D32),
  ];

  late HSVColor _hsv = HSVColor.fromColor(widget.initial);

  Color get _color => _hsv.toColor().withValues(alpha: 1);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(l10n.themeSeed),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _SeedSwatch(color: _color),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final preset in _presets)
                  InkWell(
                    onTap: () =>
                        setState(() => _hsv = HSVColor.fromColor(preset)),
                    child: _SeedSwatch(color: preset),
                  ),
              ],
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                l10n.themeSeedHue,
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ),
            Slider(
              value: _hsv.hue,
              max: 360,
              onChanged: (v) => setState(() => _hsv = _hsv.withHue(v)),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                l10n.themeSeedSaturation,
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ),
            Slider(
              value: _hsv.saturation,
              onChanged: (v) => setState(() => _hsv = _hsv.withSaturation(v)),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                l10n.themeSeedValue,
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ),
            Slider(
              value: _hsv.value,
              onChanged: (v) => setState(() => _hsv = _hsv.withValue(v)),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, AppTheme.defaultSeed),
          child: Text(l10n.themeSeedReset),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, _color),
          child: Text(l10n.save),
        ),
      ],
    );
  }
}
