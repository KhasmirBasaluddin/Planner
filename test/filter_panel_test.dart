import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:planner/features/planner/widgets/filter_panel.dart';
import 'package:planner/models/board_filter.dart';
import 'package:planner/models/planner_models.dart';

/// The panel itself, rendered.
///
/// The logic tests in board_filter_test.dart cover what a filter *means*; these
/// cover that the panel shows it, because a filtered board that does not say it
/// is filtered reads as a board with tasks missing.
void main() {
  final filters = filtersFor(
    doneStatusIds: const {'s-done'},
    stuckStatusIds: const {'s-stuck'},
  );

  /// The panel picks its layout from MediaQuery, so the surface has to be wide
  /// enough for the four-column form — 940px is the breakpoint.
  Widget harness({
    required BoardSearch search,
    double width = 1200,
    List<SavedView> savedViews = const [],
    ValueChanged<BoardSearch>? onChanged,
    void Function(String name, bool isDefault)? onSaveView,
    ValueChanged<SavedView>? onDeleteView,
    ValueChanged<SavedView>? onApplyView,
    void Function(SavedView view, bool isDefault)? onSetDefaultView,
    TaskOrder taskOrder = TaskOrder.manual,
    ValueChanged<TaskOrder>? onTaskOrderChanged,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: width,
          child: FilterBar(
            search: search,
            filters: filters,
            savedViews: savedViews,
            controller: TextEditingController(text: search.query),
            onChanged: onChanged ?? (_) {},
            onSaveView: onSaveView ?? (_, _) {},
            onDeleteView: onDeleteView ?? (_) {},
            onApplyView: onApplyView ?? (_) {},
            onSetDefaultView: onSetDefaultView ?? (_, _) {},
            taskOrder: taskOrder,
            onTaskOrderChanged: onTaskOrderChanged ?? (_) {},
          ),
        ),
      ),
    );
  }

  /// Sets a desktop-sized surface. MediaQuery drives the panel's layout, and
  /// the default 800x600 test window falls below the four-column breakpoint.
  void desktop(WidgetTester tester, {double width = 1200}) {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  group('the chip bar', () {
    testWidgets('shows nothing but the box when no filter is on', (
      tester,
    ) async {
      desktop(tester);
      await tester.pumpWidget(harness(search: const BoardSearch()));
      expect(find.text('Search tasks…'), findsOneWidget);
      expect(find.byIcon(Icons.filter_alt_outlined), findsNothing);
    });

    testWidgets('names each active filter', (tester) async {
      desktop(tester);
      await tester.pumpWidget(
        harness(search: const BoardSearch().toggle('mine').toggle('overdue')),
      );
      expect(find.text('My tasks'), findsOneWidget);
      expect(find.text('Overdue'), findsOneWidget);
    });

    testWidgets('shows the grouping as its own chip', (tester) async {
      desktop(tester);
      await tester.pumpWidget(
        harness(search: const BoardSearch().withGroup(GroupBy.status)),
      );
      expect(find.text('Status'), findsOneWidget);
      expect(find.byIcon(Icons.layers_outlined), findsOneWidget);
    });

    testWidgets('a chip removes only its own filter', (tester) async {
      desktop(tester);
      BoardSearch? updated;
      await tester.pumpWidget(
        harness(
          search: const BoardSearch().toggle('mine').toggle('overdue'),
          onChanged: (value) => updated = value,
        ),
      );

      // The close button inside the first chip, not the bar's clear-all.
      await tester.tap(find.byIcon(Icons.close_rounded).first);
      await tester.pump();

      expect(updated, isNotNull);
      expect(updated!.filterIds.length, 1);
    });
  });

  group('the dropdown', () {
    Future<void> open(WidgetTester tester) async {
      await tester.tap(find.byIcon(Icons.keyboard_arrow_down_rounded));
      await tester.pumpAndSettle();
    }

    testWidgets('has all four columns', (tester) async {
      desktop(tester);
      await tester.pumpWidget(harness(search: const BoardSearch()));
      await open(tester);

      expect(find.text('Filters'), findsOneWidget);
      expect(find.text('Group By'), findsOneWidget);
      // Sort moved in here from its own toolbar button.
      expect(find.text('Sort'), findsOneWidget);
      expect(find.text('Favorites'), findsOneWidget);
    });

    testWidgets('offers every sort order', (tester) async {
      desktop(tester);
      await tester.pumpWidget(harness(search: const BoardSearch()));
      await open(tester);

      for (final order in TaskOrder.values) {
        expect(find.text(order.label), findsWidgets, reason: order.label);
      }
    });

    testWidgets('picking a sort order reports it', (tester) async {
      desktop(tester);
      TaskOrder? picked;
      await tester.pumpWidget(
        harness(
          search: const BoardSearch(),
          onTaskOrderChanged: (value) => picked = value,
        ),
      );
      await open(tester);
      await tester.tap(find.text('Due date').last);
      await tester.pump();

      expect(picked, TaskOrder.dueDate);
    });

    testWidgets('offers every filter the board defines', (tester) async {
      desktop(tester);
      await tester.pumpWidget(harness(search: const BoardSearch()));
      await open(tester);

      expect(find.text('My tasks'), findsOneWidget);
      expect(find.text('Unassigned'), findsOneWidget);
      expect(find.text('Overdue'), findsOneWidget);
      expect(find.text('No due date'), findsOneWidget);
    });

    testWidgets('picking a filter reports it without closing', (tester) async {
      desktop(tester);
      BoardSearch? updated;
      await tester.pumpWidget(
        harness(
          search: const BoardSearch(),
          onChanged: (value) => updated = value,
        ),
      );
      await open(tester);
      await tester.tap(find.text('My tasks'));
      await tester.pump();

      expect(updated?.filterIds, {'mine'});
      // Still open: picking two filters in a row is the normal case.
      expect(find.text('Group By'), findsOneWidget);
    });

    testWidgets('says so when there are no favorites yet', (tester) async {
      desktop(tester);
      await tester.pumpWidget(harness(search: const BoardSearch()));
      await open(tester);
      expect(find.text('No saved filters yet.'), findsOneWidget);
    });

    testWidgets('lists saved favorites by name', (tester) async {
      desktop(tester);
      await tester.pumpWidget(
        harness(
          search: const BoardSearch(),
          savedViews: [
            SavedView(
              id: 'v1',
              boardId: 'b1',
              name: 'My overdue work',
              search: const BoardSearch().toggle('overdue'),
            ),
          ],
        ),
      );
      await open(tester);
      expect(find.text('My overdue work'), findsOneWidget);
    });

    testWidgets('applying a favorite hands back its search', (tester) async {
      desktop(tester);
      SavedView? applied;
      final view = SavedView(
        id: 'v1',
        boardId: 'b1',
        name: 'My overdue work',
        search: const BoardSearch().toggle('overdue'),
      );

      await tester.pumpWidget(
        harness(
          search: const BoardSearch(),
          savedViews: [view],
          onApplyView: (value) => applied = value,
        ),
      );
      await open(tester);
      await tester.tap(find.text('My overdue work'));
      await tester.pumpAndSettle();

      expect(applied?.id, 'v1');
      expect(applied?.search.filterIds, {'overdue'});
    });

    // Promoting an existing favorite, without re-saving it under the same
    // name — the star on the row is the only way to do that.
    testWidgets('the star promotes a favorite to the default', (tester) async {
      desktop(tester);
      SavedView? promoted;
      bool? promotedTo;
      final view = SavedView(
        id: 'v1',
        boardId: 'b1',
        name: 'My overdue work',
        search: const BoardSearch().toggle('overdue'),
      );

      await tester.pumpWidget(
        harness(
          search: const BoardSearch(),
          savedViews: [view],
          onSetDefaultView: (value, isDefault) {
            promoted = value;
            promotedTo = isDefault;
          },
        ),
      );
      await open(tester);
      // The row's controls appear on hover while it is not the default.
      final pointer = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(
        pointer.hover(tester.getCenter(find.text('My overdue work'))),
      );
      await tester.pumpAndSettle();

      // Scoped to the row: the Favorites section header carries an outline
      // star of its own.
      await tester.tap(
        find.descendant(
          of: find.byTooltip('Apply automatically when this board opens'),
          matching: find.byIcon(Icons.star_outline_rounded),
        ),
      );
      await tester.pumpAndSettle();

      expect(promoted?.id, 'v1');
      expect(promotedTo, isTrue);
    });

    testWidgets('the star clears a default that is already set', (
      tester,
    ) async {
      desktop(tester);
      bool? promotedTo;
      final view = SavedView(
        id: 'v1',
        boardId: 'b1',
        name: 'My overdue work',
        search: const BoardSearch().toggle('overdue'),
        isDefault: true,
      );

      await tester.pumpWidget(
        harness(
          search: const BoardSearch(),
          savedViews: [view],
          onSetDefaultView: (_, isDefault) => promotedTo = isDefault,
        ),
      );
      await open(tester);
      await tester.tap(find.byIcon(Icons.star_rounded));
      await tester.pumpAndSettle();

      expect(promotedTo, isFalse);
    });

    testWidgets('saving asks for a name and reports it', (tester) async {
      desktop(tester);
      String? savedName;
      bool? savedDefault;

      await tester.pumpWidget(
        harness(
          search: const BoardSearch().toggle('mine'),
          onSaveView: (name, isDefault) {
            savedName = name;
            savedDefault = isDefault;
          },
        ),
      );
      await open(tester);

      await tester.tap(find.text('Save current filter'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).last, 'My work');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(savedName, 'My work');
      expect(savedDefault, isFalse);
    });

    testWidgets('an unnamed favorite is not saved, and says why', (
      tester,
    ) async {
      desktop(tester);
      var called = false;
      await tester.pumpWidget(
        harness(
          search: const BoardSearch().toggle('mine'),
          onSaveView: (_, _) => called = true,
        ),
      );
      await open(tester);
      await tester.tap(find.text('Save current filter'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(called, isFalse);
      // Silence here reads as a broken button, so the refusal is stated.
      expect(find.text('Give this filter a name.'), findsOneWidget);
    });

    testWidgets('the error clears once a name is typed', (tester) async {
      desktop(tester);
      await tester.pumpWidget(
        harness(search: const BoardSearch().toggle('mine')),
      );
      await open(tester);
      await tester.tap(find.text('Save current filter'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text('Give this filter a name.'), findsOneWidget);

      await tester.enterText(find.byType(TextField).last, 'My work');
      await tester.pumpAndSettle();

      // Stale errors on a field you are actively fixing are noise.
      expect(find.text('Give this filter a name.'), findsNothing);
    });
  });

  // The panel is ~880px of columns hanging off a right-aligned button. On a
  // smaller window it used to run off the left edge of the screen and past the
  // bottom, because MenuAnchor positions from its button and does not clamp an
  // oversized child.
  group('on a narrow window', () {
    testWidgets('stacks the sections instead of showing four columns', (
      tester,
    ) async {
      desktop(tester, width: 820);
      await tester.pumpWidget(harness(search: const BoardSearch(), width: 820));
      await tester.tap(find.byIcon(Icons.keyboard_arrow_down_rounded));
      await tester.pumpAndSettle();

      // Every section is still reachable, just stacked.
      expect(find.text('Filters'), findsOneWidget);
      expect(find.text('Group By'), findsOneWidget);
      expect(find.text('Sort'), findsOneWidget);
      expect(find.text('Favorites'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('fits inside the screen', (tester) async {
      desktop(tester, width: 820);
      await tester.pumpWidget(harness(search: const BoardSearch(), width: 820));
      await tester.tap(find.byIcon(Icons.keyboard_arrow_down_rounded));
      await tester.pumpAndSettle();

      final panel = tester.getRect(find.text('Filters').first);
      // The heading used to sit at a negative x, off the left of the screen.
      expect(panel.left, greaterThanOrEqualTo(0));
      expect(panel.right, lessThanOrEqualTo(820));
    });

    testWidgets('still applies a filter', (tester) async {
      BoardSearch? updated;
      desktop(tester, width: 820);
      await tester.pumpWidget(
        harness(
          search: const BoardSearch(),
          width: 820,
          onChanged: (value) => updated = value,
        ),
      );
      await tester.tap(find.byIcon(Icons.keyboard_arrow_down_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.text('My tasks'));
      await tester.pump();

      expect(updated?.filterIds, {'mine'});
    });
  });
}
