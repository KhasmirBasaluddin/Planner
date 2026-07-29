/// Where emoji and other pictographs are allowed, and where they are not.
///
/// Chat is the one place they belong: a message is expression, and 👍 is the
/// point of it. Everywhere else they are a problem rather than a feature —
/// names render as tofu in the PDF-less places we do not control (Outlook, the
/// installer, a Postgres error message), they defeat search and sorting, and a
/// display name of pure emoji is unaddressable in a mention.
///
/// The rule deliberately does not touch letters. Accents, non-Latin scripts,
/// and apostrophes are all ordinary parts of real names — "José", "Müller",
/// "O'Brien", "李" — and rejecting them to catch emoji would break the app for
/// people whose names are simply not ASCII.
library;

import 'package:flutter/services.dart';

/// Codepoint ranges that count as pictographic.
///
/// Listed as ranges rather than matched with a `\p{Emoji}` property because
/// Dart's RegExp has no Unicode property escapes. Each entry is inclusive.
const List<(int, int)> _pictographRanges = <(int, int)>[
  (0x1F000, 0x1FAFF), // emoji proper: faces, objects, symbols, flags
  (0x1F900, 0x1F9FF), // supplemental symbols and pictographs
  (0x2600, 0x27BF), // miscellaneous symbols and dingbats (☀ ✂ ➡)
  (0x2B00, 0x2BFF), // arrows and geometric shapes used as emoji (⬆ ⭐)
  (0x2190, 0x21FF), // arrows (←) — decorative in a name, never part of one
  (0xFE00, 0xFE0F), // variation selectors: the ️ that turns ❤ into ❤️
  (0x1F1E6, 0x1F1FF), // regional indicators, which pair into flags
  (0x200D, 0x200D), // zero-width joiner, which builds 👨‍👩‍👧 from parts
  (0x20E3, 0x20E3), // combining enclosing keycap, as in 1️⃣
];

/// True when [value] contains an emoji, pictograph, or emoji-joining character.
bool containsEmoji(String value) {
  for (final rune in value.runes) {
    for (final (start, end) in _pictographRanges) {
      if (rune >= start && rune <= end) {
        return true;
      }
    }
  }
  return false;
}

/// Strips everything [containsEmoji] would flag, for pasted input.
///
/// Typing an emoji is blocked at the field; pasting one arrives whole, and
/// silently dropping it beats rejecting the entire paste.
String stripEmoji(String value) {
  final kept = value.runes.where((rune) {
    for (final (start, end) in _pictographRanges) {
      if (rune >= start && rune <= end) {
        return false;
      }
    }
    return true;
  });
  return String.fromCharCodes(kept);
}

/// Drops emoji as they are typed or pasted, so the field never holds one.
///
/// Paired with [validateNoEmoji] rather than replacing it: the formatter keeps
/// the field clean, and the validator is what catches text that reached the
/// controller some other way and produces a message the user can read.
final TextInputFormatter emojiFreeFormatter = TextInputFormatter.withFunction((
  oldValue,
  newValue,
) {
  final cleaned = stripEmoji(newValue.text);
  if (cleaned == newValue.text) {
    return newValue;
  }
  // The caret has to move back by however much was removed, or it lands
  // past the end of the shortened string and the field throws.
  final removed = newValue.text.length - cleaned.length;
  final offset = (newValue.selection.baseOffset - removed).clamp(
    0,
    cleaned.length,
  );
  return TextEditingValue(
    text: cleaned,
    selection: TextSelection.collapsed(offset: offset),
  );
});

/// Returns an error message, or null when [value] is free of emoji.
///
/// [what] names the field, so the message reads as a sentence about the thing
/// the user was actually filling in.
String? validateNoEmoji(String? value, {required String what}) {
  if (value == null || !containsEmoji(value)) {
    return null;
  }
  return 'Emoji are not allowed in a $what.';
}
