import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';
import '../theme/app_theme.dart';

/// Soft-gold color for "cached" status dots (not warning amber/orange).
Color cachedStatusDotColor(BuildContext context) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  return dark ? AppColors.cachedStatusBright : AppColors.cachedStatus;
}

/// Compact 10px status dot: red (missing) / pale gold (cached) / primary (streamable).
class TrackStatusDot extends StatelessWidget {
  const TrackStatusDot({
    super.key,
    required this.remoteMissing,
    required this.isLocal,
    this.margin = const EdgeInsets.only(right: 4),
  });

  final bool remoteMissing;
  final bool isLocal;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final color = remoteMissing
        ? AppColors.error
        : isLocal
            ? cachedStatusDotColor(context)
            : Theme.of(context).colorScheme.primary;
    final tip = remoteMissing
        ? l10n.trackStateRemoteMissing
        : isLocal
            ? l10n.downloaded
            : l10n.trackStateStreamable;
    return Tooltip(
      message: tip,
      child: Container(
        width: 10,
        height: 10,
        margin: margin,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          border: Border.all(
            color: color.withValues(alpha: 0.4),
            width: 1,
          ),
        ),
      ),
    );
  }
}
