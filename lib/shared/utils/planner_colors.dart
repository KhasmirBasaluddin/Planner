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
