import 'package:flutter/material.dart';

/// A trailing dropdown with a fixed width so every row's control lines up on
/// both edges; long labels ellipsize instead of stretching the tile.
///
/// A bare [DropdownButton] in `ListTile.trailing` sizes itself to its widest
/// item, so rows end at different x offsets and the column looks ragged.
class TrailingDropdown<T> extends StatelessWidget {
  const TrailingDropdown({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.width = 148,
  });

  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          borderRadius: BorderRadius.circular(10),
          isDense: true,
          isExpanded: true,
          alignment: AlignmentDirectional.centerEnd,
          icon: const Icon(Icons.expand_more, size: 20),
          value: value,
          items: items,
          onChanged: onChanged,
        ),
      ),
    );
  }
}