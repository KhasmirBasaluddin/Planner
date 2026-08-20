import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:planner/features/planner/widgets/board_calendar.dart';
import 'package:planner/models/planner_models.dart';

/// The calendar's task dialog rendered as a grey barrier with no content, and
/// the console filled with mouse-tracker assertions. Opening it in a test is
/// the only way to see that — the analyzer cannot, and neither can reading.
void main() {
  const status = StatusLabel(
    id: 's1',
    name: 'Not started',
    color: Colors.grey,
    position: 0,
    isDefault: true,
  );

  PlannerTask task({DateTime? due, int comments = 0}) {
    return PlannerTask(
      id: 't1',
      groupId: 'g1',
      boardId: 'b1',
      title: 'Test',
      statusId: 's1',
      priority: TaskPriority.urgent,
      progress: 0.19,
      position: 0,
      dueDate: due,
      commentCount: comments,
    );
  }

  TaskGroup groupWith(PlannerTask t) => TaskGroup(
    id: 'g1',
    boardId: 'b1',
    name: 'To do',
    color: Colors.blue,
    tasks: [t],
  );

  /// Renders the calendar and taps the task chip, which is how the dialog is
  /// reached in the app.
  Future<void> openDialog(
    WidgetTester tester, {
    DateTime? due,
    int comments = 0,
  }) async {
    final t = task(due: due ?? DateTime.now(), comments: comments);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BoardCalendar(
            groups: [groupWith(t)],
            members: const [],
            statuses: const [status],
            onEditTask: (_) {},
            onDeleteTask: (_) {},
            onStatusChanged: (_, _) async {},
            onProgressChanged: (_, _) async {},
            onOpenChat: (_) {},
            onOpenNotes: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Test').first);
    await tester.pumpAndSettle();
  }

  group('calendar task dialog', () {
    testWidgets('opens without a rendering error', (tester) async {
      await openDialog(tester);

      // The title appears twice once open: on the calendar chip behind, and in
      // the dialog itself.
      expect(find.text('Test'), findsAtLeast(2));
      expect(find.text('Edit task'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);
    });

    testWidgets('leads with the due date and progress', (tester) async {
      await openDialog(tester, due: DateTime.now());

      expect(find.text('DUE'), findsOneWidget);
      // Two matches: the calendar's own Today button, and the due card.
      expect(find.text('Today'), findsNWidgets(2));
      expect(find.text('PROGRESS'), findsOneWidget);
      expect(find.text('19%'), findsOneWidget);
    });

    testWidgets('frames a due date as time remaining', (tester) async {
      // Tomorrow rather than further out: a date in the next month falls
      // outside the grid this calendar draws, so there is no chip to tap.
      await openDialog(
        tester,
        due: DateTime.now().add(const Duration(days: 1)),
      );
      // "Tomorrow" is the answer; the date is the raw material for it.
      expect(find.text('Tomorrow'), findsOneWidget);
      expect(find.text('DUE'), findsOneWidget);
    });

    testWidgets('an overdue task says how late it is', (tester) async {
      await openDialog(
        tester,
        due: DateTime.now().subtract(const Duration(days: 1)),
      );
      expect(find.text('Yesterday'), findsOneWidget);
    });

    testWidgets('shows the message count when there is one', (tester) async {
      await openDialog(tester, comments: 3);
      expect(find.text('Task chat'), findsOneWidget);
      expect(find.textContaining('3 messages'), findsOneWidget);
      expect(find.text('Open chat'), findsOneWidget);
    });

    testWidgets('an unassigned task says so rather than showing nothing', (
      tester,
    ) async {
      await openDialog(tester);
      expect(find.text('Unassigned'), findsOneWidget);
      expect(find.text('Urgent'), findsOneWidget);
    });
  });
}
