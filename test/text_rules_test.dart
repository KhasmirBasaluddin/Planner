import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:planner/features/planner/widgets/planner_dialogs.dart';
import 'package:planner/shared/utils/text_rules.dart';

/// Emoji belong in chat and nowhere else.
///
/// The risk in a rule like this is not missing an emoji — it is rejecting a
/// real name. Most of these tests exist to pin down what stays allowed.
void main() {
  group('containsEmoji', () {
    test('catches a plain emoji', () {
      expect(containsEmoji('Ship it 🚀'), isTrue);
    });

    test('catches one built from a variation selector', () {
      // ❤️ is U+2764 followed by U+FE0F. Miss the selector and the stripped
      // text keeps a stray invisible character.
      expect(containsEmoji('❤️'), isTrue);
    });

    test('catches a family built with zero-width joiners', () {
      expect(containsEmoji('👨‍👩‍👧'), isTrue);
    });

    test('catches a flag built from regional indicators', () {
      expect(containsEmoji('🇵🇭'), isTrue);
    });

    test('catches a keycap', () {
      expect(containsEmoji('1️⃣'), isTrue);
    });

    test('catches dingbats used decoratively', () {
      expect(containsEmoji('Done ✅'), isTrue);
      expect(containsEmoji('★ Featured'), isTrue);
    });
  });

  // The important half. A name is not suspicious for being non-ASCII, and a
  // rule that rejected these would be worse than the problem it solves.
  group('containsEmoji leaves real text alone', () {
    test('plain ASCII', () {
      expect(containsEmoji('Juan Dela Cruz'), isFalse);
    });

    test('accents and umlauts', () {
      expect(containsEmoji('José Müller'), isFalse);
      expect(containsEmoji('Renée Ångström'), isFalse);
    });

    test('apostrophes and hyphens', () {
      expect(containsEmoji("O'Brien-Smith"), isFalse);
    });

    test('non-Latin scripts', () {
      expect(containsEmoji('李明'), isFalse);
      expect(containsEmoji('Мария'), isFalse);
      expect(containsEmoji('محمد'), isFalse);
      expect(containsEmoji('ソラ'), isFalse);
    });

    test('an email address', () {
      expect(containsEmoji('juan@vintazk.com'), isFalse);
    });

    test('a password of symbols', () {
      expect(containsEmoji(r'Tr0ub4dor&3!#$%'), isFalse);
    });
  });

  group('stripEmoji', () {
    test('keeps the name and drops the decoration', () {
      expect(stripEmoji('Juan 🚀 Dela Cruz'), 'Juan  Dela Cruz');
    });

    test('removes the invisible half of a sequence too', () {
      // Nothing renderable should survive, including U+FE0F on its own.
      expect(stripEmoji('❤️'), isEmpty);
      expect(stripEmoji('👨‍👩‍👧'), isEmpty);
    });

    test('leaves clean text untouched', () {
      const name = 'José Müller';
      expect(stripEmoji(name), name);
    });
  });

  group('validateNoEmoji', () {
    test('names the field in the message', () {
      expect(
        validateNoEmoji('Board 🎉', what: 'board name'),
        'Emoji are not allowed in a board name.',
      );
    });

    test('passes clean input', () {
      expect(validateNoEmoji('Q3 Roadmap', what: 'board name'), isNull);
    });

    test('passes null', () {
      expect(validateNoEmoji(null, what: 'name'), isNull);
    });
  });

  group('emojiFreeFormatter', () {
    TextEditingValue format(String text, {int? caret}) {
      final value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: caret ?? text.length),
      );
      return emojiFreeFormatter.formatEditUpdate(TextEditingValue.empty, value);
    }

    test('drops a pasted emoji', () {
      expect(format('Juan 🚀').text, 'Juan ');
    });

    test('leaves clean input exactly as typed', () {
      expect(format('José Müller').text, 'José Müller');
    });

    test('keeps the caret inside the shortened text', () {
      // A caret left past the end throws when the field rebuilds.
      final result = format('🚀🚀🚀');
      expect(
        result.selection.baseOffset,
        lessThanOrEqualTo(result.text.length),
      );
      expect(result.selection.baseOffset, greaterThanOrEqualTo(0));
    });
  });

  // A guard is only worth having if it is on every field. This walks the source
  // rather than trusting a checklist: a new TextField added without the
  // formatter is exactly the kind of gap that survives code review.
  group('coverage', () {
    final sources = <String>[
      'lib/features/auth/login_page.dart',
      'lib/features/planner/widgets/planner_dialogs.dart',
      'lib/features/planner/widgets/filter_panel.dart',
      'lib/features/workspace/members_dialog.dart',
      'lib/features/workspace/join_workspace_dialog.dart',
      'lib/features/planner/widgets/planner_sidebar.dart',
    ];

    test('every text input outside chat rejects emoji', () {
      final gaps = <String>[];

      for (final path in sources) {
        final src = File(path).readAsStringSync();
        for (final match in RegExp(r'Text(?:Form)?Field\(').allMatches(src)) {
          final end = (match.start + 1800).clamp(0, src.length);
          final chunk = src.substring(match.start, end);

          final guarded =
              chunk.contains('emojiFreeFormatter') ||
              chunk.contains('validateNoEmoji') ||
              chunk.contains('containsEmoji') ||
              chunk.contains('FilteringTextInputFormatter');

          // The chat composer is the deliberate exception: a message is
          // expression, and 👍 is the point of it.
          final isComposer = chunk.contains('commentMaxLength');

          if (!guarded && !isComposer) {
            final line = src.substring(0, match.start).split('\n').length;
            gaps.add('$path:$line');
          }
        }
      }

      expect(
        gaps,
        isEmpty,
        reason: 'unguarded text inputs: ${gaps.join(', ')}',
      );
    });

    test('the chat composer is exempt on purpose', () {
      // If this ever fails, someone stripped emoji from chat — which is the
      // one place they belong.
      final src = File(
        'lib/features/planner/widgets/planner_dialogs.dart',
      ).readAsStringSync();
      final composer = src.indexOf('maxLength: commentMaxLength');
      expect(composer, greaterThan(-1));

      final chunk = src.substring(
        composer,
        (composer + 900).clamp(0, src.length),
      );
      expect(chunk.contains('emojiFreeFormatter'), isFalse);
    });
  });

  // Length limits, checked against the SQL rather than against a comment.
  //
  // The client must never be looser than the database: if it were, a name the
  // field accepted would fail on insert with a raw constraint error instead of
  // the counter stopping it as it is typed.
  group('length limits stay inside the database constraints', () {
    late final String core = File(
      'supabase/migrations/0002_core.sql',
    ).readAsStringSync();

    int dbLimit(String constraint) {
      // Non-greedy across newlines: the constraint name and its `between`
      // clause are often on separate lines.
      final match = RegExp(
        RegExp.escape(constraint) + r'[\s\S]*?between 1 and (\d+)',
      ).firstMatch(core);
      expect(match, isNotNull, reason: 'no constraint named $constraint');
      return int.parse(match!.group(1)!);
    }

    test('workspace names', () {
      expect(
        NameLimits.workspace,
        lessThanOrEqualTo(dbLimit('workspaces_name_length')),
      );
    });

    test('board names', () {
      expect(
        NameLimits.board,
        lessThanOrEqualTo(dbLimit('boards_name_length')),
      );
    });

    test('group names', () {
      expect(
        NameLimits.group,
        lessThanOrEqualTo(dbLimit('task_groups_name_length')),
      );
    });

    test('task titles', () {
      expect(NameLimits.task, lessThanOrEqualTo(dbLimit('tasks_title_length')));
    });

    test('chat messages match the database exactly', () {
      // The one that is equal rather than stricter: 5000 characters is already
      // far past any real message, so there is nothing to gain by tightening.
      expect(commentMaxLength, dbLimit('task_comments_body_length'));
    });
  });
}
