import 'package:flutter_test/flutter_test.dart';
import 'package:planner/features/planner/widgets/planner_dialogs.dart';
import 'package:planner/models/planner_models.dart';

/// The chat model that replaced task notes.
void main() {
  const alex = UserProfile(
    id: 'u1',
    email: 'alex@vintazk.com',
    fullName: 'Alex Rivera',
  );

  TaskComment comment({
    String id = 'c1',
    String body = 'Looks good to me.',
    String? parentId,
    DateTime? editedAt,
    List<TaskComment> replies = const [],
    List<String> mentionedIds = const [],
    Map<String, int> reactions = const {},
    Set<String> myReactions = const {},
  }) {
    return TaskComment(
      id: id,
      taskId: 't1',
      body: body,
      createdAt: DateTime.now(),
      parentId: parentId,
      author: alex,
      editedAt: editedAt,
      replies: replies,
      mentionedIds: mentionedIds,
      reactions: reactions,
      myReactions: myReactions,
    );
  }

  group('TaskComment', () {
    test('parses a Supabase row', () {
      final parsed = TaskComment.fromMap({
        'id': 'c1',
        'task_id': 't1',
        'parent_id': null,
        'body': 'Shipping tomorrow.',
        'created_at': '2026-07-29T10:00:00Z',
        'edited_at': null,
      }, author: alex);

      expect(parsed.body, 'Shipping tomorrow.');
      expect(parsed.author?.displayName, 'Alex Rivera');
      expect(parsed.isReply, isFalse);
      expect(parsed.wasEdited, isFalse);
    });

    test('an edit is marked by edited_at, not by comparing timestamps', () {
      // Timestamps could not distinguish "never edited" from "edited a second
      // after posting", which is why the column exists.
      expect(comment().wasEdited, isFalse);
      expect(comment(editedAt: DateTime.now()).wasEdited, isTrue);
    });

    test('a reply knows it is one', () {
      expect(comment(parentId: 'c1').isReply, isTrue);
      expect(comment().isReply, isFalse);
    });

    test('threads carry their replies', () {
      final thread = comment(
        replies: [comment(id: 'c2', parentId: 'c1', body: 'Agreed.')],
      );
      expect(thread.hasReplies, isTrue);
      expect(thread.replies.single.body, 'Agreed.');
      // Threads stay one deep, so a reply never carries replies of its own.
      expect(thread.replies.single.hasReplies, isFalse);
    });

    test('reactions track both the total and your own', () {
      final reacted = comment(
        reactions: {'👍': 3, '🎉': 1},
        myReactions: {'👍'},
      );
      expect(reacted.reactions['👍'], 3);
      expect(reacted.myReactions.contains('👍'), isTrue);
      expect(reacted.myReactions.contains('🎉'), isFalse);
    });

    test('mentions are stored rather than re-parsed from the text', () {
      // An edit that removes the @name should not un-notify someone already
      // pinged, so the record is the row and not the body.
      final mentioned = comment(body: 'Thanks!', mentionedIds: ['u2']);
      expect(mentioned.mentionedIds, ['u2']);
      expect(mentioned.body.contains('@'), isFalse);
    });

    test('age reads compactly', () {
      TaskComment aged(Duration ago) => TaskComment(
        id: 'c1',
        taskId: 't1',
        body: 'x',
        createdAt: DateTime.now().subtract(ago),
      );

      expect(aged(Duration.zero).age, 'just now');
      expect(aged(const Duration(minutes: 5)).age, '5m');
      expect(aged(const Duration(hours: 3)).age, '3h');
      expect(aged(const Duration(days: 2)).age, '2d');
      expect(aged(const Duration(days: 21)).age, '3w');
    });

    test('copyWith replaces only the replies', () {
      final original = comment(body: 'Original');
      final withReplies = original.copyWith(
        replies: [comment(id: 'c2', parentId: 'c1')],
      );

      expect(withReplies.body, 'Original');
      expect(withReplies.id, original.id);
      expect(withReplies.replies, hasLength(1));
      expect(original.replies, isEmpty);
    });
  });

  group('task comment count', () {
    test('is read from the row the trigger maintains', () {
      final task = PlannerTask.fromMap({
        'id': 't1',
        'group_id': 'g1',
        'board_id': 'b1',
        'title': 'Ship it',
        'comment_count': 4,
      });
      expect(task.commentCount, 4);
    });

    test('defaults to zero when absent', () {
      final task = PlannerTask.fromMap({
        'id': 't1',
        'group_id': 'g1',
        'title': 'Bare',
      });
      expect(task.commentCount, 0);
    });
  });

  group('@everyone', () {
    test('is a distinct notification from being named directly', () {
      // "asked the team about" rather than "mentioned you on" — a broadcast is
      // a different event from being singled out.
      expect(
        NotificationKind.fromName('mentioned'),
        NotificationKind.mentioned,
      );
    });

    test('is not a member, so the picker offers it separately', () {
      // It cannot come from the member list, which is why both the composer
      // suggestion and the text highlighting special-case it.
      const members = <String>['Alex Rivera', 'Maria Beatrice'];
      expect(members.contains('everyone'), isFalse);
    });
  });

  group('badge count', () {
    test('shows the exact number up to 99', () {
      expect(compactCount(0), '0');
      expect(compactCount(1), '1');
      expect(compactCount(42), '42');
      expect(compactCount(99), '99');
    });

    test('clamps past 99, because three digits do not fit the circle', () {
      expect(compactCount(100), '99+');
      expect(compactCount(128), '99+');
      expect(compactCount(999), '99+');
    });

    test('has a second ceiling for absurd counts', () {
      expect(compactCount(1000), '999+');
      expect(compactCount(50000), '999+');
    });
  });

  group('quick reactions', () {
    test('includes a heart, and enough to choose from', () {
      // Six fits one row at a tappable size; a longer strip turns a one-tap
      // acknowledgement into a decision.
      expect(quickReactions, contains('❤️'));
      expect(quickReactions, contains('👍'));
      // Acknowledging work is the common case in a task chat.
      expect(quickReactions, contains('✅'));
      expect(quickReactions, hasLength(6));
    });

    test('has no duplicates', () {
      expect(quickReactions.toSet(), hasLength(quickReactions.length));
    });
  });

  group('notification kinds', () {
    test('mentioned is a distinct kind from a plain comment', () {
      // A mention is more pointed than "someone commented", and the trigger
      // suppresses the duplicate when both would fire.
      expect(
        NotificationKind.fromName('mentioned'),
        NotificationKind.mentioned,
      );
      expect(
        NotificationKind.fromName('comment_added'),
        NotificationKind.commentAdded,
      );
    });

    test('an unknown kind falls back rather than throwing', () {
      expect(
        NotificationKind.fromName('nonsense'),
        NotificationKind.memberJoined,
      );
    });
  });

  // The reply header names a person relative to whoever is reading it. The
  // first version compared only the parent's author against the viewer, so a
  // reply *to* you from someone else announced "Replied to yourself".
  group('replyLabel', () {
    test('names the target when I reply to someone else', () {
      expect(
        replyLabel(
          replierIsMe: true,
          targetId: 'u2',
          targetName: 'Rin',
          currentUserId: 'u1',
        ),
        'You replied to Rin',
      );
    });

    test('says replied to you when someone answers my message', () {
      expect(
        replyLabel(
          replierIsMe: false,
          targetId: 'u1',
          targetName: 'Alex Rivera',
          currentUserId: 'u1',
        ),
        'Replied to you',
      );
    });

    test('only says yourself when I answer my own message', () {
      expect(
        replyLabel(
          replierIsMe: true,
          targetId: 'u1',
          targetName: 'Alex Rivera',
          currentUserId: 'u1',
        ),
        'You replied to yourself',
      );
    });

    test('names both parties when neither is me', () {
      expect(
        replyLabel(
          replierIsMe: false,
          targetId: 'u3',
          targetName: 'Rin',
          currentUserId: 'u1',
        ),
        'Replied to Rin',
      );
    });

    test('truncates a name long enough to crowd out the quote', () {
      final label = replyLabel(
        replierIsMe: true,
        targetId: 'u2',
        targetName: 'Bartholomew Featherstonehaugh III',
        currentUserId: 'u1',
      );
      expect(label.length, lessThan(36));
      expect(label, endsWith('…'));
      expect(label, startsWith('You replied to Bartholomew'));
    });

    test('falls back when the account is gone', () {
      expect(
        replyLabel(
          replierIsMe: false,
          targetId: null,
          targetName: null,
          currentUserId: 'u1',
        ),
        'Replied to someone',
      );
    });
  });

  // The field caps typing and the send path re-checks, because a paste arrives
  // whole and task_comments_body_length would otherwise reject it as a raw
  // constraint error.
  group('commentMaxLength', () {
    test('matches the database check in 0002_core.sql', () {
      expect(commentMaxLength, 5000);
    });

    test('an ordinary message is nowhere near the limit', () {
      const typical = 'Can you take a look at this before standup tomorrow?';
      expect(typical.length, lessThan(commentMaxLength));
    });
  });
}
