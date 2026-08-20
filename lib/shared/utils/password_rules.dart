import 'package:flutter/material.dart';

import 'planner_colors.dart';

/// Password rules for new accounts, and for changing an existing one.
///
/// Length does more for real-world strength than character-class rules, so the
/// floor is 8 with a nudge toward longer, and the mix requirement is kept mild
/// rather than the usual "one of each of four types" — that pattern reliably
/// produces `Password1!` and nothing safer.
///
/// Shared rather than private to the login page: a password set from the
/// account dialog has to clear exactly the same bar as one set at signup,
/// and two copies of this would eventually disagree.
class PasswordCheck {
  const PasswordCheck({
    required this.hasLength,
    required this.hasLetter,
    required this.hasNumberOrSymbol,
    required this.isLong,
  });

  factory PasswordCheck.of(String value) {
    return PasswordCheck(
      hasLength: value.length >= 8,
      hasLetter: RegExp(r'[A-Za-z]').hasMatch(value),
      hasNumberOrSymbol: RegExp(r'[0-9\W_]').hasMatch(value),
      isLong: value.length >= 12,
    );
  }

  final bool hasLength;
  final bool hasLetter;
  final bool hasNumberOrSymbol;
  final bool isLong;

  bool get isValid => hasLength && hasLetter && hasNumberOrSymbol;

  /// 0–3, for the strength meter.
  int get score {
    if (!isValid) {
      return hasLength || hasLetter ? 1 : 0;
    }
    return isLong ? 3 : 2;
  }

  String get label => switch (score) {
    0 => 'Too short',
    1 => 'Weak',
    2 => 'Good',
    _ => 'Strong',
  };

  Color get color => switch (score) {
    0 || 1 => plannerRed,
    2 => plannerYellow,
    _ => plannerGreen,
  };
}
