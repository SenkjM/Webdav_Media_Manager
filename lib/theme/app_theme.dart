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

  /// Brand seed. Callers that do not pass a seed keep the existing teal.
  static const Color defaultSeed = Color(0xFF2EC4B6);

  /// Default light theme (ThemeMode.light).
  static ThemeData get light => lightFrom(defaultSeed);

  /// Dark theme used when [ThemeMode.dark] or the system is dark.
  static ThemeData get dark => darkFrom(defaultSeed);

  static ThemeData lightFrom(Color seed) => _build(seed, Brightness.light);

  static ThemeData darkFrom(Color seed) => _build(seed, Brightness.dark);

  /// Classic M3 tonal scheme. [DynamicSchemeVariant.fidelity] keeps a bright
  /// seed (the default teal) from being flattened into a pastel primary.
  /// Not the expressive variant.
  static ThemeData _build(Color seed, Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
      dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
    );
    final onSurface = scheme.onSurface;
    final variant = scheme.onSurfaceVariant;
    final muted = scheme.outline;
    final accent = scheme.primary;
    final onAccent = scheme.onPrimary;
    final page = scheme.surface;
    final panel = scheme.surfaceContainerLow;
    final panelHigh = scheme.surfaceContainerHigh;
    final line = scheme.outlineVariant;
    final isDark = brightness == Brightness.dark;

    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: page,
      canvasColor: page,
      cardColor: panel,
      dividerColor: line,
      visualDensity: VisualDensity.compact,
    );

    final radius10 = BorderRadius.circular(10);
    final radius8 = BorderRadius.circular(8);

    return base.copyWith(
      appBarTheme: AppBarTheme(
        backgroundColor: page,
        foregroundColor: onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
          systemNavigationBarColor: page,
          systemNavigationBarIconBrightness: isDark
              ? Brightness.light
              : Brightness.dark,
        ),
        titleTextStyle: TextStyle(
          color: onSurface,
          fontSize: 18,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
        ),
        iconTheme: IconThemeData(color: onSurface),
      ),
      drawerTheme: DrawerThemeData(
        backgroundColor: page,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        color: panel,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: radius10),
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: variant,
        textColor: onSurface,
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        selectedColor: accent,
        selectedTileColor: accent.withValues(alpha: isDark ? 0.14 : 0.12),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: accent,
        unselectedLabelColor: muted,
        indicatorColor: accent,
        dividerColor: line,
        labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        unselectedLabelStyle: const TextStyle(
          fontWeight: FontWeight.w500,
          fontSize: 14,
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: accent,
        linearTrackColor: panelHigh,
        circularTrackColor: panelHigh,
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: accent,
        inactiveTrackColor: panelHigh,
        thumbColor: accent,
        overlayColor: accent.withValues(alpha: 0.2),
        trackHeight: 4,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: accent,
        foregroundColor: onAccent,
        elevation: 4,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: onAccent,
          shape: RoundedRectangleBorder(borderRadius: radius10),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: accent,
          side: BorderSide(color: line),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: accent),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: panelHigh,
        selectedColor: accent.withValues(alpha: isDark ? 0.25 : 0.22),
        labelStyle: TextStyle(color: onSurface, fontSize: 12),
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: radius8),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: isDark ? panel : page,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: isDark ? panel : page,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      popupMenuTheme: const PopupMenuThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(10)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: TextStyle(color: scheme.onInverseSurface),
        actionTextColor: scheme.inversePrimary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: radius10),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: panel,
        border: OutlineInputBorder(
          borderRadius: radius10,
          borderSide: BorderSide(color: line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: radius10,
          borderSide: BorderSide(color: line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: radius10,
          borderSide: BorderSide(color: accent, width: 1.5),
        ),
        labelStyle: TextStyle(color: variant),
        hintStyle: TextStyle(color: muted),
      ),
      dividerTheme: DividerThemeData(color: line, thickness: 1, space: 1),
      iconTheme: IconThemeData(color: variant),
      primaryIconTheme: IconThemeData(color: accent),
      textTheme: base.textTheme
          .apply(bodyColor: onSurface, displayColor: onSurface)
          .copyWith(
            titleLarge: TextStyle(
              color: onSurface,
              fontWeight: FontWeight.w700,
              fontSize: 20,
              letterSpacing: 0.1,
              height: 1.2,
            ),
            titleMedium: TextStyle(
              color: onSurface,
              fontWeight: FontWeight.w600,
              fontSize: 16,
              letterSpacing: 0.1,
              height: 1.25,
            ),
            titleSmall: TextStyle(
              color: onSurface,
              fontWeight: FontWeight.w600,
              fontSize: 14,
              height: 1.25,
            ),
            bodyLarge: TextStyle(color: onSurface, fontSize: 15, height: 1.3),
            bodyMedium: TextStyle(color: variant, fontSize: 13, height: 1.3),
            bodySmall: TextStyle(
              color: scheme.onSurfaceVariant,
              fontSize: 12,
              height: 1.3,
            ),
            labelMedium: TextStyle(
              color: scheme.onSurfaceVariant,
              fontSize: 12,
              fontWeight: FontWeight.w500,
              height: 1.3,
            ),
            headlineSmall: TextStyle(
              color: onSurface,
              fontWeight: FontWeight.w700,
              fontSize: 22,
              letterSpacing: 0.1,
              height: 1.2,
            ),
          ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) return onAccent;
            return variant;
          }),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) return accent;
            return panel;
          }),
        ),
      ),
    );
  }
}
