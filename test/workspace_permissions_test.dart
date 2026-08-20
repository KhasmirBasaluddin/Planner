import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:planner/features/planner/widgets/planner_sidebar.dart';
import 'package:planner/models/planner_models.dart';

/// Who can do what to a workspace.
///
/// The database has always enforced this — `workspaces_update` and
/// `workspaces_delete` check the role — but the sidebar offered members the
/// controls anyway, so the failure only appeared when Save was pressed. These
/// tests assert the menu itself, per role, because "the analyzer is clean" says
/// nothing about which widgets a given role actually sees.
void main() {
  Workspace workspaceAs(WorkspaceRole role) {
    return Workspace(
      id: 'w1',
      name: 'My workspace',
      color: Colors.indigo,
      ownerId: role == WorkspaceRole.owner ? 'me' : 'someone-else',
      role: role,
      joinCode: 'PLNR-J53G',
    );
  }

  /// Renders the sidebar as [role] and opens the workspace menu.
  Future<void> openMenu(WidgetTester tester, WorkspaceRole role) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 280,
            height: 800,
            child: PlannerSidebar(
              workspaces: [workspaceAs(role)],
              selectedWorkspaceIndex: 0,
              boards: const [],
              selectedBoardIndex: 0,
              members: const [],
              loading: false,
              compact: false,
              onWorkspaceSelected: (_) {},
              onCreateWorkspace: () {},
              onJoinWorkspace: () {},
              onRenameWorkspace: () {},
              onManageMembers: () {},
              onOpenDeletedItems: () {},
              onLeaveWorkspace: () {},
              onDeleteWorkspace: () {},
              onSignOut: () {},
              onBoardSelected: (_) {},
              onCreateBoard: () {},
              onRenameBoard: (_) {},
              onDeleteBoard: (_) {},
              onPinBoard: (_) {},
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('My workspace'));
    await tester.pumpAndSettle();
  }

  group('workspace menu', () {
    testWidgets('an owner can manage and delete', (tester) async {
      await openMenu(tester, WorkspaceRole.owner);

      expect(find.text('Members & invites'), findsOneWidget);
      expect(find.text('Workspace settings'), findsOneWidget);
      expect(find.text('Delete workspace'), findsOneWidget);
      // The owner cannot walk away and leave nobody able to manage it.
      expect(find.text('Leave workspace'), findsNothing);
    });

    testWidgets('an admin can manage but not delete', (tester) async {
      await openMenu(tester, WorkspaceRole.admin);

      expect(find.text('Members & invites'), findsOneWidget);
      expect(find.text('Workspace settings'), findsOneWidget);
      expect(find.text('Delete workspace'), findsNothing);
      expect(find.text('Leave workspace'), findsOneWidget);
    });

    testWidgets('a member can only view people and leave', (tester) async {
      await openMenu(tester, WorkspaceRole.member);

      // Renaming and deleting are absent, not shown-and-refused.
      expect(find.text('Workspace settings'), findsNothing);
      expect(find.text('Delete workspace'), findsNothing);
      expect(find.text('Members & invites'), findsNothing);

      // Seeing who you work with is not a management action.
      expect(find.text('View members'), findsOneWidget);
      expect(find.text('Leave workspace'), findsOneWidget);
    });

    testWidgets('a viewer gets the same as a member', (tester) async {
      await openMenu(tester, WorkspaceRole.viewer);

      expect(find.text('Workspace settings'), findsNothing);
      expect(find.text('Delete workspace'), findsNothing);
      expect(find.text('View members'), findsOneWidget);
      expect(find.text('Leave workspace'), findsOneWidget);
    });

    // One test per role rather than a loop: reopening the menu in the same
    // pump leaves the previous one mounted, and every finder then matches
    // twice.
    for (final role in WorkspaceRole.values) {
      testWidgets('a ${role.name} can start or join a workspace of their own', (
        tester,
      ) async {
        await openMenu(tester, role);
        expect(find.text('New workspace'), findsOneWidget);
        expect(find.text('Join with a code'), findsOneWidget);
      });
    }
  });
}
