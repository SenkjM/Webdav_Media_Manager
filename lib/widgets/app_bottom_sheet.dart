import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Shared bottom-sheet shell.
///
/// Every sheet in this app that is just a stack of tiles has to be scrollable:
/// those stacks are tall enough that a short window (or a raised keyboard) made
/// them overflow with `A RenderFlex overflowed by N pixels`. Wrapping each one in
/// [SingleChildScrollView] by hand was easy to forget, so all of them go through
/// here.
///
/// For sheets that manage their own scrolling (a real `ListView`, a fixed-height
/// preview), pass [scrollable] = false.
class AppBottomSheet extends StatelessWidget {
  const AppBottomSheet({
    super.key,
    required this.child,
    this.scrollable = true,
    this.padding = const EdgeInsets.fromLTRB(16, 8, 16, 16),
  });

  final Widget child;
  final bool scrollable;
  final EdgeInsets padding;

  /// Standard rounded surface used by every sheet in the app.
  static RoundedRectangleBorder get shape => const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      );

  /// Drag handle shown at the top of a sheet.
  static Widget handle() => Center(
        child: Container(
          width: 36,
          height: 4,
          margin: const EdgeInsets.only(top: 8, bottom: 4),
          decoration: BoxDecoration(
            color: AppColors.divider,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final content = Padding(padding: padding, child: child);
    return SafeArea(
      child: scrollable
          // `shrinkWrap` + min-size column: the sheet stays as short as its
          // content, but scrolls instead of overflowing once it does not fit.
          ? SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [handle(), content],
              ),
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [handle(), content],
            ),
    );
  }
}
