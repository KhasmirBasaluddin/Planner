import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:planner/core/updates/release_notes.dart';

void main() {
  /// The version in pubspec.yaml, without the build number.
  String pubspecVersion() {
    final line = File('pubspec.yaml')
        .readAsLinesSync()
        .firstWhere((l) => l.startsWith('version:'));
    return line.split(':')[1].trim().split('+')[0];
  }

  group('release notes', () {
    test('the running version has notes written for it', () {
      // The whole feature is silent when these disagree — the dialog looks the
      // version up by string and finds nothing. Easy to forget when bumping
      // the version, and invisible until someone updates and sees no notes.
      final version = pubspecVersion();
      expect(
        notesFor(version),
        isNotNull,
        reason:
            'pubspec.yaml is $version but release_notes.dart has no entry for '
            'it. Add one, or the "What\'s new" dialog will never appear.',
      );
    });

    test('the newest entry is the one being shipped', () {
      expect(releaseHistory.first.version, pubspecVersion());
    });

    test('an unknown version has no notes rather than throwing', () {
      // An older build, or a release nobody wrote notes for. Either way the
      // dialog has to stay shut instead of failing at startup.
      expect(notesFor('0.0.1'), isNull);
      expect(notesFor(''), isNull);
    });

    test('every release has a headline and at least one note', () {
      for (final release in releaseHistory) {
        expect(
          release.headline.trim(),
          isNotEmpty,
          reason: '${release.version} has no headline',
        );
        expect(
          release.notes,
          isNotEmpty,
          reason: '${release.version} has no notes',
        );
      }
    });

    test('no version appears twice', () {
      final seen = <String>{};
      for (final release in releaseHistory) {
        expect(
          seen.add(release.version),
          isTrue,
          reason: '${release.version} is listed more than once',
        );
      }
    });

    test('every note says something', () {
      for (final release in releaseHistory) {
        for (final note in release.notes) {
          expect(note.title.trim(), isNotEmpty);
          expect(note.body.trim(), isNotEmpty);
        }
      }
    });

    test('notes are written for people, not as a commit log', () {
      // A cheap guard against pasting commit subjects in. If these words show
      // up, the note is describing the code rather than the change.
      const jargon = ['refactor', 'null check', 'RLS', 'migration 00'];
      for (final release in releaseHistory) {
        for (final note in release.notes) {
          final text = '${note.title} ${note.body}';
          for (final word in jargon) {
            expect(
              text.toLowerCase().contains(word.toLowerCase()),
              isFalse,
              reason: '"${note.title}" reads like a commit message ($word)',
            );
          }
        }
      }
    });
  });

  group('note kinds', () {
    test('carry the label the badge shows', () {
      expect(ReleaseNoteKind.added.label, 'New');
      expect(ReleaseNoteKind.improved.label, 'Improved');
      expect(ReleaseNoteKind.fixed.label, 'Fixed');
    });

    test('default to improved when unspecified', () {
      const note = ReleaseNote(title: 'A thing', body: 'It got better.');
      expect(note.kind, ReleaseNoteKind.improved);
    });
  });
}
