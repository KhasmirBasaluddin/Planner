import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:planner/features/planner/widgets/send_back_dialog.dart';
import 'package:planner/models/planner_models.dart';

void main() {
  const task = PlannerTask(
    id: 't1',
    groupId: 'g1',
    boardId: 'b1',
    title: 'Ship the report',
    priority: TaskPriority.high,
    progress: 1,
    position: 0,
  );
  const done = StatusLabel(
    id: 's-done',
    name: 'Done',
    color: Colors.green,
    isDone: true,
    position: 3,
  );
  const working = StatusLabel(
    id: 's-working',
    name: 'Working on it',
    color: Colors.orange,
    isDone: false,
    position: 1,
  );

  SendBackDecision? decision;
  var settled = false;

  Future<void> open(WidgetTester tester) async {
    decision = null;
    settled = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () async {
                decision = await showSendBackDialog(
                  context: context,
                  task: task,
                  from: done,
                  to: working,
                );
                settled = true;
              },
              child: const Text('go'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
  }

  testWidgets('confirming returns the typed comment', (tester) async {
    await open(tester);
    await tester.enterText(find.byType(TextField), '  Numbers are wrong  ');
    await tester.tap(find.text('Send back'));
    await tester.pumpAndSettle();
    expect(settled, isTrue);
    expect(decision?.comment, 'Numbers are wrong');
  });

  testWidgets('confirming with no text returns an empty comment', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(find.text('Send back'));
    await tester.pumpAndSettle();
    expect(settled, isTrue);
    expect(decision?.comment, '');
  });

  testWidgets('cancelling returns null', (tester) async {
    await open(tester);
    await tester.enterText(find.byType(TextField), 'typed then changed mind');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(settled, isTrue);
    expect(decision, isNull);
  });

  testWidgets('names both statuses so the mover knows what they are doing', (
    tester,
  ) async {
    await open(tester);
    expect(find.textContaining('Working on it'), findsWidgets);
    expect(find.textContaining('Done'), findsWidgets);
  });
}
