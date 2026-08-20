import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:planner/features/planner/widgets/review_dialog.dart';
import 'package:planner/models/planner_models.dart';

/// The submit / send-back dialog, which replaced the old send-back-only one.
///
/// The behaviour worth pinning down is that a cancel really cancels — the
/// whole status change is abandoned, so a mis-drag costs nothing — and that
/// the note stays optional in both directions.
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
    position: 1,
  );
  const stuck = StatusLabel(
    id: 's-stuck',
    name: 'Stuck',
    color: Colors.red,
    position: 2,
  );

  ReviewDecision? decision;
  var settled = false;

  Future<void> open(
    WidgetTester tester, {
    ReviewKind kind = ReviewKind.sendBack,
    List<StatusLabel> targets = const [],
  }) async {
    decision = null;
    settled = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () async {
                decision = await showReviewDialog(
                  context: context,
                  task: task,
                  kind: kind,
                  from: kind == ReviewKind.sendBack ? done : working,
                  to: kind == ReviewKind.sendBack ? working : done,
                  targets: targets,
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

  group('sending work back', () {
    testWidgets('confirming returns the typed note, trimmed', (tester) async {
      await open(tester);
      await tester.enterText(find.byType(TextField), '  Numbers are wrong  ');
      await tester.tap(find.text('Send back'));
      await tester.pumpAndSettle();
      expect(settled, isTrue);
      expect(decision?.body, 'Numbers are wrong');
    });

    testWidgets('the note is optional', (tester) async {
      await open(tester);
      await tester.tap(find.text('Send back'));
      await tester.pumpAndSettle();
      expect(settled, isTrue);
      expect(decision?.body, '');
      expect(decision?.uploads, isEmpty);
    });

    testWidgets('cancelling abandons the whole move', (tester) async {
      await open(tester);
      await tester.enterText(find.byType(TextField), 'changed my mind');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(settled, isTrue);
      expect(decision, isNull);
    });

    testWidgets('names the task being sent back', (tester) async {
      await open(tester);
      expect(find.textContaining('Ship the report'), findsWidgets);
    });

    testWidgets('offers every non-done status as a destination', (
      tester,
    ) async {
      await open(tester, targets: const [working, stuck]);
      expect(find.text('Working on it'), findsOneWidget);
      expect(find.text('Stuck'), findsOneWidget);
    });

    testWidgets('picking a different destination is what comes back', (
      tester,
    ) async {
      await open(tester, targets: const [working, stuck]);
      await tester.tap(find.text('Stuck'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Send back'));
      await tester.pumpAndSettle();
      expect(decision?.target?.id, 's-stuck');
    });

    testWidgets('a single destination needs no chooser', (tester) async {
      await open(tester, targets: const [working]);
      expect(find.text('Move it to'), findsNothing);
    });

    testWidgets('assignment is left alone unless it is changed', (
      tester,
    ) async {
      await open(tester);
      await tester.tap(find.text('Send back'));
      await tester.pumpAndSettle();
      // Null rather than an empty list: "leave it with whoever has it" and
      // "unassign everyone" must not collapse into the same answer.
      expect(decision?.reassignTo, isNull);
    });
  });

  group('submitting work', () {
    testWidgets('confirms with the submit wording', (tester) async {
      await open(tester, kind: ReviewKind.submit);
      expect(find.text('Submit work'), findsOneWidget);
      expect(find.text('Send back'), findsNothing);
    });

    testWidgets('the note is optional here too', (tester) async {
      await open(tester, kind: ReviewKind.submit);
      await tester.tap(find.text('Submit work'));
      await tester.pumpAndSettle();
      expect(decision?.body, '');
    });

    testWidgets('offers no status chooser and no reassignment', (
      tester,
    ) async {
      await open(tester, kind: ReviewKind.submit, targets: const [working]);
      expect(find.text('Move it to'), findsNothing);
      expect(find.text('Who picks it up'), findsNothing);
    });
  });

  group('content types', () {
    test('images are recognised so they can preview inline', () {
      expect(contentTypeForFile('shot.PNG'), 'image/png');
      expect(contentTypeForFile('shot.jpeg'), 'image/jpeg');
    });

    test('documents get their own type', () {
      expect(contentTypeForFile('report.pdf'), 'application/pdf');
    });

    test('anything unrecognised still uploads', () {
      expect(contentTypeForFile('mystery.xyz'), 'application/octet-stream');
      expect(contentTypeForFile('noextension'), 'application/octet-stream');
    });
  });
}
