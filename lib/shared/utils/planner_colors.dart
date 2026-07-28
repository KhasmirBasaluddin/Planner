import 'package:flutter/material.dart';

import '../../models/planner_models.dart';

const Color plannerBlue = Color(0xFF0F6BFF);
const Color plannerGreen = Color(0xFF00A36C);
const Color plannerYellow = Color(0xFFFDAB3D);
const Color plannerRed = Color(0xFFE2445C);
const Color plannerPurple = Color(0xFF784BD1);
const Color plannerTeal = Color(0xFF0CA2A1);
const Color plannerOrange = Color(0xFFFB7D28);
const Color plannerMagenta = Color(0xFFCE4DFF);
const Color plannerCyan = Color(0xFF3DB5FF);
const Color plannerBrown = Color(0xFF8C5B32);
const Color plannerInk = Color(0xFF20233A);
const Color plannerText = Color(0xFF4B5168);
const Color plannerMuted = Color(0xFF6B7188);
const Color plannerBorder = Color(0xFFE1E4EE);
const Color plannerSurface = Color(0xFFF6F7FB);
const Color plannerSidebar = Color(0xFF181B34);

/// Sticky-note paper tones. These are deliberately softer than the accent
/// colors above: a note is a large filled surface with text on top, so it needs
/// low saturation to stay readable.
const Color noteYellow = Color(0xFFFFF3B0);
const Color noteGreen = Color(0xFFD4F5DD);
const Color noteBlue = Color(0xFFD6E9FF);
const Color notePink = Color(0xFFFFDCE5);
const Color notePurple = Color(0xFFE8DEFF);
const Color noteOrange = Color(0xFFFFE0C7);
const Color noteTeal = Color(0xFFCFF1EF);
const Color noteGray = Color(0xFFE9ECF3);

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

/// The header band of a note: the same hue, a shade deeper, so the card reads
/// as one object rather than two stacked rectangles.
Color noteHeaderColor(Color base) {
  final hsl = HSLColor.fromColor(base);
  return hsl
      .withSaturation((hsl.saturation * 1.08).clamp(0.0, 1.0))
      .withLightness((hsl.lightness - 0.08).clamp(0.0, 1.0))
      .toColor();
}

/// A border tone derived from the note color, for definition against the canvas.
Color noteBorderColor(Color base) {
  final hsl = HSLColor.fromColor(base);
  return hsl.withLightness((hsl.lightness - 0.16).clamp(0.0, 1.0)).toColor();
}

Color statusColor(TaskStatus status) {
  return switch (status) {
    TaskStatus.done => plannerGreen,
    TaskStatus.working => plannerYellow,
    TaskStatus.stuck => plannerRed,
    TaskStatus.notStarted => const Color(0xFF8C93A8),
  };
}

Color priorityColor(TaskPriority priority) {
  return switch (priority) {
    TaskPriority.high => plannerRed,
    TaskPriority.medium => plannerPurple,
    TaskPriority.low => plannerBlue,
  };
}
