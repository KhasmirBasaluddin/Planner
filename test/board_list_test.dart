import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:planner/features/planner/widgets/planner_sidebar.dart';
import 'package:planner/models/planner_models.dart';

/// Board search and pinning in the sidebar.
///
/// The subtle part is that selection is by index into the *unfiltered* list.
/// Filtering or reordering the display must not change which board a tap
/// selects, so these tests assert the index that comes back, not just what is
/// on screen.
void main() {
  Board board(String name, {bool pinned = false}) {
    return Board(
      id: name.toLowerCase().replaceAll(' ', '-'),
      name: name,
      color: Colors.indigo,
      pinned: pinned,
      groups: const [],
    );
  }

  int? tappedIndex;
  Board? pinnedBoard;

  Future<void> pumpSidebar(WidgetTester tester, List<Board> boards) async {
    tappedIndex = null;
    pinnedBoard = null;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 280,
            height: 900,
            child: PlannerSidebar(
              workspaces: [
                Workspace(
                  id: 'w1',
                  name: 'My workspace',
                  color: Colors.indigo,
                  ownerId: 'me',
                  role: WorkspaceRole.owner,
                ),
              ],
              selectedWorkspaceIndex: 0,
              boards: boards,
              selectedBoardIndex: 0,
              members: const [],
              loading: false,
              compact: false,
              onWorkspaceSelected: (_) {},
              onCreateWorkspace: () {},
              onJoinWorkspace: () {},
              onRenameWorkspace: () {},
              onManageMembers: () {},
              onLeaveWorkspace: () {},
              onDeleteWorkspace: () {},
              onSignOut: () {},
              onBoardSelected: (index) => tappedIndex = index,
              onCreateBoard: () {},
              onRenameBoard: (_) {},
              onDeleteBoard: (_) {},
              onPinBoard: (board) => pinnedBoard = board,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  List<Board> sixBoards() => [
    board('Website Redesign'),
    board('Q1 Marketing'),
    board('Hiring'),
    board('Infrastructure'),
    board('Customer Research'),
    board('Website Copy'),
  ];

  group('board search', () {
    testWidgets('is hidden when there is nothing to choose between', (
      tester,
    ) async {
      await pumpSidebar(tester, [board('Only one')]);
      expect(find.text('Search boards'), findsNothing);
    });

    testWidgets('appears as soon as there are two boards', (tester) async {
      // Deliberately the smallest list that needs it. Hiding the box until
      // some larger threshold made it look absent rather than unnecessary.
      await pumpSidebar(tester, [board('Alpha'), board('Beta')]);
      expect(find.text('Search boards'), findsOneWidget);
    });

    testWidgets('keeps its text legible while hovered', (tester) async {
      await pumpSidebar(tester, sixBoards());
      await tester.enterText(find.byType(TextField), 'My');
      await tester.pumpAndSettle();

      // The rail is dark and the text white, so any pale hover or focus
      // overlay on the field swallows what has been typed.
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.decoration?.hoverColor, Colors.transparent);
      expect(field.decoration?.focusColor, Colors.transparent);
      expect(field.style?.color, Colors.white);
    });

    testWidgets('filters by name, case-insensitively', (tester) async {
      await pumpSidebar(tester, sixBoards());

      await tester.enterText(find.byType(TextField), 'website');
      await tester.pumpAndSettle();

      expect(find.text('Website Redesign'), findsOneWidget);
      expect(find.text('Website Copy'), findsOneWidget);
      expect(find.text('Hiring'), findsNothing);
    });

    testWidgets('selecting a filtered board reports its real index', (
      tester,
    ) async {
      await pumpSidebar(tester, sixBoards());

      await tester.enterText(find.byType(TextField), 'research');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Customer Research'));

      // Fifth in the full list, first in the filtered one. Selection is by
      // position in the full list, so this must be 4 and not 0.
      expect(tappedIndex, 4);
    });

    testWidgets('says so when nothing matches', (tester) async {
      await pumpSidebar(tester, sixBoards());

      await tester.enterText(find.byType(TextField), 'zzzz');
      await tester.pumpAndSettle();

      expect(find.text('No boards match'), findsOneWidget);
      // Distinct from having no boards at all, which offers a Create button.
      expect(find.text('No boards yet'), findsNothing);
    });

    testWidgets('the empty state is horizontally centred', (tester) async {
      await pumpSidebar(tester, sixBoards());

      await tester.enterText(find.byType(TextField), 'zzzz');
      await tester.pumpAndSettle();

      // The icon and the text should share a centre line, and it should be the
      // rail's. Left-aligned children read as a layout bug, not an empty state.
      final railCentre = tester.getCenter(find.byType(PlannerSidebar)).dx;
      final iconCentre = tester
          .getCenter(find.byIcon(Icons.search_off_rounded))
          .dx;
      final textCentre = tester.getCenter(find.text('No boards match')).dx;

      expect((iconCentre - railCentre).abs(), lessThan(1));
      expect((textCentre - railCentre).abs(), lessThan(1));
    });
  });

  group('board pinning', () {
    testWidgets('a pinned board sorts above the rest', (tester) async {
      await pumpSidebar(tester, [
        board('Alpha'),
        board('Beta'),
        board('Gamma', pinned: true),
      ]);

      final gamma = tester.getTopLeft(find.text('Gamma')).dy;
      final alpha = tester.getTopLeft(find.text('Alpha')).dy;
      expect(gamma, lessThan(alpha));
    });

    testWidgets('pinning still selects the right board afterwards', (
      tester,
    ) async {
      await pumpSidebar(tester, [
        board('Alpha'),
        board('Beta'),
        board('Gamma', pinned: true),
      ]);

      // Gamma is drawn first but is index 2 in the underlying list.
      await tester.tap(find.text('Gamma'));
      expect(tappedIndex, 2);
    });

    /// Opens the row menu for the board at [rowIndex].
    ///
    /// The menu is always in the tree but sits behind
    /// `IgnorePointer(ignoring: !hovered)`, so a bare tap is swallowed. The
    /// pointer has to actually enter the row first, as it would in the app.
    Future<void> openRowMenu(WidgetTester tester, {int rowIndex = 0}) async {
      final pointer = TestPointer(1, PointerDeviceKind.mouse);
      final trigger = find.byIcon(Icons.more_horiz_rounded).at(rowIndex);
      await tester.sendEventToBinding(
        pointer.hover(tester.getCenter(trigger)),
      );
      await tester.pumpAndSettle();

      await tester.tap(trigger);
      await tester.pumpAndSettle();
    }

    testWidgets('the row menu offers Pin, and reports which board', (
      tester,
    ) async {
      await pumpSidebar(tester, [board('Alpha'), board('Beta')]);
      await openRowMenu(tester);

      expect(find.text('Pin to top'), findsOneWidget);
      await tester.tap(find.text('Pin to top'));
      await tester.pumpAndSettle();

      expect(pinnedBoard?.name, 'Alpha');
    });

    testWidgets('an already-pinned board offers Unpin instead', (tester) async {
      await pumpSidebar(tester, [board('Alpha', pinned: true)]);
      await openRowMenu(tester);

      expect(find.text('Unpin board'), findsOneWidget);
      expect(find.text('Pin to top'), findsNothing);
    });

    testWidgets('equally-pinned boards keep the order they arrived in', (
      tester,
    ) async {
      await pumpSidebar(tester, [
        board('Alpha'),
        board('Beta'),
        board('Gamma'),
      ]);

      final alpha = tester.getTopLeft(find.text('Alpha')).dy;
      final beta = tester.getTopLeft(find.text('Beta')).dy;
      final gamma = tester.getTopLeft(find.text('Gamma')).dy;
      expect(alpha, lessThan(beta));
      expect(beta, lessThan(gamma));
    });
  });

  group('progress agrees with status', () {
    const done = StatusLabel(
      id: 's-done',
      name: 'Done',
      color: Colors.green,
      position: 3,
      isDone: true,
    );
    const notStarted = StatusLabel(
      id: 's-new',
      name: 'Not started',
      color: Colors.grey,
      position: 0,
      isDefault: true,
    );
    const working = StatusLabel(
      id: 's-working',
      name: 'Working on it',
      color: Colors.orange,
      position: 1,
    );

    test('a done status fills the bar', () {
      expect(progressForStatus(done, 0), 1);
      expect(progressForStatus(done, 0.4), 1);
    });

    test('a not-started status empties it', () {
      expect(progressForStatus(notStarted, 1), 0);
      expect(progressForStatus(notStarted, 0.4), 0);
    });

    test('moving off 100% to an in-between status does not stay at 100%', () {
      // The reported bug: a full bar labelled "Working on it".
      expect(progressForStatus(working, 1), lessThan(1));
      expect(progressForStatus(working, 1), greaterThan(0));
    });

    test('moving off 0% to an in-between status does not stay at 0%', () {
      expect(progressForStatus(working, 0), greaterThan(0));
    });

    test('mid-progress is left alone', () {
      // Nothing about "Working on it" says how far along the work is, so a
      // real measurement is not overwritten with a guess.
      expect(progressForStatus(working, 0.4), 0.4);
      expect(progressForStatus(working, 0.9), 0.9);
    });
  });

  group('stale tracking', () {
    test('progress_at is read separately from the row', () {
      // Not updated_at: renaming a task or changing its due date resets that,
      // so a genuinely stalled task would look busy to the sweep.
      final task = PlannerTask.fromMap({
        'id': 't1',
        'group_id': 'g1',
        'board_id': 'b1',
        'title': 'Ship it',
        'progress': 0.4,
        'progress_at': '2026-07-26T10:00:00Z',
      });
      expect(task.progressAt, DateTime.utc(2026, 7, 26, 10));
      expect(task.progress, 0.4);
    });

    test('is null when the row does not carry it', () {
      final task = PlannerTask.fromMap({
        'id': 't1',
        'group_id': 'g1',
        'title': 'Bare',
      });
      expect(task.progressAt, isNull);
    });
  });

  group('priority', () {
    test('has four levels, led by Urgent', () {
      expect(TaskPriority.values, hasLength(4));
      expect(TaskPriority.values.first, TaskPriority.urgent);
      expect(TaskPriority.urgent.label, 'Urgent');
    });

    test('parses the wire value, falling back rather than throwing', () {
      expect(TaskPriority.fromName('urgent'), TaskPriority.urgent);
      expect(TaskPriority.fromName('nonsense'), TaskPriority.medium);
    });
  });
}
