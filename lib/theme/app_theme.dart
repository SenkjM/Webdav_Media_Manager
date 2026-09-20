import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Light default palette (浅色系). Teal accent aligns with app icon branding.
/// Info-density cues inspired by Poweramp / Salt Player — not a clone / no trademarked assets.
class AppColors {
  AppColors._();

  /// Soft near-white scaffold / page background.
  static const Color background = Color(0xFFFAFAFA);

  /// Pure white cards / drawer / surfaces.
  static const Color surface = Color(0xFFFFFFFF);

  /// Slightly elevated panels (mini player, list cards).
  static const Color elevated = Color(0xFFF0F0F2);

  /// Higher elevation / tracks / chip fills.
  static const Color elevatedHigh = Color(0xFFE4E4E8);

  /// Brand accent (teal — matches latest icon direction).
  static const Color accent = Color(0xFF2EC4B6);

  static const Color accentBright = Color(0xFF3DD9C9);

  /// Text/icons on accent fills.
  static const Color onAccent = Color(0xFF003832);

  /// Primary body / title text on light surfaces.
  static const Color primaryText = Color(0xFF1A1A1E);

  static const Color secondaryText = Color(0xFF5C5C66);

  static const Color mutedText = Color(0xFF8A8A94);

  /// Track row: audio file already in local cache (light-theme friendly green).
  static const Color localReady = Color(0xFF2E7D32);

  /// Track row: library placeholder — not downloaded yet (soft gray).
  static const Color remotePlaceholder = Color(0xFFB0B0B8);

  static const Color divider = Color(0xFFE0E0E4);

  static const Color error = Color(0xFFE53935);

  // --- Compatibility aliases (existing call sites) ---
  /// Formerly near-black scaffold; now the light page background.
  static const Color nearBlack = background;

  /// Formerly on-dark text; now primary text on light surfaces.
  static const Color onDark = primaryText;
}

class AppTheme {
  AppTheme._();

  /// Default light theme (ThemeMode.light).
  static ThemeData get light {
    const scheme = ColorScheme(
      brightness: Brightness.light,
      primary: AppColors.accent,
      onPrimary: AppColors.onAccent,
      primaryContainer: Color(0xFFC8F5F0),
      onPrimaryContainer: Color(0xFF003832),
      secondary: AppColors.accentBright,
      onSecondary: AppColors.onAccent,
      secondaryContainer: AppColors.elevatedHigh,
      onSecondaryContainer: AppColors.primaryText,
      tertiary: AppColors.accent,
      onTertiary: AppColors.onAccent,
      error: AppColors.error,
      onError: Color(0xFFFFFFFF),
      surface: AppColors.surface,
      onSurface: AppColors.primaryText,
      onSurfaceVariant: AppColors.secondaryText,
      outline: AppColors.mutedText,
      outlineVariant: AppColors.divider,
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: Color(0xFF2A2A30),
      onInverseSurface: Color(0xFFF5F5F7),
      inversePrimary: Color(0xFF7DEDE3),
      surfaceTint: AppColors.accent,
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.background,
      canvasColor: AppColors.surface,
      cardColor: AppColors.elevated,
      dividerColor: AppColors.divider,
      visualDensity: VisualDensity.compact,
    );

    return base.copyWith(
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.primaryText,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
          systemNavigationBarColor: AppColors.background,
          systemNavigationBarIconBrightness: Brightness.dark,
        ),
        titleTextStyle: TextStyle(
          color: AppColors.primaryText,
          fontSize: 18,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
        ),
        iconTheme: IconThemeData(color: AppColors.primaryText),
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
      listTileTheme: ListTileThemeData(
        iconColor: AppColors.secondaryText,
        textColor: AppColors.primaryText,
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        selectedColor: AppColors.accent,
        selectedTileColor: AppColors.accent.withValues(alpha: 0.12),
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
        foregroundColor: AppColors.onAccent,
        elevation: 4,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.accent,
          foregroundColor: AppColors.onAccent,
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
        selectedColor: AppColors.accent.withValues(alpha: 0.22),
        labelStyle: const TextStyle(color: AppColors.primaryText, fontSize: 12),
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: const Color(0xFF2A2A30),
        contentTextStyle: const TextStyle(color: Color(0xFFF5F5F7)),
        actionTextColor: AppColors.accentBright,
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
      textTheme: base.textTheme
          .apply(
            bodyColor: AppColors.primaryText,
            displayColor: AppColors.primaryText,
          )
          .copyWith(
            titleLarge: const TextStyle(
              color: AppColors.primaryText,
              fontWeight: FontWeight.w700,
              fontSize: 20,
              letterSpacing: 0.1,
              height: 1.2,
            ),
            titleMedium: const TextStyle(
              color: AppColors.primaryText,
              fontWeight: FontWeight.w600,
              fontSize: 16,
              letterSpacing: 0.1,
              height: 1.25,
            ),
            titleSmall: const TextStyle(
              color: AppColors.primaryText,
              fontWeight: FontWeight.w600,
              fontSize: 14,
              height: 1.25,
            ),
            bodyLarge: const TextStyle(
              color: AppColors.primaryText,
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
              color: AppColors.primaryText,
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
              return AppColors.onAccent;
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

  /// Optional dark theme for future ThemeMode.system support.
  static ThemeData get dark {
    const nearBlack = Color(0xFF0B0B0D);
    const surface = Color(0xFF121214);
    const elevated = Color(0xFF1A1A1E);
    const elevatedHigh = Color(0xFF222228);
    const accent = Color(0xFF2EC4B6);
    const accentBright = Color(0xFF3DD9C9);
    const onAccent = Color(0xFF003832);
    const onDark = Color(0xFFFFFFFF);
    const secondaryText = Color(0xFFB0B0B8);
    const mutedText = Color(0xFF7A7A82);
    const divider = Color(0xFF2A2A30);
    const error = Color(0xFFEF5350);

    const scheme = ColorScheme(
      brightness: Brightness.dark,
      primary: accent,
      onPrimary: onAccent,
      primaryContainer: Color(0xFF004D47),
      onPrimaryContainer: accentBright,
      secondary: accentBright,
      onSecondary: onAccent,
      secondaryContainer: elevatedHigh,
      onSecondaryContainer: onDark,
      tertiary: accent,
      onTertiary: onAccent,
      error: error,
      onError: onDark,
      surface: surface,
      onSurface: onDark,
      onSurfaceVariant: secondaryText,
      outline: mutedText,
      outlineVariant: divider,
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: Color(0xFFE8E8EC),
      onInverseSurface: nearBlack,
      inversePrimary: Color(0xFF007A70),
      surfaceTint: accent,
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: nearBlack,
      canvasColor: surface,
      cardColor: elevated,
      dividerColor: divider,
      visualDensity: VisualDensity.compact,
    );

    return base.copyWith(
      appBarTheme: const AppBarTheme(
        backgroundColor: nearBlack,
        foregroundColor: onDark,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          systemNavigationBarColor: nearBlack,
          systemNavigationBarIconBrightness: Brightness.light,
        ),
        titleTextStyle: TextStyle(
          color: onDark,
          fontSize: 18,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
        ),
        iconTheme: IconThemeData(color: onDark),
      ),
      drawerTheme: const DrawerThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        color: elevated,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: secondaryText,
        textColor: onDark,
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        selectedColor: accent,
        selectedTileColor: accent.withValues(alpha: 0.14),
      ),
      tabBarTheme: const TabBarThemeData(
        labelColor: accent,
        unselectedLabelColor: mutedText,
        indicatorColor: accent,
        dividerColor: divider,
        labelStyle: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        unselectedLabelStyle:
            TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: accent,
        linearTrackColor: elevatedHigh,
        circularTrackColor: elevatedHigh,
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: accent,
        inactiveTrackColor: elevatedHigh,
        thumbColor: accentBright,
        overlayColor: accent.withValues(alpha: 0.2),
        trackHeight: 4,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: accent,
        foregroundColor: onAccent,
        elevation: 4,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: onAccent,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: accent,
          side: const BorderSide(color: divider),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: accent),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: elevatedHigh,
        selectedColor: accent.withValues(alpha: 0.25),
        labelStyle: const TextStyle(color: onDark, fontSize: 12),
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: elevated,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: elevated,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: elevatedHigh,
        contentTextStyle: const TextStyle(color: onDark),
        actionTextColor: accent,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: elevated,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: divider),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: accent, width: 1.5),
        ),
        labelStyle: const TextStyle(color: secondaryText),
        hintStyle: const TextStyle(color: mutedText),
      ),
      dividerTheme: const DividerThemeData(
        color: divider,
        thickness: 1,
        space: 1,
      ),
      iconTheme: const IconThemeData(color: secondaryText),
      primaryIconTheme: const IconThemeData(color: accent),
      textTheme: base.textTheme
          .apply(bodyColor: onDark, displayColor: onDark)
          .copyWith(
            titleLarge: const TextStyle(
              color: onDark,
              fontWeight: FontWeight.w700,
              fontSize: 20,
              letterSpacing: 0.1,
              height: 1.2,
            ),
            titleMedium: const TextStyle(
              color: onDark,
              fontWeight: FontWeight.w600,
              fontSize: 16,
              letterSpacing: 0.1,
              height: 1.25,
            ),
            titleSmall: const TextStyle(
              color: onDark,
              fontWeight: FontWeight.w600,
              fontSize: 14,
              height: 1.25,
            ),
            bodyLarge: const TextStyle(
              color: onDark,
              fontSize: 15,
              height: 1.3,
            ),
            bodyMedium: const TextStyle(
              color: secondaryText,
              fontSize: 13,
              height: 1.3,
            ),
            bodySmall: const TextStyle(
              color: mutedText,
              fontSize: 12,
              height: 1.3,
            ),
            headlineSmall: const TextStyle(
              color: onDark,
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
              return onAccent;
            }
            return secondaryText;
          }),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return accent;
            }
            return elevated;
          }),
        ),
      ),
    );
  }
}
