import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:planner/features/planner/widgets/board_header.dart';
import 'package:planner/features/planner/widgets/board_toolbar.dart';
import 'package:planner/features/planner/widgets/filter_panel.dart';
import 'package:planner/models/board_filter.dart';
import 'package:planner/models/planner_models.dart';

/// The header at the widths a desktop window actually gets dragged to.
///
/// Overflow is invisible to `flutter analyze` and shows up as a striped bar in
/// a screenshot, which is how the last two were found. These fail loudly
/// instead: a RenderFlex overflow throws in a test.
void main() {
  const board = Board(
    id: 'b1',
    // Long on purpose: the title shares the row with the filter bar and the
    // action buttons, so a real board name is the honest test.
    name: 'Vintazk 360 Dashboard',
    color: Color(0xFF4C5BD4),
    groups: [],
  );

  final members = [
    const WorkspaceMember(
      profile: UserProfile(
        id: 'u1',
        email: 'ak.basaluddin@vintazk.com',
        fullName: 'AL-Khasmir Basaluddin',
      ),
      role: WorkspaceRole.owner,
    ),
    const WorkspaceMember(
      profile: UserProfile(
        id: 'u2',
        email: 'ma@vintazk.com',
        fullName: 'Mohammad Aldrin',
      ),
      role: WorkspaceRole.member,
    ),
  ];

  /// Header and toolbar stacked, as the board renders them.
  ///
  /// The search moved from the header down to the toolbar row, so both have to
  /// be measured together — the widths that overflow are the ones where the
  /// view buttons and the filter bar compete for the same row.
  Widget harness({required double width, required BoardSearch search}) {
    return MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: width,
          child: Column(
            children: [
              BoardHeader(
                board: board,
                members: members,
                readOnly: false,
                onAddTask: () {},
                onAddGroup: () {},
                onRenameBoard: () {},
                onDeleteBoard: () {},
              ),
              BoardToolbar(
                mode: ViewMode.table,
                onModeChanged: (_) {},
                searchController: TextEditingController(),
                search: search,
                filters: filtersFor(
                  doneStatusIds: const {'s-done'},
                  stuckStatusIds: const {'s-stuck'},
                ),
                savedViews: const [],
                onSearchChanged: (_) {},
                onSaveView: (_, _) {},
                onDeleteView: (_) {},
                onApplyView: (_) {},
                taskOrder: TaskOrder.manual,
                onTaskOrderChanged: (_) {},
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Spanning each breakpoint in board_header.dart: tight below 700, narrow
  // below 900, full above.
  for (final width in <double>[640, 700, 860, 900, 1100, 1440, 1920]) {
    testWidgets('lays out at ${width.toInt()}px with no filters', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        harness(width: width, search: const BoardSearch()),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('lays out at ${width.toInt()}px with filters active', (
      tester,
    ) async {
      // Chips share the bar with the text box, so an active filter is the
      // worst case for the header's width.
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        harness(
          width: width,
          search: const BoardSearch()
              .toggle('mine')
              .toggle('overdue')
              .withGroup(GroupBy.status),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  }

  // Position, not just absence of overflow.
  //
  // The search first landed as an Expanded, which stretched it across the row
  // and parked it right beside the view buttons instead of at the right edge.
  group('the search sits on the right', () {
    testWidgets('past the halfway point of the toolbar', (tester) async {
      tester.view.physicalSize = const Size(1440, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        harness(width: 1440, search: const BoardSearch()),
      );

      final searchBox = tester.getRect(find.byType(FilterBar));
      final calendar = tester.getRect(find.text('Calendar'));
      // Measured against the toolbar's content box, not the window: the
      // container carries 28px of horizontal padding.
      final row = tester.getRect(
        find
            .descendant(
              of: find.byType(BoardToolbar),
              matching: find.byType(Row),
            )
            .first,
      );

      // Clear of the view switcher, not adjacent to it.
      expect(searchBox.left, greaterThan(calendar.right + 100));
      // And flush with the content box's right edge.
      expect(searchBox.right, closeTo(row.right, 1));
    });

    testWidgets('stays right-aligned when filters are active', (tester) async {
      tester.view.physicalSize = const Size(1440, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        harness(
          width: 1440,
          search: const BoardSearch().toggle('mine').toggle('overdue'),
        ),
      );

      final searchBox = tester.getRect(find.byType(FilterBar));
      final row = tester.getRect(
        find
            .descendant(
              of: find.byType(BoardToolbar),
              matching: find.byType(Row),
            )
            .first,
      );
      expect(searchBox.right, closeTo(row.right, 1));
    });
  });
}
