/// What changed in each release, for the "What's new" dialog.
///
/// Kept in the app rather than fetched from the GitHub release body. Three
/// reasons: it shows on first launch after an update, which is exactly when a
/// network call is least welcome; the wording can be written for the people
/// who use Planner rather than for a changelog; and a portable ZIP that never
/// talks to GitHub still explains itself.
///
/// Add a new entry at the top when releasing. The version must match
/// `pubspec.yaml` — the dialog looks the running version up by that string,
/// and an entry that does not match simply never appears.
library;

/// One line in the notes, grouped so a release reads as a short list rather
/// than a wall of text.
class ReleaseNote {
  const ReleaseNote({
    required this.title,
    required this.body,
    this.kind = ReleaseNoteKind.improved,
  });

  final String title;
  final String body;
  final ReleaseNoteKind kind;
}

/// What sort of change this is. Purely for the label and colour — people scan
/// for "what's new" and "what got fixed" differently.
enum ReleaseNoteKind {
  added('New'),
  improved('Improved'),
  fixed('Fixed');

  const ReleaseNoteKind(this.label);

  final String label;
}

/// One release.
class ReleaseNotes {
  const ReleaseNotes({
    required this.version,
    required this.headline,
    required this.notes,
  });

  /// Must match `pubspec.yaml`'s version, without the build number.
  final String version;

  /// One sentence summing the release up, above the list.
  final String headline;

  final List<ReleaseNote> notes;
}

/// Newest first.
const List<ReleaseNotes> releaseHistory = [
  ReleaseNotes(
    version: '1.0.2',
    headline:
        'Work notes with attachments, a proper account panel, and the board '
        'now keeps itself up to date on its own.',
    notes: [
      ReleaseNote(
        kind: ReleaseNoteKind.added,
        title: 'Work notes, with photos and files',
        body:
            'Every task now has a work log beside its chat. Record what you '
            'actually did and attach photos or files as proof. Marking a task '
            'done asks for a note, and sending it back records why — so the '
            'whole back-and-forth stays readable afterwards instead of being '
            'buried in the conversation.',
      ),
      ReleaseNote(
        kind: ReleaseNoteKind.added,
        title: 'Reviewing finished work',
        body:
            'Admins and owners can send finished work back to any unfinished '
            'status, with a reason, and optionally hand it to someone else. '
            'The person who submitted it can fix it and submit again. Every '
            'round is kept.',
      ),
      ReleaseNote(
        kind: ReleaseNoteKind.added,
        title: 'See who marked a task done',
        body:
            'A task can have several people on it, so the avatars tell you who '
            'is responsible — not who finished it. That now shows on the '
            'status itself in the table, the board and the calendar.',
      ),
      ReleaseNote(
        kind: ReleaseNoteKind.added,
        title: 'Your account',
        body:
            'Change your display name and password from the menu under your '
            'avatar. Your name can be changed once every 7 days, since it is '
            'how teammates recognise you everywhere.',
      ),
      ReleaseNote(
        kind: ReleaseNoteKind.added,
        title: 'Deleted items',
        body:
            'Anything you delete is kept for 30 days and can be put back from '
            'the workspace menu. Only admins and owners can remove something '
            'for good.',
      ),
      ReleaseNote(
        kind: ReleaseNoteKind.added,
        title: 'Notification history',
        body:
            'The bell now has a "See all" view with filters for unread, '
            'mentions and task activity, so nothing is lost off the bottom of '
            'the panel.',
      ),
      ReleaseNote(
        kind: ReleaseNoteKind.fixed,
        title: 'Invitations arrive without restarting',
        body:
            'An invitation sent while your app was open — or asleep — '
            'sometimes never appeared until you closed and reopened Planner. '
            'The app now notices when it has been disconnected and catches up '
            'by itself. There is also a refresh button in the top bar if you '
            'ever want to force it.',
      ),
      ReleaseNote(
        kind: ReleaseNoteKind.fixed,
        title: 'Chat no longer scrolls under your mouse',
        body:
            'Moving the pointer across a conversation used to scroll it. It '
            'stays put now.',
      ),
      ReleaseNote(
        kind: ReleaseNoteKind.fixed,
        title: 'Several links pasted together',
        body:
            'Links pasted back to back with no space between them were treated '
            'as one enormous link, and the "open this link?" box grew past the '
            'bottom of the screen. They are separate links again.',
      ),
      ReleaseNote(
        kind: ReleaseNoteKind.fixed,
        title: 'Joining with a code clears the invitation',
        body:
            'Someone invited by email who joined with the workspace code '
            'instead stayed listed under "Pending invitations" forever, even '
            'though they were already a member.',
      ),
    ],
  ),
];

/// The notes for [version], or null when there are none — an older build, or
/// a release nobody wrote notes for. Either way the dialog stays shut.
ReleaseNotes? notesFor(String version) {
  for (final release in releaseHistory) {
    if (release.version == version) {
      return release;
    }
  }
  return null;
}
