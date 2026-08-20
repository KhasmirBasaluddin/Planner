import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:planner/features/planner/widgets/board_table.dart';
import 'package:planner/models/planner_models.dart';

/// The table at the widths a desktop window actually gets dragged to.
///
/// It was the last view that refused to adapt — a 900px minimum and a
/// sideways scrollbar below it. Now the optional columns step aside one at a
/// time instead, and these tests pin both halves of that: nothing overflows,
/// and the right columns are present at each width.
void main() {
  const statuses = [
    StatusLabel(
      id: 's-working',
      name: 'Working on it',
      color: Colors.orange,
      position: 1,
    ),
    StatusLabel(
      id: 's-done',
      name: 'Done',
      color: Colors.green,
      position: 2,
      isDone: true,
    ),
  ];

  final members = [
    const WorkspaceMember(
      profile: UserProfile(
        id: 'u1',
        email: 'ak.basaluddin@vintazk.com',
        fullName: 'AL-Khasmir Basaluddin',
      ),
      role: WorkspaceRole.owner,
    ),
  ];

  PlannerTask task(int n) => PlannerTask(
    id: 't$n',
    groupId: 'g1',
    boardId: 'b1',
    // Long on purpose: the title cell is the one that gets squeezed.
    title: 'Forecast Accuracy / Billable Hours Feature Dashboard $n',
    statusId: 's-working',
    priority: TaskPriority.high,
    progress: 0.4,
    position: n.toDouble(),
    assigneeIds: const ['u1'],
    dueDate: DateTime.now().add(Duration(days: n)),
    startDate: DateTime.now(),
    endDate: DateTime.now().add(const Duration(days: 30)),
  );

  final group = TaskGroup(
    id: 'g1',
    boardId: 'b1',
    name: 'To do',
    color: Colors.blue,
    tasks: [for (var n = 0; n < 3; n++) task(n)],
  );

  Widget harness({required double width}) {
    return MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: width,
          child: BoardTable(
            groups: [group],
            members: members,
            statuses: statuses,
            collapsedGroupIds: const {},
            onToggleGroup: (_) {},
            onRenameGroup: (_) {},
            onDeleteGroup: (_) {},
            onEditTask: (_) {},
            onDeleteTask: (_) {},
            onStatusChanged: (_, _) async {},
            onProgressChanged: (_, _) async {},
            onOpenChat: (_) {},
            onOpenNotes: (_) {},
            onTaskReorder: (_, _, _) {},
          ),
        ),
      ),
    );
  }

  Future<void> pumpAt(WidgetTester tester, double width) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(harness(width: width));
  }

  // Spanning every breakpoint in TableColumns.forWidth, plus the horizontal
  // scroll floor.
  for (final width in <double>[480, 560, 640, 720, 800, 900, 1440]) {
    testWidgets('lays out at ${width.toInt()}px without overflowing', (
      tester,
    ) async {
      await pumpAt(tester, width);
      expect(tester.takeException(), isNull);
    });
  }

  // The header cells render their labels uppercased.
  testWidgets('a wide window shows every column', (tester) async {
    await pumpAt(tester, 1440);
    expect(find.text('OWNER'), findsOneWidget);
    expect(find.text('PRIORITY'), findsOneWidget);
    expect(find.text('TIMELINE'), findsOneWidget);
  });

  testWidgets('the timeline steps aside first', (tester) async {
    await pumpAt(tester, 820);
    expect(find.text('TIMELINE'), findsNothing);
    expect(find.text('OWNER'), findsOneWidget);
    expect(find.text('PRIORITY'), findsOneWidget);
  });

  testWidgets('then the owner column', (tester) async {
    await pumpAt(tester, 720);
    expect(find.text('TIMELINE'), findsNothing);
    expect(find.text('OWNER'), findsNothing);
    expect(find.text('PRIORITY'), findsOneWidget);
  });

  testWidgets('task, status and due survive to the narrowest widths', (
    tester,
  ) async {
    await pumpAt(tester, 560);
    expect(find.text('TASK'), findsOneWidget);
    expect(find.text('STATUS'), findsOneWidget);
    expect(find.text('DUE'), findsOneWidget);
    expect(find.text('PRIORITY'), findsNothing);
  });
}
