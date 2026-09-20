import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Poweramp-inspired dark theme (appearance cues only — not a clone / no trademarked assets).
class AppColors {
  AppColors._();

  static const Color nearBlack = Color(0xFF0B0B0D);
  static const Color surface = Color(0xFF121214);
  static const Color elevated = Color(0xFF1A1A1E);
  static const Color elevatedHigh = Color(0xFF222228);
  static const Color accent = Color(0xFFFF9800);
  static const Color accentBright = Color(0xFFFFB300);
  static const Color onDark = Color(0xFFFFFFFF);
  static const Color secondaryText = Color(0xFFB0B0B8);
  static const Color mutedText = Color(0xFF7A7A82);
  static const Color divider = Color(0xFF2A2A30);
  static const Color error = Color(0xFFEF5350);
}

class AppTheme {
  AppTheme._();

  static ThemeData get dark {
    const scheme = ColorScheme(
      brightness: Brightness.dark,
      primary: AppColors.accent,
      onPrimary: Color(0xFF1A1000),
      primaryContainer: Color(0xFF3D2A00),
      onPrimaryContainer: AppColors.accentBright,
      secondary: AppColors.accentBright,
      onSecondary: Color(0xFF1A1000),
      secondaryContainer: AppColors.elevatedHigh,
      onSecondaryContainer: AppColors.onDark,
      tertiary: AppColors.accent,
      onTertiary: Color(0xFF1A1000),
      error: AppColors.error,
      onError: AppColors.onDark,
      surface: AppColors.surface,
      onSurface: AppColors.onDark,
      onSurfaceVariant: AppColors.secondaryText,
      outline: AppColors.mutedText,
      outlineVariant: AppColors.divider,
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: Color(0xFFE8E8EC),
      onInverseSurface: AppColors.nearBlack,
      inversePrimary: Color(0xFF7A4F00),
      surfaceTint: AppColors.accent,
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.nearBlack,
      canvasColor: AppColors.surface,
      cardColor: AppColors.elevated,
      dividerColor: AppColors.divider,
      visualDensity: VisualDensity.compact,
    );

    return base.copyWith(
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.nearBlack,
        foregroundColor: AppColors.onDark,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          systemNavigationBarColor: AppColors.nearBlack,
          systemNavigationBarIconBrightness: Brightness.light,
        ),
        titleTextStyle: TextStyle(
          color: AppColors.onDark,
          fontSize: 18,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
        ),
        iconTheme: IconThemeData(color: AppColors.onDark),
      ),
      drawerTheme: const DrawerThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        color: AppColors.elevated,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: AppColors.secondaryText,
        textColor: AppColors.onDark,
        dense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        selectedColor: AppColors.accent,
        selectedTileColor: Color(0x22FF9800),
      ),
      tabBarTheme: const TabBarThemeData(
        labelColor: AppColors.accent,
        unselectedLabelColor: AppColors.mutedText,
        indicatorColor: AppColors.accent,
        dividerColor: AppColors.divider,
        labelStyle: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        unselectedLabelStyle:
            TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.accent,
        linearTrackColor: AppColors.elevatedHigh,
        circularTrackColor: AppColors.elevatedHigh,
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: AppColors.accent,
        inactiveTrackColor: AppColors.elevatedHigh,
        thumbColor: AppColors.accentBright,
        overlayColor: AppColors.accent.withValues(alpha: 0.2),
        trackHeight: 4,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.accent,
        foregroundColor: Color(0xFF1A1000),
        elevation: 4,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.accent,
          foregroundColor: const Color(0xFF1A1000),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.accent,
          side: const BorderSide(color: AppColors.divider),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: AppColors.accent),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.elevatedHigh,
        selectedColor: AppColors.accent.withValues(alpha: 0.25),
        labelStyle: const TextStyle(color: AppColors.onDark, fontSize: 12),
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.elevated,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.elevated,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.elevatedHigh,
        contentTextStyle: const TextStyle(color: AppColors.onDark),
        actionTextColor: AppColors.accent,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.elevated,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.divider),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.accent, width: 1.5),
        ),
        labelStyle: const TextStyle(color: AppColors.secondaryText),
        hintStyle: const TextStyle(color: AppColors.mutedText),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.divider,
        thickness: 1,
        space: 1,
      ),
      iconTheme: const IconThemeData(color: AppColors.secondaryText),
      primaryIconTheme: const IconThemeData(color: AppColors.accent),
      textTheme: base.textTheme.apply(
        bodyColor: AppColors.onDark,
        displayColor: AppColors.onDark,
      ).copyWith(
        titleLarge: const TextStyle(
          color: AppColors.onDark,
          fontWeight: FontWeight.w700,
          fontSize: 20,
          letterSpacing: 0.1,
          height: 1.2,
        ),
        titleMedium: const TextStyle(
          color: AppColors.onDark,
          fontWeight: FontWeight.w600,
          fontSize: 16,
          letterSpacing: 0.1,
          height: 1.25,
        ),
        titleSmall: const TextStyle(
          color: AppColors.onDark,
          fontWeight: FontWeight.w600,
          fontSize: 14,
          height: 1.25,
        ),
        bodyLarge: const TextStyle(
          color: AppColors.onDark,
          fontSize: 15,
          height: 1.3,
        ),
        bodyMedium: const TextStyle(
          color: AppColors.secondaryText,
          fontSize: 13,
          height: 1.3,
        ),
        bodySmall: const TextStyle(
          color: AppColors.mutedText,
          fontSize: 12,
          height: 1.3,
        ),
        headlineSmall: const TextStyle(
          color: AppColors.onDark,
          fontWeight: FontWeight.w700,
          fontSize: 22,
          letterSpacing: 0.1,
          height: 1.2,
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return const Color(0xFF1A1000);
            }
            return AppColors.secondaryText;
          }),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return AppColors.accent;
            }
            return AppColors.elevated;
          }),
        ),
      ),
    );
  }
}
