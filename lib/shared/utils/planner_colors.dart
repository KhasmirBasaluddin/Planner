import 'package:flutter/material.dart';

import '../../models/planner_models.dart';

/// Design tokens.
///
/// The palette is built around a deep indigo brand and a warm neutral ramp:
/// greys carry a slight warmth (hue ~250, very low saturation) so large
/// surfaces read as paper rather than the cold blue-grey of default Material.
/// Accents are picked for distinguishability at small sizes — the status dots
/// and pills are often only a few pixels wide.

// --- Brand ---------------------------------------------------------------
const Color plannerBlue = Color(0xFF4C5BD4); // primary action
const Color plannerIndigo = Color(0xFF3B47AE); // pressed / deep
const Color plannerViolet = Color(0xFF7B5CF0); // secondary accent

// --- Status and accents --------------------------------------------------
const Color plannerGreen = Color(0xFF17A673);
const Color plannerYellow = Color(0xFFE8A33D);
const Color plannerRed = Color(0xFFE05260);
const Color plannerPurple = Color(0xFF7B5CF0);
const Color plannerTeal = Color(0xFF12A5A0);
const Color plannerOrange = Color(0xFFEE7A45);
const Color plannerMagenta = Color(0xFFC44FD1);
const Color plannerCyan = Color(0xFF3FA9E0);
const Color plannerBrown = Color(0xFF9A6B44);
const Color plannerSlate = Color(0xFF7C8398);

// --- Neutral ramp --------------------------------------------------------
const Color plannerInk = Color(0xFF1C1E2E); // headings
const Color plannerText = Color(0xFF474C61); // body
const Color plannerMuted = Color(0xFF767C93); // secondary
const Color plannerFaint = Color(0xFFA3A8BC); // placeholder
const Color plannerBorder = Color(0xFFE4E5EF); // hairlines
const Color plannerDivider = Color(0xFFEFF0F6);
const Color plannerSurface = Color(0xFFF7F7FB); // app background
const Color plannerCard = Color(0xFFFFFFFF);
const Color plannerHover = Color(0xFFF2F3F9);
const Color plannerSidebar = Color(0xFF191B2E);
const Color plannerSidebarHi = Color(0xFF24273F);

// --- Elevation -----------------------------------------------------------
/// Shadows are tinted with the ink color rather than pure black; neutral-black
/// shadows look muddy over a warm surface.
const List<BoxShadow> shadowSm = [
  BoxShadow(color: Color(0x0F1C1E2E), blurRadius: 3, offset: Offset(0, 1)),
];

const List<BoxShadow> shadowMd = [
  BoxShadow(color: Color(0x141C1E2E), blurRadius: 10, offset: Offset(0, 3)),
  BoxShadow(color: Color(0x0A1C1E2E), blurRadius: 2, offset: Offset(0, 1)),
];

const List<BoxShadow> shadowLg = [
  BoxShadow(color: Color(0x1F1C1E2E), blurRadius: 26, offset: Offset(0, 10)),
  BoxShadow(color: Color(0x0D1C1E2E), blurRadius: 4, offset: Offset(0, 2)),
];

// --- Shape ---------------------------------------------------------------
/// One radius scale, used everywhere. Mixed radii are the fastest way to make
/// an interface look assembled from parts.
const double radiusXs = 4;
const double radiusSm = 6;
const double radiusMd = 8;
const double radiusLg = 12;
const double radiusXl = 16;

/// Note paper tones — soft, low saturation, because a note is a large filled
/// surface with text on top.
const Color noteYellow = Color(0xFFFDF3C7);
const Color noteGreen = Color(0xFFD8F3E3);
const Color noteBlue = Color(0xFFDCE8FC);
const Color notePink = Color(0xFFFCE0E7);
const Color notePurple = Color(0xFFE9E1FD);
const Color noteOrange = Color(0xFFFDE6D2);
const Color noteTeal = Color(0xFFD3F0EE);
const Color noteGray = Color(0xFFECEDF4);

const List<Color> notePalette = [
  noteYellow,
  noteGreen,
  noteBlue,
  notePink,
  notePurple,
  noteOrange,
  noteTeal,
  noteGray,
];

/// Board and group accent choices.
const List<Color> accentPalette = [
  plannerBlue,
  plannerGreen,
  plannerYellow,
  plannerRed,
  plannerPurple,
  plannerTeal,
  plannerOrange,
  plannerMagenta,
  plannerCyan,
  plannerBrown,
];

/// A shade deeper than [base], for a note's header band.
Color noteHeaderColor(Color base) {
  final hsl = HSLColor.fromColor(base);
  return hsl
      .withSaturation((hsl.saturation * 1.12).clamp(0.0, 1.0))
      .withLightness((hsl.lightness - 0.07).clamp(0.0, 1.0))
      .toColor();
}

Color noteBorderColor(Color base) {
  final hsl = HSLColor.fromColor(base);
  return hsl.withLightness((hsl.lightness - 0.14).clamp(0.0, 1.0)).toColor();
}

/// Readable text over an arbitrary accent fill.
Color onAccent(Color background) {
  return background.computeLuminance() > 0.6 ? plannerInk : Colors.white;
}

/// A tinted background for a colored pill or chip.
Color tint(Color color, [double amount = 0.10]) {
  return color.withValues(alpha: amount);
}

/// The color a board gave this status, falling back to grey when a task has
/// none — which happens only if the label was deleted out from under it.
Color statusColor(StatusLabel? status) => status?.color ?? plannerSlate;

Color priorityColor(TaskPriority priority) {
  return switch (priority) {
    // Urgent has to out-shout High, so it takes red and High steps down to
    // orange, pushing Medium to yellow.
    TaskPriority.urgent => plannerRed,
    TaskPriority.high => plannerOrange,
    TaskPriority.medium => plannerYellow,
    TaskPriority.low => plannerSlate,
  };
}

/// Deterministic accent for a person, so the same teammate always gets the same
/// avatar color across the app.
Color avatarColor(String seed) {
  if (seed.isEmpty) {
    return plannerSlate;
  }
  var hash = 0;
  for (final unit in seed.codeUnits) {
    hash = (hash * 31 + unit) & 0x7FFFFFFF;
  }
  return accentPalette[hash % accentPalette.length];
}

/// The face to render emoji in.
///
/// Flutter does not pick an emoji font on its own: the default face is asked
/// first, has no glyph for a variation-selector sequence like ❤️ or a newer
/// codepoint like 🎉, and the result is tofu or a mismatched monochrome glyph.
/// Naming the platform emoji font explicitly is what makes them render.
const String emojiFontFamily = 'Segoe UI Emoji';

/// Tried in order when the primary face is missing — a Windows build may run
/// on a machine without it, and the same widgets build on other platforms.
const List<String> emojiFontFallback = <String>[
  'Segoe UI Emoji',
  'Apple Color Emoji',
  'Noto Color Emoji',
];
