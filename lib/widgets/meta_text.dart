import 'package:flutter/material.dart';

/// Quiet secondary line (size, count, path).
///
/// Color comes from the active [ColorScheme.onSurfaceVariant], so the default
/// teal seed and any later seed, in light or dark, use the same role.
class MetaText extends StatelessWidget {
  const MetaText(this.data, {super.key, this.maxLines = 1});

  final String data;
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      data,
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}
