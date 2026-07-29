import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:planner/features/planner/widgets/app_navbar.dart';
import 'package:planner/models/planner_models.dart';

/// Opening the notification panel used to throw at layout time:
/// `MenuAnchor` wraps its children in `IntrinsicWidth`, which asks every
/// descendant for its intrinsic width, and the scrolling feed inside cannot
/// answer that. The analyzer cannot see it — only a real layout pass can — so
/// these tests open the panel for each shape it can take.
void main() {
  AppNotification notification({
    required String id,
    NotificationKind kind = NotificationKind.taskAssigned,
    bool read = false,
    Duration age = Duration.zero,
    String? inviteId,
  }) {
    return AppNotification(
      id: id,
      kind: kind,
      title: 'Something happened on "Ship the thing"',
      body: 'With a second line of detail.',
      inviteId: inviteId,
      readAt: read ? DateTime.now() : null,
      createdAt: DateTime.now().subtract(age),
    );
  }

  PendingInvite invite({
    String id = 'i1',
    UserProfile? invitedBy,
    int memberCount = 0,
    WorkspaceRole role = WorkspaceRole.member,
  }) {
    return PendingInvite(
      id: id,
      workspaceId: 'w1',
      workspaceName: 'Vintazk Business',
      workspaceColor: Colors.indigo,
      role: role,
      createdAt: DateTime.now(),
      invitedBy: invitedBy,
      memberCount: memberCount,
    );
  }

  const maria = UserProfile(
    id: 'u9',
    email: 'maria@vintazk.com',
    fullName: 'Maria Beatrice',
  );

  Future<void> openPanel(
    WidgetTester tester, {
    List<PendingInvite> invites = const [],
    List<AppNotification> notifications = const [],
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppNavbar(
            fullName: 'Test User',
            email: 'test@vintazk.com',
            invites: invites,
            notifications: notifications,
            onAcceptInvite: (_) {},
            onDeclineInvite: (_) {},
            onOpenNotification: (_) {},
            onMarkAllRead: () {},
          ),
        ),
      ),
    );

    await tester.tap(find.byType(InkWell).first);
    await tester.pumpAndSettle();
  }

  group('notification panel opens without a layout error', () {
    testWidgets('when empty', (tester) async {
      await openPanel(tester);
      expect(find.text('You are all caught up'), findsOneWidget);
    });

    testWidgets('with an invitation only', (tester) async {
      await openPanel(tester, invites: [invite()]);
      expect(find.text('Vintazk Business'), findsOneWidget);
      // The buttons are the whole point of an invitation.
      expect(find.text('Accept'), findsOneWidget);
      expect(find.text('Decline'), findsOneWidget);
    });

    testWidgets('with a feed only', (tester) async {
      await openPanel(
        tester,
        notifications: [notification(id: 'n1'), notification(id: 'n2')],
      );
      expect(find.text('TODAY'), findsOneWidget);
    });

    testWidgets('with both, and across every time bucket', (tester) async {
      await openPanel(
        tester,
        invites: [invite()],
        notifications: [
          notification(id: 'n1'),
          notification(id: 'n2', age: const Duration(days: 1)),
          notification(id: 'n3', age: const Duration(days: 3)),
          notification(id: 'n4', age: const Duration(days: 10)),
          notification(id: 'n5', age: const Duration(days: 90)),
        ],
      );

      for (final heading in ['TODAY', 'YESTERDAY', 'THIS WEEK', 'THIS MONTH',
        'EARLIER']) {
        expect(find.text(heading), findsOneWidget, reason: heading);
      }
    });

    testWidgets('with enough entries to scroll', (tester) async {
      await openPanel(
        tester,
        notifications: [
          for (var i = 0; i < 40; i++) notification(id: 'n$i'),
        ],
      );
      // SingleChildScrollView rather than ListView: MenuAnchor measures its
      // children's intrinsic width, which a lazy viewport refuses to report.
      expect(find.byType(SingleChildScrollView), findsWidgets);
    });
  });

  group('panel contents', () {
    testWidgets('a pending invitation is not also shown in the feed', (
      tester,
    ) async {
      await openPanel(
        tester,
        invites: [invite(id: 'i1')],
        notifications: [
          notification(
            id: 'n1',
            kind: NotificationKind.workspaceInvite,
            inviteId: 'i1',
          ),
        ],
      );

      // The card is present, and the announcement it duplicates is not — so
      // there is no time heading left for the feed.
      expect(find.text('Vintazk Business'), findsOneWidget);
      expect(find.text('TODAY'), findsNothing);
    });

    testWidgets('an answered invitation keeps its feed entry', (tester) async {
      await openPanel(
        tester,
        notifications: [
          notification(
            id: 'n1',
            kind: NotificationKind.workspaceInvite,
            inviteId: 'i1',
          ),
        ],
      );
      expect(find.text('TODAY'), findsOneWidget);
    });

    testWidgets('an invitation names who sent it and how big the team is', (
      tester,
    ) async {
      await openPanel(
        tester,
        invites: [invite(invitedBy: maria, memberCount: 4)],
      );

      expect(find.text('Maria Beatrice invited you'), findsOneWidget);
      expect(find.text('Vintazk Business'), findsOneWidget);
      expect(find.textContaining('4 members'), findsOneWidget);
      // The role is spelled out, not just named.
      expect(
        find.textContaining('Can create and edit boards', findRichText: true),
        findsOneWidget,
      );
    });

    testWidgets('falls back when the inviter account is gone', (tester) async {
      await openPanel(tester, invites: [invite(memberCount: 1)]);

      expect(find.text('You have been invited'), findsOneWidget);
      expect(find.textContaining('1 member'), findsOneWidget);
    });

    testWidgets('a viewer invitation says it is read-only', (tester) async {
      await openPanel(
        tester,
        invites: [invite(invitedBy: maria, role: WorkspaceRole.viewer)],
      );
      expect(
        find.textContaining('Read-only', findRichText: true),
        findsOneWidget,
      );
    });

    testWidgets('an invitation renders even without its workspace name', (
      tester,
    ) async {
      // RLS hid the workspace from the invited person, so the embedded
      // `workspaces(...)` came back null and the repository dropped the
      // invitation entirely — the bell stayed empty while the row sat pending,
      // which looked like invitations silently expiring. The policy now lets an
      // invited person read the name, and the repository falls back rather than
      // discarding, so a nameless invitation is still answerable.
      await openPanel(
        tester,
        invites: [
          PendingInvite(
            id: 'i1',
            workspaceId: 'w1',
            workspaceName: 'a workspace',
            workspaceColor: Colors.indigo,
            role: WorkspaceRole.member,
            createdAt: DateTime.now(),
          ),
        ],
      );

      expect(find.text('Accept'), findsOneWidget);
      expect(find.text('Decline'), findsOneWidget);
    });

    testWidgets('unread count and mark-all appear only when unread', (
      tester,
    ) async {
      await openPanel(
        tester,
        notifications: [notification(id: 'n1'), notification(id: 'n2')],
      );
      expect(find.text('2 new'), findsOneWidget);
      expect(find.text('Mark all read'), findsOneWidget);
    });

    testWidgets('no unread badge when everything is read', (tester) async {
      await openPanel(
        tester,
        notifications: [notification(id: 'n1', read: true)],
      );
      expect(find.text('Mark all read'), findsNothing);
    });
  });
}
