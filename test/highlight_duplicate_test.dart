import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:planner/features/planner/widgets/board_calendar.dart';
import 'package:planner/features/planner/widgets/board_kanban.dart';
import 'package:planner/features/planner/widgets/board_table.dart';
import 'package:planner/models/planner_models.dart';

/// Revealing a task must never crash, however many places it appears.
///
/// The reveal originally marked the target row with a GlobalKey so the page
/// could scroll to it. A GlobalKey may only be attached to one widget at a
/// time, and the same task legitimately renders more than once — grouped by
/// assignee it appears under every assignee it belongs to, and mid-transition
/// between views the outgoing view is still mounted. Both raised "Duplicate
/// GlobalKey detected in widget tree" and took the whole app down to a red
/// screen. Each view now scrolls itself, with no key involved.
void main() {
  const statuses = [
    StatusLabel(
      id: 's-working',
      name: 'Working on it',
      color: Colors.orange,
      position: 1,
    ),
  ];

  final members = [
    for (final id in ['u1', 'u2'])
      WorkspaceMember(
        profile: UserProfile(
          id: id,
          email: '$id@vintazk.com',
          fullName: 'Member $id',
        ),
        role: WorkspaceRole.member,
      ),
  ];

  // One task, assigned to two people — the shape "group by assignee" turns
  // into the same task inside two groups.
  final shared = PlannerTask(
    id: 'shared',
    groupId: 'g1',
    boardId: 'b1',
    title: 'Shared task',
    statusId: 's-working',
    priority: TaskPriority.urgent,
    progress: 0.5,
    position: 0,
    assigneeIds: const ['u1', 'u2'],
    dueDate: DateTime.now(),
  );

  /// The same task placed in two groups, as _regroup does for assignees.
  List<TaskGroup> duplicatedAcrossGroups() => [
    for (final id in ['u1', 'u2'])
      TaskGroup(
        id: 'group:$id',
        boardId: 'b1',
        name: 'Member $id',
        color: Colors.blue,
        tasks: [shared],
      ),
  ];

  Future<void> pump(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
    await tester.pumpAndSettle();
  }

  testWidgets('the table survives one task appearing in two groups', (
    tester,
  ) async {
    await pump(
      tester,
      BoardTable(
        groups: duplicatedAcrossGroups(),
        members: members,
        statuses: statuses,
        collapsedGroupIds: const {},
        highlightedTaskId: shared.id,
        onToggleGroup: (_) {},
        onRenameGroup: (_) {},
        onDeleteGroup: (_) {},
        onEditTask: (_) {},
        onDeleteTask: (_) {},
        onStatusChanged: (_, _) async {},
        onProgressChanged: (_, _) async {},
        onOpenChat: (_) {},
      ),
    );
    expect(tester.takeException(), isNull);
    // Rendered in both groups, not silently dropped from one.
    expect(find.text('Shared task'), findsNWidgets(2));
  });

  testWidgets('the kanban survives one task appearing in two groups', (
    tester,
  ) async {
    await pump(
      tester,
      BoardKanban(
        groups: duplicatedAcrossGroups(),
        members: members,
        statuses: statuses,
        highlightedTaskId: shared.id,
        onEditTask: (_) {},
        onDeleteTask: (_) {},
        onStatusChanged: (_, _) async {},
        onProgressChanged: (_, _) async {},
        onOpenChat: (_) {},
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('the calendar survives one task appearing in two groups', (
    tester,
  ) async {
    await pump(
      tester,
      BoardCalendar(
        groups: duplicatedAcrossGroups(),
        members: members,
        statuses: statuses,
        highlightedTaskId: shared.id,
        onEditTask: (_) {},
        onDeleteTask: (_) {},
        onStatusChanged: (_, _) async {},
        onProgressChanged: (_, _) async {},
        onOpenChat: (_) {},
      ),
    );
    expect(tester.takeException(), isNull);
  });

  // Two views mounted at once is what AnimatedSwitcher does during a mode
  // change, and it was the other way the duplicate key was hit.
  testWidgets('two views can hold the same highlighted task at once', (
    tester,
  ) async {
    final groups = [
      TaskGroup(
        id: 'g1',
        boardId: 'b1',
        name: 'To do',
        color: Colors.blue,
        tasks: [shared],
      ),
    ];

    await pump(
      tester,
      Column(
        children: [
          Expanded(
            child: BoardTable(
              groups: groups,
              members: members,
              statuses: statuses,
              collapsedGroupIds: const {},
              highlightedTaskId: shared.id,
              onToggleGroup: (_) {},
              onRenameGroup: (_) {},
              onDeleteGroup: (_) {},
              onEditTask: (_) {},
              onDeleteTask: (_) {},
              onStatusChanged: (_, _) async {},
              onProgressChanged: (_, _) async {},
              onOpenChat: (_) {},
            ),
          ),
          Expanded(
            child: BoardKanban(
              groups: groups,
              members: members,
              statuses: statuses,
              highlightedTaskId: shared.id,
              onEditTask: (_) {},
              onDeleteTask: (_) {},
              onStatusChanged: (_, _) async {},
              onProgressChanged: (_, _) async {},
              onOpenChat: (_) {},
            ),
          ),
        ],
      ),
    );
    expect(tester.takeException(), isNull);
  });
}
