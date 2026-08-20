import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/updates/release_notes.dart';
import '../utils/planner_colors.dart';

/// The version whose notes have already been shown.
///
/// A string rather than a bool: the question is not "has this ever been
/// shown" but "has it been shown for *this* version", and every future
/// release has to be able to ask it again.
const String _seenVersionKey = 'whats_new_seen_version';

/// Shows what changed, once, after the app updates.
///
/// Deliberately silent for a first install. Someone opening Planner for the
/// first time has no idea what the previous version did, so a list of changes
/// is noise at exactly the moment they are trying to get their bearings — the
/// version is recorded and the dialog waits for the next update.
///
/// Returns true when the dialog was shown.
Future<bool> showWhatsNewIfUpdated(BuildContext context) async {
  final version = (await PackageInfo.fromPlatform()).version;
  final prefs = await SharedPreferences.getInstance();
  final seen = prefs.getString(_seenVersionKey);

  if (seen == version) {
    return false;
  }

  // Record it either way, so a release with no notes written for it still
  // counts as seen and does not queue itself up behind the next one.
  await prefs.setString(_seenVersionKey, version);

  // First run: nothing to compare against.
  if (seen == null) {
    return false;
  }

  final notes = notesFor(version);
  if (notes == null || !context.mounted) {
    return false;
  }

  await showDialog<void>(
    context: context,
    builder: (context) => _WhatsNewDialog(notes: notes),
  );
  return true;
}

/// Opens the notes on demand, ignoring whether they have been seen. For a
/// "What's new" entry in a menu, and for testing the dialog itself.
Future<void> showReleaseNotes(BuildContext context, ReleaseNotes notes) {
  return showDialog<void>(
    context: context,
    builder: (context) => _WhatsNewDialog(notes: notes),
  );
}

class _WhatsNewDialog extends StatelessWidget {
  const _WhatsNewDialog({required this.notes});

  final ReleaseNotes notes;

  @override
  Widget build(BuildContext context) {
    final viewport = MediaQuery.sizeOf(context);

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      backgroundColor: plannerCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusLg),
      ),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 520,
          maxHeight: viewport.height - 80,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(version: notes.version, headline: notes.headline),
            Flexible(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(22, 18, 22, 20),
                itemCount: notes.notes.length,
                separatorBuilder: (_, _) => const SizedBox(height: 16),
                itemBuilder: (context, index) => _Note(note: notes.notes[index]),
              ),
            ),
            const Divider(height: 1, color: plannerBorder),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Get started'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.version, required this.headline});

  final String version;
  final String headline;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 22, 18, 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [tint(plannerBlue, 0.14), tint(plannerViolet, 0.09)],
        ),
        border: const Border(bottom: BorderSide(color: plannerBorder)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 9,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: plannerBlue,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'Version $version',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const Spacer(),
              IconButton(
                tooltip: 'Close',
                icon: const Icon(
                  Icons.close_rounded,
                  size: 19,
                  color: plannerMuted,
                ),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            "What's new in Planner",
            style: TextStyle(
              color: plannerInk,
              fontSize: 19,
              fontWeight: FontWeight.w700,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            headline,
            style: const TextStyle(
              color: plannerText,
              fontSize: 12.5,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.note});

  final ReleaseNote note;

  Color get _tone => switch (note.kind) {
    ReleaseNoteKind.added => plannerGreen,
    ReleaseNoteKind.improved => plannerBlue,
    ReleaseNoteKind.fixed => plannerOrange,
  };

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 1),
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: tint(_tone, 0.12),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                note.kind.label,
                style: TextStyle(
                  color: _tone,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                ),
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                note.title,
                style: const TextStyle(
                  color: plannerInk,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  height: 1.3,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 5),
        Padding(
          // Indented past the badge so the body lines up under the title.
          padding: const EdgeInsets.only(left: 47),
          child: Text(
            note.body,
            style: const TextStyle(
              color: plannerMuted,
              fontSize: 12.5,
              height: 1.5,
            ),
          ),
        ),
      ],
    );
  }
}
