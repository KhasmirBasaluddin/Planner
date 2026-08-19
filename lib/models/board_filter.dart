/// The saved-search model behind the filter panel.
///
/// Three independent things, the way Odoo's search view separates them:
///
///   * **Filters** narrow which tasks are shown. Several may be active at once.
///   * **Group by** decides how the survivors are bucketed for display.
///   * **Favorites** are a named [BoardSearch] — filters and grouping together
///     — saved so a search worth repeating does not have to be rebuilt.
///
/// Everything here is pure: no widgets, no Supabase. The panel renders it and
/// [BoardSearch.apply] is the only thing that decides what a filter means, so
/// the rules can be tested without pumping a frame.
library;

import 'planner_models.dart';

/// A predicate offered in the Filters column.
///
/// Filters of *different* kinds intersect — "Not done" AND "Overdue" shows
/// tasks that are both. Filters of the *same* kind union, so picking High and
/// Urgent shows either, which is what someone selecting two priorities means.
/// This mirrors Odoo, and it is the behaviour that makes a filter bar usable:
/// intersecting same-kind filters would make every second click empty the list.
enum FilterKind {
  /// Assignment: mine, or unassigned.
  assignment,

  /// Progress state, read from the task's status label.
  state,

  /// Where the due date falls relative to today.
  due,

  /// The task's priority.
  priority,
}

/// One toggleable filter.
class BoardFilter {
  const BoardFilter({
    required this.id,
    required this.label,
    required this.kind,
    required this.matches,
  });

  /// Stable across sessions: this is what a saved favorite stores.
  final String id;
  final String label;
  final FilterKind kind;

  /// True when [task] survives this filter.
  final bool Function(PlannerTask task, FilterContext context) matches;
}

/// What a filter needs to know beyond the task itself.
///
/// Passed in rather than read from a global so the rules stay pure: "my tasks"
/// depends on who is asking, and "done" depends on how this board labels its
/// statuses, neither of which lives on PlannerTask.
class FilterContext {
  const FilterContext({
    required this.currentUserId,
    required this.today,
    this.doneStatusIds = const {},
    this.stuckStatusIds = const {},
  });

  final String currentUserId;

  /// Midnight today. Passed in rather than read from the clock so a filter's
  /// behaviour is fixed for the whole pass and testable without freezing time.
  final DateTime today;

  final Set<String> doneStatusIds;
  final Set<String> stuckStatusIds;
}

/// How the surviving tasks are bucketed.
enum GroupBy {
  /// The board's own groups, as authored. The default.
  none('Group', null),
  status('Status', FilterKind.state),
  assignee('Assignee', FilterKind.assignment),
  priority('Priority', FilterKind.priority),
  dueDate('Due date', FilterKind.due);

  const GroupBy(this.label, this.relatedKind);

  final String label;

  /// The filter kind this grouping reflects, used only for the panel's icon.
  final FilterKind? relatedKind;
}

/// The filters and grouping currently in effect.
///
/// Immutable — every change returns a new one, so undoing a filter is just
/// keeping the previous value and there is no way to mutate the active search
/// out from under a widget mid-build.
class BoardSearch {
  const BoardSearch({
    this.filterIds = const {},
    this.groupBy = GroupBy.none,
    this.query = '',
  });

  factory BoardSearch.fromMap(Map<String, dynamic> map) {
    final ids =
        (map['filter_ids'] as List?)?.cast<String>() ?? const <String>[];
    return BoardSearch(
      filterIds: ids.toSet(),
      groupBy: GroupBy.values.firstWhere(
        (value) => value.name == map['group_by'],
        orElse: () => GroupBy.none,
      ),
      // The text box is deliberately not saved with a favorite: a saved search
      // is a shape ("my overdue work"), not the one-off word you typed to find
      // a single task inside it.
      query: '',
    );
  }

  final Set<String> filterIds;
  final GroupBy groupBy;
  final String query;

  bool get isEmpty =>
      filterIds.isEmpty && groupBy == GroupBy.none && query.trim().isEmpty;

  /// Active filters plus grouping, for the chip bar's count.
  int get chipCount => filterIds.length + (groupBy == GroupBy.none ? 0 : 1);

  BoardSearch copyWith({
    Set<String>? filterIds,
    GroupBy? groupBy,
    String? query,
  }) {
    return BoardSearch(
      filterIds: filterIds ?? this.filterIds,
      groupBy: groupBy ?? this.groupBy,
      query: query ?? this.query,
    );
  }

  /// Turns [id] on if off, off if on.
  BoardSearch toggle(String id) {
    final next = Set<String>.from(filterIds);
    if (!next.remove(id)) {
      next.add(id);
    }
    return copyWith(filterIds: next);
  }

  /// Clears the grouping when [group] is already active, so the same click
  /// that applied it takes it away.
  BoardSearch withGroup(GroupBy group) =>
      copyWith(groupBy: groupBy == group ? GroupBy.none : group);

  BoardSearch remove(String id) =>
      copyWith(filterIds: Set<String>.from(filterIds)..remove(id));

  BoardSearch get cleared => BoardSearch(query: query);

  Map<String, dynamic> toMap() => {
    'filter_ids': filterIds.toList()..sort(),
    'group_by': groupBy.name,
  };

  /// True when [task] passes every active filter.
  ///
  /// Same-kind filters union, different kinds intersect — see [FilterKind].
  bool matches(
    PlannerTask task,
    FilterContext context,
    List<BoardFilter> available,
  ) {
    if (query.trim().isNotEmpty &&
        !task.title.toLowerCase().contains(query.trim().toLowerCase())) {
      return false;
    }
    if (filterIds.isEmpty) {
      return true;
    }

    final active = available.where((f) => filterIds.contains(f.id));
    final byKind = <FilterKind, List<BoardFilter>>{};
    for (final filter in active) {
      byKind.putIfAbsent(filter.kind, () => []).add(filter);
    }

    for (final group in byKind.values) {
      if (!group.any((filter) => filter.matches(task, context))) {
        return false;
      }
    }
    return true;
  }

  /// By value, not identity.
  ///
  /// Every mutation here returns a fresh instance, so identity says only
  /// "something was rebuilt" — which made it useless for deciding whether the
  /// filtered board actually needs recomputing. The board page caches that
  /// work against this comparison.
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is BoardSearch &&
        other.groupBy == groupBy &&
        other.query == query &&
        other.filterIds.length == filterIds.length &&
        other.filterIds.containsAll(filterIds);
  }

  @override
  int get hashCode => Object.hash(
    groupBy,
    query,
    // Order-independent, matching the set semantics above.
    Object.hashAllUnordered(filterIds),
  );
}

/// A named [BoardSearch], saved for reuse.
///
/// Stored in `board_views` — the table has held a name, a jsonb config, and a
/// created_by since the schema was built, which is exactly this. Favorites are
/// private to whoever saved them.
class SavedView {
  const SavedView({
    required this.id,
    required this.boardId,
    required this.name,
    required this.search,
    this.isDefault = false,
  });

  factory SavedView.fromMap(Map<String, dynamic> map) {
    final config = (map['config'] as Map?)?.cast<String, dynamic>() ?? const {};
    return SavedView(
      id: map['id'] as String,
      boardId: (map['board_id'] ?? '') as String,
      name: (map['name'] ?? '') as String,
      search: BoardSearch.fromMap(config),
      isDefault: (config['is_default'] ?? false) as bool,
    );
  }

  final String id;
  final String boardId;
  final String name;
  final BoardSearch search;

  /// Applied automatically when the board opens. At most one per board — the
  /// repository clears the flag on the others when one is set.
  final bool isDefault;

  Map<String, dynamic> toConfig() => {
    ...search.toMap(),
    'is_default': isDefault,
  };

  SavedView copyWith({String? name, BoardSearch? search, bool? isDefault}) {
    return SavedView(
      id: id,
      boardId: boardId,
      name: name ?? this.name,
      search: search ?? this.search,
      isDefault: isDefault ?? this.isDefault,
    );
  }
}

/// The filters offered for a board.
///
/// Built per board rather than declared as a constant because "Done" and
/// "Stuck" are status *labels* the board owns, and their ids differ from board
/// to board. The ids here are stable strings, so a favorite saved today still
/// resolves after the board's statuses are renamed.
List<BoardFilter> filtersFor({
  required Set<String> doneStatusIds,
  required Set<String> stuckStatusIds,
}) {
  return [
    BoardFilter(
      id: 'mine',
      label: 'My tasks',
      kind: FilterKind.assignment,
      matches: (task, context) =>
          task.assigneeIds.contains(context.currentUserId),
    ),
    BoardFilter(
      id: 'unassigned',
      label: 'Unassigned',
      kind: FilterKind.assignment,
      matches: (task, context) => task.assigneeIds.isEmpty,
    ),
    BoardFilter(
      id: 'not_done',
      label: 'Not done',
      kind: FilterKind.state,
      matches: (task, context) =>
          task.statusId == null ||
          !context.doneStatusIds.contains(task.statusId),
    ),
    BoardFilter(
      id: 'done',
      label: 'Done',
      kind: FilterKind.state,
      matches: (task, context) =>
          task.statusId != null &&
          context.doneStatusIds.contains(task.statusId),
    ),
    BoardFilter(
      id: 'stuck',
      label: 'Stuck',
      kind: FilterKind.state,
      matches: (task, context) =>
          task.statusId != null &&
          context.stuckStatusIds.contains(task.statusId),
    ),
    BoardFilter(
      id: 'overdue',
      label: 'Overdue',
      kind: FilterKind.due,
      // Done work is never overdue, however old the date. Without this the
      // filter fills up with finished tasks and stops meaning "needs action".
      matches: (task, context) {
        final due = task.dueDate;
        if (due == null) return false;
        if (task.statusId != null &&
            context.doneStatusIds.contains(task.statusId)) {
          return false;
        }
        return DateTime(due.year, due.month, due.day).isBefore(context.today);
      },
    ),
    BoardFilter(
      id: 'due_this_week',
      label: 'Due this week',
      kind: FilterKind.due,
      matches: (task, context) {
        final due = task.dueDate;
        if (due == null) return false;
        final day = DateTime(due.year, due.month, due.day);
        final end = context.today.add(const Duration(days: 7));
        return !day.isBefore(context.today) && day.isBefore(end);
      },
    ),
    BoardFilter(
      id: 'no_due_date',
      label: 'No due date',
      kind: FilterKind.due,
      matches: (task, context) => task.dueDate == null,
    ),
    for (final priority in TaskPriority.values)
      BoardFilter(
        id: 'priority_${priority.name}',
        label: priority.label,
        kind: FilterKind.priority,
        matches: (task, context) => task.priority == priority,
      ),
  ];
}
