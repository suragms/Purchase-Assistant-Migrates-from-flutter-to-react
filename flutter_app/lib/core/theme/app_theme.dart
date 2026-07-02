import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../design_system/hexa_glass_theme.dart';
import 'hexa_colors.dart';
import 'hexa_outline_input_border.dart';

/// Premium theme — navy primary, semantic profit/loss, blue accent for info/links only.
ThemeData buildHexaTheme(Brightness brightness) {
  final isDark = brightness == Brightness.dark;

  final baseScheme = isDark ? _darkScheme() : _lightScheme();
  final baseApplied =
      (isDark ? ThemeData.dark().textTheme : ThemeData.light().textTheme)
          .apply(
    bodyColor: baseScheme.onSurface,
    displayColor: baseScheme.onSurface,
  );
  final baseText = GoogleFonts.plusJakartaSansTextTheme(baseApplied);
  // Harisree / fintech hierarchy — Plus Jakarta Sans (see [GoogleFonts] above).
  final textTheme = baseText.copyWith(
    displayLarge: baseText.displayLarge?.copyWith(
      fontSize: 30,
      fontWeight: FontWeight.w800,
      height: 1.12,
      letterSpacing: -0.8,
    ),
    displayMedium: baseText.displayMedium?.copyWith(
      fontSize: 28,
      fontWeight: FontWeight.w800,
      height: 1.12,
      letterSpacing: -0.7,
    ),
    displaySmall: baseText.displaySmall?.copyWith(
      fontSize: 24,
      fontWeight: FontWeight.w800,
      height: 1.15,
      letterSpacing: -0.55,
    ),
    headlineLarge: baseText.headlineLarge?.copyWith(
      fontSize: 26,
      fontWeight: FontWeight.w800,
      height: 1.18,
      letterSpacing: -0.5,
    ),
    headlineMedium: baseText.headlineMedium?.copyWith(
      fontSize: 22,
      fontWeight: FontWeight.w700,
      height: 1.22,
      letterSpacing: -0.35,
    ),
    headlineSmall: baseText.headlineSmall?.copyWith(
      fontSize: 18,
      fontWeight: FontWeight.w700,
      height: 1.25,
      letterSpacing: -0.25,
    ),
    titleLarge: baseText.titleLarge?.copyWith(
      fontSize: 18,
      fontWeight: FontWeight.w800,
      height: 1.2,
      letterSpacing: -0.2,
    ),
    titleMedium: baseText.titleMedium?.copyWith(
      fontSize: 16,
      fontWeight: FontWeight.w700,
      height: 1.25,
      letterSpacing: -0.12,
    ),
    titleSmall: baseText.titleSmall?.copyWith(
      fontSize: 15,
      fontWeight: FontWeight.w700,
      height: 1.28,
    ),
    bodyLarge: baseText.bodyLarge?.copyWith(
      fontSize: 16,
      fontWeight: FontWeight.w500,
      height: 1.4,
    ),
    bodyMedium: baseText.bodyMedium?.copyWith(
      fontSize: 15,
      fontWeight: FontWeight.w500,
      height: 1.4,
    ),
    bodySmall: baseText.bodySmall?.copyWith(
      fontSize: 14,
      fontWeight: FontWeight.w400,
      height: 1.42,
      letterSpacing: 0.01,
    ),
    labelLarge: baseText.labelLarge?.copyWith(
      fontSize: 14,
      fontWeight: FontWeight.w600,
      height: 1.2,
      letterSpacing: 0.1,
    ),
    labelMedium: baseText.labelMedium?.copyWith(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      height: 1.22,
    ),
    labelSmall: baseText.labelSmall?.copyWith(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      height: 1.2,
      letterSpacing: 0.12,
    ),
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    fontFamily: GoogleFonts.plusJakartaSans().fontFamily,
    colorScheme: baseScheme,
    splashFactory: InkRipple.splashFactory,
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: CupertinoPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.windows: CupertinoPageTransitionsBuilder(),
        TargetPlatform.linux: CupertinoPageTransitionsBuilder(),
      },
    ),
    scaffoldBackgroundColor:
        isDark ? HexaColors.canvas : Colors.transparent,
    extensions: <ThemeExtension<dynamic>>[
      isDark ? HexaGlassTheme.dark() : HexaGlassTheme.light(),
    ],
    textTheme: textTheme.copyWith(
      titleLarge: textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: -0.3,
        color: baseScheme.onSurface,
      ),
      titleMedium: textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w800,
        color: baseScheme.onSurface,
      ),
      titleSmall: textTheme.titleSmall?.copyWith(
        fontWeight: FontWeight.w700,
        color: baseScheme.onSurface,
      ),
      bodyLarge: textTheme.bodyLarge?.copyWith(
        height: 1.35,
        fontWeight: FontWeight.w500,
      ),
      bodyMedium: textTheme.bodyMedium?.copyWith(
        height: 1.35,
        color: isDark ? baseScheme.onSurfaceVariant : HexaColors.textBody,
        fontWeight: FontWeight.w500,
      ),
      bodySmall: textTheme.bodySmall?.copyWith(
        color: isDark ? baseScheme.onSurfaceVariant : HexaColors.neutral,
        fontWeight: FontWeight.w400,
      ),
      labelLarge: textTheme.labelLarge?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: 0.15,
      ),
      labelMedium: textTheme.labelMedium?.copyWith(
        fontWeight: FontWeight.w500,
        color: baseScheme.onSurfaceVariant,
      ),
      labelSmall: textTheme.labelSmall?.copyWith(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: baseScheme.onSurfaceVariant.withValues(alpha: 0.88),
        letterSpacing: 0.15,
      ),
    ),
    appBarTheme: AppBarTheme(
      elevation: 0,
      scrolledUnderElevation: 0.5,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      backgroundColor: Colors.transparent,
      toolbarHeight: 56,
      titleSpacing: 16,
      foregroundColor: isDark ? baseScheme.onSurface : HexaColors.brandPrimary,
      titleTextStyle: textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: -0.35,
        color: baseScheme.onSurface,
      ),
    ),
    tabBarTheme: TabBarThemeData(
      indicatorSize: TabBarIndicatorSize.tab,
      dividerColor: Colors.transparent,
      labelColor: baseScheme.primary,
      unselectedLabelColor: baseScheme.onSurfaceVariant,
      indicator: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: baseScheme.primary.withValues(alpha: isDark ? 0.22 : 0.16),
      ),
      labelStyle: textTheme.labelLarge
          ?.copyWith(fontWeight: FontWeight.w800, letterSpacing: 0.2),
      unselectedLabelStyle:
          textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
    ),
    cardTheme: CardThemeData(
      color: isDark ? HexaColors.surfaceCard : HexaColors.surfaceCardLight,
      surfaceTintColor: Colors.transparent,
      elevation: isDark ? 0 : 3,
      shadowColor: isDark
          ? Colors.transparent
          : HexaColors.brandPrimary.withValues(alpha: 0.10),
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
            color: baseScheme.outlineVariant
                .withValues(alpha: isDark ? 0.35 : 0.42)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
        tapTargetSize: MaterialTapTargetSize.padded,
        elevation: WidgetStateProperty.resolveWith((s) {
          if (s.contains(WidgetState.disabled)) return 0.0;
          if (s.contains(WidgetState.pressed)) return 0.0;
          if (s.contains(WidgetState.hovered)) return 4.0;
          return 2.0;
        }),
        shadowColor: WidgetStateProperty.resolveWith((s) {
          if (s.contains(WidgetState.disabled) ||
              s.contains(WidgetState.pressed)) {
            return Colors.transparent;
          }
          return HexaColors.brandPrimary.withValues(alpha: 0.35);
        }),
        padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 22, vertical: 14)),
        shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
        textStyle: WidgetStatePropertyAll(
            textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
        backgroundColor: WidgetStateProperty.resolveWith((s) {
          if (s.contains(WidgetState.disabled)) {
            return HexaColors.brandDisabledBg;
          }
          if (s.contains(WidgetState.pressed)) {
            return HexaColors.brandSecondary;
          }
          if (s.contains(WidgetState.hovered)) {
            return HexaColors.brandHover;
          }
          return HexaColors.brandPrimary;
        }),
        foregroundColor: WidgetStateProperty.resolveWith((s) {
          if (s.contains(WidgetState.disabled)) {
            return HexaColors.brandDisabledText;
          }
          return Colors.white;
        }),
        overlayColor: WidgetStateProperty.resolveWith((s) {
          if (s.contains(WidgetState.pressed)) {
            return Colors.white.withValues(alpha: 0.14);
          }
          return Colors.white.withValues(alpha: 0.08);
        }),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
        tapTargetSize: MaterialTapTargetSize.padded,
        padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 16, vertical: 14)),
        shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
        side: const WidgetStatePropertyAll(
            BorderSide(color: HexaColors.brandAccent)),
        backgroundColor: WidgetStateProperty.resolveWith((s) {
          final base = Colors.transparent;
          if (s.contains(WidgetState.pressed)) {
            return Color.alphaBlend(
                HexaColors.brandAccent.withValues(alpha: 0.14), base);
          }
          if (s.contains(WidgetState.hovered)) {
            return Color.alphaBlend(
                HexaColors.brandAccent.withValues(alpha: 0.10), base);
          }
          return base;
        }),
        foregroundColor: WidgetStateProperty.resolveWith((s) {
          if (s.contains(WidgetState.disabled)) {
            return HexaColors.brandDisabledText;
          }
          return HexaColors.brandAccent;
        }),
        overlayColor: WidgetStateProperty.resolveWith((s) {
          if (s.contains(WidgetState.pressed)) {
            return HexaColors.brandAccent.withValues(alpha: 0.18);
          }
          return HexaColors.brandAccent.withValues(alpha: 0.08);
        }),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 72,
      elevation: 0,
      backgroundColor:
          isDark ? HexaColors.surfaceCard : baseScheme.surfaceContainer,
      indicatorColor:
          baseScheme.primaryContainer.withValues(alpha: isDark ? 0.45 : 0.65),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return textTheme.labelMedium?.copyWith(
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          letterSpacing: 0.15,
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return IconThemeData(
          size: 24,
          color: selected
              ? baseScheme.onPrimaryContainer
              : baseScheme.onSurfaceVariant,
        );
      }),
    ),
    inputDecorationTheme: _hexaInputDecorationTheme(
      textTheme: textTheme,
      baseScheme: baseScheme,
      isDark: isDark,
    ),
    searchBarTheme: SearchBarThemeData(
      backgroundColor: WidgetStatePropertyAll(
          isDark ? HexaColors.surfaceElevated : Colors.white),
      surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
      elevation: const WidgetStatePropertyAll(0),
      shadowColor: const WidgetStatePropertyAll(Colors.transparent),
      side: WidgetStatePropertyAll(
        BorderSide(
          color: isDark
              ? baseScheme.outlineVariant.withValues(alpha: 0.75)
              : HexaColors.inputBorderGrey,
        ),
      ),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      hintStyle: WidgetStatePropertyAll(
        textTheme.bodyMedium?.copyWith(
          color: isDark
              ? baseScheme.onSurfaceVariant.withValues(alpha: 0.9)
              : HexaColors.inputHint,
          fontWeight: FontWeight.w400,
        ),
      ),
      textStyle: WidgetStatePropertyAll(
        textTheme.bodyMedium?.copyWith(
          color: isDark ? baseScheme.onSurface : HexaColors.inputText,
          fontWeight: FontWeight.w500,
        ),
      ),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    ),
    listTileTheme: ListTileThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      minVerticalPadding: 12,
    ),
    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 450),
      showDuration: const Duration(seconds: 3),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      verticalOffset: 10,
      textStyle: textTheme.labelSmall?.copyWith(
        color: Colors.white,
        fontWeight: FontWeight.w600,
        fontSize: 12,
        height: 1.25,
      ),
      decoration: BoxDecoration(
        color: HexaColors.brandPrimary.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(10),
      ),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: HexaColors.brandAccent,
      linearTrackColor: HexaColors.brandBorder.withValues(alpha: 0.65),
      circularTrackColor: HexaColors.brandBorder.withValues(alpha: 0.65),
    ),
    dividerTheme: DividerThemeData(
        color: baseScheme.outlineVariant.withValues(alpha: 0.45)),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      elevation: 0,
      highlightElevation: 0,
      backgroundColor: baseScheme.tertiary,
      foregroundColor: baseScheme.onTertiary,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: isDark ? HexaColors.surfaceCard : Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      showDragHandle: true,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: isDark ? HexaColors.surfaceCard : Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: isDark ? HexaColors.surfaceElevated : const Color(0xFF1E293B),
      contentTextStyle:
          textTheme.bodyMedium?.copyWith(color: Colors.white),
      actionTextColor: const Color(0xFF5EEAD4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 6,
    ),
    chipTheme: ChipThemeData(
      backgroundColor:
          isDark ? HexaColors.surfaceElevated : HexaColors.surfaceCardLight,
      selectedColor: baseScheme.primaryContainer,
      secondarySelectedColor: baseScheme.primaryContainer,
      disabledColor: baseScheme.surfaceContainer,
      side:
          BorderSide(color: baseScheme.outlineVariant.withValues(alpha: 0.75)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      labelStyle: textTheme.labelMedium?.copyWith(color: baseScheme.onSurface),
      secondaryLabelStyle:
          textTheme.labelMedium?.copyWith(color: baseScheme.onPrimaryContainer),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      brightness: brightness,
    ),
    iconButtonTheme: IconButtonThemeData(
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
        padding: const WidgetStatePropertyAll(EdgeInsets.all(12)),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        overlayColor: WidgetStateProperty.resolveWith((s) {
          if (s.contains(WidgetState.hovered)) {
            return HexaColors.brandPrimary.withValues(alpha: 0.08);
          }
          if (s.contains(WidgetState.focused)) {
            return HexaColors.brandAccent.withValues(alpha: 0.12);
          }
          return HexaColors.brandPrimary.withValues(alpha: 0.06);
        }),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(48, 40)),
        padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
        tapTargetSize: MaterialTapTargetSize.padded,
        foregroundColor: WidgetStateProperty.resolveWith((s) {
          if (s.contains(WidgetState.disabled)) {
            return HexaColors.brandDisabledText;
          }
          if (s.contains(WidgetState.pressed)) {
            return HexaColors.brandSecondary;
          }
          if (s.contains(WidgetState.hovered)) {
            return HexaColors.brandAccent;
          }
          return HexaColors.brandAccent;
        }),
        overlayColor: WidgetStateProperty.resolveWith((s) {
          if (s.contains(WidgetState.hovered)) {
            return HexaColors.brandAccent.withValues(alpha: 0.10);
          }
          return Colors.transparent;
        }),
      ),
    ),
    // Slightly roomier than compact; still dense enough for business UIs.
    visualDensity: VisualDensity.standard,
  );
}

InputDecorationTheme _hexaInputDecorationTheme({
  required TextTheme textTheme,
  required ColorScheme baseScheme,
  required bool isDark,
}) {
  const radius = BorderRadius.all(Radius.circular(12));
  final defaultSide = BorderSide(
    color: isDark ? const Color(0xFF475569) : HexaColors.inputBorderGrey,
    width: 1,
  );
  const focusSide = BorderSide(color: HexaColors.brandAccent, width: 2);
  final focusRingColor = isDark
      ? HexaColors.brandAccent.withValues(alpha: 0.42)
      : HexaColors.inputFocusRing;

  HexaOutlineInputBorder outlineRest() => HexaOutlineInputBorder(
        borderRadius: radius,
        borderSide: defaultSide,
        focusRing: false,
      );

  return InputDecorationTheme(
    filled: true,
    fillColor: isDark ? const Color(0xFF1E293B) : Colors.white,
    isDense: true,
    border: outlineRest(),
    enabledBorder: outlineRest(),
    focusedBorder: HexaOutlineInputBorder(
      borderRadius: radius,
      borderSide: focusSide,
      focusRing: true,
      ringColor: focusRingColor,
    ),
    disabledBorder: HexaOutlineInputBorder(
      borderRadius: radius,
      borderSide: BorderSide(
        color: defaultSide.color.withValues(alpha: isDark ? 0.35 : 0.5),
        width: 1,
      ),
      focusRing: false,
    ),
    errorBorder: HexaOutlineInputBorder(
      borderRadius: radius,
      borderSide: BorderSide(
        color: HexaColors.loss.withValues(alpha: 0.92),
        width: 1,
      ),
      focusRing: false,
    ),
    focusedErrorBorder: const HexaOutlineInputBorder(
      borderRadius: radius,
      borderSide: BorderSide(color: HexaColors.loss, width: 2),
      focusRing: true,
      ringColor: HexaColors.inputErrorFocusRing,
    ),
    contentPadding:
        const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
    labelStyle: textTheme.bodyMedium?.copyWith(
      color: baseScheme.onSurfaceVariant,
      fontWeight: FontWeight.w600,
    ),
    floatingLabelStyle: textTheme.bodySmall?.copyWith(
      color: HexaColors.brandAccent,
      fontWeight: FontWeight.w700,
    ),
    hintStyle: textTheme.bodyMedium?.copyWith(
      color: isDark
          ? baseScheme.onSurfaceVariant.withValues(alpha: 0.88)
          : HexaColors.inputHint,
      fontWeight: FontWeight.w400,
    ),
    prefixIconColor: WidgetStateColor.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) {
        return baseScheme.onSurfaceVariant.withValues(alpha: 0.45);
      }
      if (states.contains(WidgetState.focused)) {
        return HexaColors.brandAccent;
      }
      return baseScheme.onSurfaceVariant;
    }),
    suffixIconColor: WidgetStateColor.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) {
        return baseScheme.onSurfaceVariant.withValues(alpha: 0.45);
      }
      if (states.contains(WidgetState.focused)) {
        return HexaColors.brandAccent;
      }
      return baseScheme.onSurfaceVariant;
    }),
  );
}

ColorScheme _lightScheme() {
  return const ColorScheme(
    brightness: Brightness.light,
    primary: HexaColors.brandPrimary,
    onPrimary: Colors.white,
    primaryContainer: Color(0xFFD8ECE8),
    onPrimaryContainer: HexaColors.brandPrimary,
    secondary: HexaColors.brandAccent,
    onSecondary: Colors.white,
    secondaryContainer: Color(0xFFD7F2EE),
    onSecondaryContainer: HexaColors.brandPrimary,
    tertiary: HexaColors.brandAccent,
    onTertiary: Colors.white,
    tertiaryContainer: Color(0xFFD7F2EE),
    onTertiaryContainer: HexaColors.brandPrimary,
    error: HexaColors.loss,
    onError: Colors.white,
    surface: HexaColors.surfaceCardLight,
    onSurface: HexaColors.inputText,
    surfaceContainerHighest: HexaColors.surfaceCardLight,
    surfaceContainerHigh: Color(0xFFF0F5F3),
    surfaceContainer: Color(0xFFF3F7F5),
    onSurfaceVariant: HexaColors.neutral,
    outline: Color(0xFFB8D2CD),
    outlineVariant: Color(0xFFD7E7E3),
  );
}

ColorScheme _darkScheme() {
  return const ColorScheme(
    brightness: Brightness.dark,
    primary: HexaColors.primaryMid,
    onPrimary: Colors.white,
    primaryContainer: Color(0xFF10302F),
    onPrimaryContainer: Color(0xFFB8F0EF),
    secondary: HexaColors.accentPurple,
    onSecondary: Colors.white,
    secondaryContainer: Color(0xFF3D2A6B),
    onSecondaryContainer: Color(0xFFE9D5FF),
    tertiary: Color(0xFF5EEAD4),
    onTertiary: Color(0xFF042A28),
    error: HexaColors.loss,
    onError: Color(0xFF450A0A),
    surface: HexaColors.canvas,
    onSurface: HexaColors.textPrimary,
    surfaceContainerHighest: HexaColors.surfaceElevated,
    surfaceContainerHigh: HexaColors.surfaceCard,
    surfaceContainer: HexaColors.surfaceMuted,
    onSurfaceVariant: HexaColors.textSecondary,
    outline: Color(0xFF475569),
    outlineVariant: Color(0xFF334155),
  );
}
