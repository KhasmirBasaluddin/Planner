import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../shared/utils/planner_colors.dart';

/// The app theme.
///
/// Two deliberate choices shape the feel:
///  * A tight type scale with negative tracking on headings. Default Material
///    sizing is built for touch; this is a dense desktop tool, so text is
///    smaller and line heights are tighter.
///  * Hairline borders plus low, tinted shadows instead of Material elevation
///    overlays, which keeps surfaces crisp rather than washed grey.
ThemeData buildAppTheme() {
  final base = GoogleFonts.interTextTheme();

  final textTheme = base
      .copyWith(
        displaySmall: base.displaySmall?.copyWith(
          fontSize: 28,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.8,
          height: 1.2,
        ),
        headlineSmall: base.headlineSmall?.copyWith(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.4,
        ),
        titleLarge: base.titleLarge?.copyWith(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
        ),
        titleMedium: base.titleMedium?.copyWith(
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
        bodyLarge: base.bodyLarge?.copyWith(fontSize: 14, height: 1.5),
        bodyMedium: base.bodyMedium?.copyWith(fontSize: 13, height: 1.5),
        bodySmall: base.bodySmall?.copyWith(fontSize: 12, height: 1.45),
        labelLarge: base.labelLarge?.copyWith(
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
        labelSmall: base.labelSmall?.copyWith(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
        ),
      )
      .apply(bodyColor: plannerText, displayColor: plannerInk);

  return ThemeData(
    useMaterial3: true,
    scaffoldBackgroundColor: plannerSurface,
    textTheme: textTheme,
    // InkRipple, not InkSparkle: the sparkle splash needs a fragment shader
    // (`shaders/ink_sparkle.frag`) that is not bundled on Windows desktop, and
    // its absence throws on every tap.
    splashFactory: InkRipple.splashFactory,
    dividerColor: plannerDivider,
    colorScheme: ColorScheme.fromSeed(
      seedColor: plannerBlue,
      primary: plannerBlue,
      surface: plannerCard,
      error: plannerRed,
    ),
    // Material's default hover/focus tints are too heavy on a dense grid.
    hoverColor: plannerHover,
    focusColor: tint(plannerBlue, 0.08),
    splashColor: tint(plannerBlue, 0.10),
    highlightColor: Colors.transparent,

    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: plannerBlue,
        foregroundColor: Colors.white,
        disabledBackgroundColor: plannerBorder,
        disabledForegroundColor: plannerFaint,
        elevation: 0,
        textStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.1,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
        minimumSize: const Size(0, 36),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusSm),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: plannerText,
        backgroundColor: plannerCard,
        side: const BorderSide(color: plannerBorder),
        textStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.1,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
        minimumSize: const Size(0, 36),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusSm),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: plannerText,
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        minimumSize: const Size(0, 36),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusSm),
        ),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: plannerMuted,
        minimumSize: const Size(32, 32),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusSm),
        ),
      ),
    ),

    dialogTheme: DialogThemeData(
      backgroundColor: plannerCard,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shadowColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusLg),
        side: const BorderSide(color: plannerBorder),
      ),
      titleTextStyle: const TextStyle(
        color: plannerInk,
        fontSize: 16,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
      ),
      contentTextStyle: const TextStyle(
        color: plannerText,
        fontSize: 13,
        height: 1.55,
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: plannerCard,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusMd),
        side: const BorderSide(color: plannerBorder),
      ),
      textStyle: const TextStyle(
        color: plannerText,
        fontSize: 13,
        fontWeight: FontWeight.w500,
      ),
    ),
    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 450),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      textStyle: const TextStyle(
        color: Colors.white,
        fontSize: 11.5,
        fontWeight: FontWeight.w500,
      ),
      decoration: BoxDecoration(
        color: plannerInk,
        borderRadius: BorderRadius.circular(radiusSm),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: plannerInk,
      contentTextStyle: const TextStyle(color: Colors.white, fontSize: 13),
      actionTextColor: const Color(0xFF9FB0FF),
      behavior: SnackBarBehavior.floating,
      elevation: 0,
      // A floating snackbar defaults to the full window width on desktop, which
      // reads as a broken banner rather than a transient message. Capping it and
      // pinning it to one corner keeps it looking deliberate.
      width: 420,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusMd),
      ),
    ),

    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: plannerCard,
      hintStyle: const TextStyle(
        color: plannerFaint,
        fontSize: 13,
        fontWeight: FontWeight.w400,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      isDense: true,
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusSm),
        borderSide: const BorderSide(color: plannerBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusSm),
        borderSide: const BorderSide(color: plannerBlue, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusSm),
        borderSide: const BorderSide(color: plannerRed),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusSm),
        borderSide: const BorderSide(color: plannerRed, width: 1.5),
      ),
      errorStyle: const TextStyle(color: plannerRed, fontSize: 11.5),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusSm),
        borderSide: const BorderSide(color: plannerBorder),
      ),
    ),

    checkboxTheme: CheckboxThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusXs),
      ),
      side: const BorderSide(color: plannerFaint, width: 1.5),
    ),
    dividerTheme: const DividerThemeData(
      color: plannerDivider,
      thickness: 1,
      space: 1,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: plannerBlue,
      linearMinHeight: 6,
    ),
    scrollbarTheme: ScrollbarThemeData(
      thickness: WidgetStateProperty.all(8),
      radius: const Radius.circular(radiusXs),
      thumbColor: WidgetStateProperty.resolveWith((states) {
        return states.contains(WidgetState.hovered)
            ? plannerFaint
            : plannerBorder;
      }),
    ),
  );
}
