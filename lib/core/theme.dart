import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../shared/utils/planner_colors.dart';

ThemeData buildAppTheme() {
  final textTheme = GoogleFonts.interTextTheme().apply(
    bodyColor: plannerText,
    displayColor: plannerInk,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(seedColor: plannerBlue),
    scaffoldBackgroundColor: plannerSurface,
    textTheme: textTheme,
    splashFactory: InkRipple.splashFactory,
    dividerColor: plannerBorder,
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: plannerBlue,
        foregroundColor: Colors.white,
        elevation: 0,
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        minimumSize: const Size(0, 36),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: plannerText,
        side: const BorderSide(color: plannerBorder),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        minimumSize: const Size(0, 36),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: plannerText,
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        minimumSize: const Size(0, 36),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      elevation: 8,
      shadowColor: const Color(0x33101828),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: Colors.white,
      surfaceTintColor: Colors.white,
      elevation: 4,
      shadowColor: const Color(0x29101828),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: plannerBorder),
      ),
      textStyle: const TextStyle(
        color: plannerText,
        fontSize: 13,
        fontWeight: FontWeight.w500,
      ),
    ),
    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 500),
      textStyle: const TextStyle(color: Colors.white, fontSize: 12),
      decoration: BoxDecoration(
        color: plannerInk,
        borderRadius: BorderRadius.circular(6),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      hintStyle: const TextStyle(
        color: plannerMuted,
        fontSize: 13,
        fontWeight: FontWeight.w400,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: plannerBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: plannerBlue, width: 1.4),
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: plannerBorder),
      ),
    ),
  );
}
