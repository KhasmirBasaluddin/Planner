import 'package:flutter_test/flutter_test.dart';
import 'package:planner/models/board_filter.dart';
import 'package:planner/models/planner_models.dart';

/// The filter rules, tested without a widget in sight.
///
/// The behaviour worth pinning down is how multiple filters combine: same-kind
/// filters union and different kinds intersect. Get that backwards and every
/// second click empties the board, which is the failure mode that makes a
/// filter bar feel broken.
void main() {
  const me = 'u1';
  const teammate = 'u2';
  const doneId = 's-done';
  const stuckId = 's-stuck';
  const workingId = 's-working';

  final today = DateTime(2026, 7, 29);

  final context = FilterContext(
    currentUserId: me,
    today: today,
    doneStatusIds: const {doneId},
    stuckStatusIds: const {stuckId},
  );

  final filters = filtersFor(
    doneStatusIds: const {doneId},
    stuckStatusIds: const {stuckId},
  );

  PlannerTask task({
    String id = 't1',
    String title = 'Write the spec',
    String? statusId = workingId,
    TaskPriority priority = TaskPriority.medium,
    List<String> assignees = const [me],
    DateTime? due,
  }) {
    return PlannerTask(
      id: id,
      groupId: 'g1',
      boardId: 'b1',
      title: title,
      priority: priority,
      progress: 0,
      position: 0,
      statusId: statusId,
      assigneeIds: assignees,
      dueDate: due,
    );
  }

  bool passes(BoardSearch search, PlannerTask candidate) =>
      search.matches(candidate, context, filters);

  group('a search with nothing active', () {
    test('keeps every task', () {
      expect(passes(const BoardSearch(), task()), isTrue);
      expect(const BoardSearch().isEmpty, isTrue);
    });
  });

  group('single filters', () {
    test('my tasks keeps mine and drops a teammate\'s', () {
      final search = const BoardSearch().toggle('mine');
      expect(passes(search, task(assignees: const [me])), isTrue);
      expect(passes(search, task(assignees: const [teammate])), isFalse);
      expect(passes(search, task(assignees: const [])), isFalse);
    });

    test('unassigned keeps only tasks with nobody on them', () {
      final search = const BoardSearch().toggle('unassigned');
      expect(passes(search, task(assignees: const [])), isTrue);
      expect(passes(search, task(assignees: const [me])), isFalse);
    });

    test('done reads the board\'s own status ids', () {
      final search = const BoardSearch().toggle('done');
      expect(passes(search, task(statusId: doneId)), isTrue);
      expect(passes(search, task(statusId: workingId)), isFalse);
    });

    test('not done treats a task with no status as unfinished', () {
      final search = const BoardSearch().toggle('not_done');
      expect(passes(search, task(statusId: null)), isTrue);
      expect(passes(search, task(statusId: workingId)), isTrue);
      expect(passes(search, task(statusId: doneId)), isFalse);
    });
  });

  group('due dates', () {
    test('overdue is strictly before today', () {
      final search = const BoardSearch().toggle('overdue');
      expect(passes(search, task(due: DateTime(2026, 7, 28))), isTrue);
      // Due today is not yet overdue.
      expect(passes(search, task(due: today)), isFalse);
      expect(passes(search, task(due: DateTime(2026, 7, 30))), isFalse);
      expect(passes(search, task(due: null)), isFalse);
    });

    test('finished work is never overdue, however old', () {
      // Otherwise the filter fills with completed tasks and stops meaning
      // "needs action", which is the only reason to look at it.
      final search = const BoardSearch().toggle('overdue');
      final old = DateTime(2020, 1, 1);
      expect(passes(search, task(due: old, statusId: doneId)), isFalse);
      expect(passes(search, task(due: old, statusId: workingId)), isTrue);
    });

    test('due this week spans today through six days out', () {
      final search = const BoardSearch().toggle('due_this_week');
      expect(passes(search, task(due: today)), isTrue);
      expect(passes(search, task(due: DateTime(2026, 8, 4))), isTrue);
      expect(passes(search, task(due: DateTime(2026, 8, 5))), isFalse);
      expect(passes(search, task(due: DateTime(2026, 7, 28))), isFalse);
    });

    test('no due date is its own filter', () {
      final search = const BoardSearch().toggle('no_due_date');
      expect(passes(search, task(due: null)), isTrue);
      expect(passes(search, task(due: today)), isFalse);
    });
  });

  // The heart of it.
  group('combining filters', () {
    test('two filters of the same kind union', () {
      // Picking High and Urgent means "either", not "both" — no task could
      // ever be two priorities, so intersecting would always show nothing.
      final search = const BoardSearch()
          .toggle('priority_high')
          .toggle('priority_urgent');

      expect(passes(search, task(priority: TaskPriority.high)), isTrue);
      expect(passes(search, task(priority: TaskPriority.urgent)), isTrue);
      expect(passes(search, task(priority: TaskPriority.low)), isFalse);
    });

    test('filters of different kinds intersect', () {
      final search = const BoardSearch().toggle('mine').toggle('overdue');
      final yesterday = DateTime(2026, 7, 28);

      expect(
        passes(search, task(assignees: const [me], due: yesterday)),
        isTrue,
      );
      // Mine, but not overdue.
      expect(passes(search, task(assignees: const [me], due: null)), isFalse);
      // Overdue, but not mine.
      expect(
        passes(search, task(assignees: const [teammate], due: yesterday)),
        isFalse,
      );
    });

    test('unioned kinds still intersect with other kinds', () {
      final search = const BoardSearch()
          .toggle('priority_high')
          .toggle('priority_urgent')
          .toggle('mine');

      expect(
        passes(
          search,
          task(priority: TaskPriority.urgent, assignees: const [me]),
        ),
        isTrue,
      );
      expect(
        passes(
          search,
          task(priority: TaskPriority.urgent, assignees: const [teammate]),
        ),
        isFalse,
      );
      expect(
        passes(search, task(priority: TaskPriority.low, assignees: const [me])),
        isFalse,
      );
    });

    test('mine and unassigned union rather than cancelling out', () {
      // Both are assignment filters. Intersecting them is unsatisfiable.
      final search = const BoardSearch().toggle('mine').toggle('unassigned');
      expect(passes(search, task(assignees: const [me])), isTrue);
      expect(passes(search, task(assignees: const [])), isTrue);
      expect(passes(search, task(assignees: const [teammate])), isFalse);
    });
  });

  group('the text query', () {
    test('narrows by title, case-insensitively', () {
      const search = BoardSearch(query: 'SPEC');
      expect(passes(search, task(title: 'Write the spec')), isTrue);
      expect(passes(search, task(title: 'Ship it')), isFalse);
    });

    test('applies on top of the active filters', () {
      final search = const BoardSearch(query: 'spec').toggle('mine');
      expect(
        passes(search, task(title: 'Write the spec', assignees: const [me])),
        isTrue,
      );
      expect(
        passes(
          search,
          task(title: 'Write the spec', assignees: const [teammate]),
        ),
        isFalse,
      );
    });
  });

  group('toggling', () {
    test('a second toggle turns a filter back off', () {
      final search = const BoardSearch().toggle('mine').toggle('mine');
      expect(search.filterIds, isEmpty);
      expect(search.isEmpty, isTrue);
    });

    test('picking the active grouping clears it', () {
      final grouped = const BoardSearch().withGroup(GroupBy.status);
      expect(grouped.groupBy, GroupBy.status);
      expect(grouped.withGroup(GroupBy.status).groupBy, GroupBy.none);
    });

    test('picking a different grouping replaces it', () {
      final search = const BoardSearch()
          .withGroup(GroupBy.status)
          .withGroup(GroupBy.assignee);
      expect(search.groupBy, GroupBy.assignee);
    });

    test('clearing keeps the typed query', () {
      // The text box and the filter chips are separate controls; clearing the
      // chips should not empty the thing the user is mid-way through typing.
      final search = const BoardSearch(
        query: 'spec',
      ).toggle('mine').withGroup(GroupBy.status);
      expect(search.cleared.query, 'spec');
      expect(search.cleared.filterIds, isEmpty);
      expect(search.cleared.groupBy, GroupBy.none);
    });

    test('the chip count covers filters and grouping', () {
      final search = const BoardSearch()
          .toggle('mine')
          .toggle('overdue')
          .withGroup(GroupBy.status);
      expect(search.chipCount, 3);
    });
  });

  group('saving and restoring', () {
    test('a round trip preserves filters and grouping', () {
      final original = const BoardSearch()
          .toggle('mine')
          .toggle('overdue')
          .withGroup(GroupBy.priority);

      final restored = BoardSearch.fromMap(original.toMap());
      expect(restored.filterIds, original.filterIds);
      expect(restored.groupBy, GroupBy.priority);
    });

    test('the typed query is deliberately not saved', () {
      // A favorite is a shape — "my overdue work" — not the one-off word you
      // typed to find a single task inside it.
      const original = BoardSearch(query: 'spec');
      expect(BoardSearch.fromMap(original.toMap()).query, isEmpty);
    });

    test('an unknown grouping falls back rather than throwing', () {
      // A favorite saved by a newer build must not crash an older one.
      final restored = BoardSearch.fromMap({
        'filter_ids': ['mine'],
        'group_by': 'something_we_have_not_shipped',
      });
      expect(restored.groupBy, GroupBy.none);
      expect(restored.filterIds, {'mine'});
    });

    test('a malformed config degrades to an empty search', () {
      expect(BoardSearch.fromMap(const {}).isEmpty, isTrue);
    });

    test('SavedView carries its default flag through the config', () {
      final view = SavedView(
        id: 'v1',
        boardId: 'b1',
        name: 'My overdue',
        search: const BoardSearch().toggle('overdue'),
        isDefault: true,
      );

      final restored = SavedView.fromMap({
        'id': 'v1',
        'board_id': 'b1',
        'name': 'My overdue',
        'config': view.toConfig(),
      });

      expect(restored.isDefault, isTrue);
      expect(restored.search.filterIds, {'overdue'});
      expect(restored.name, 'My overdue');
    });
  });
}
