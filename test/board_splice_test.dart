import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:planner/models/planner_models.dart';

/// The splice at the heart of the incremental refresh.
///
/// When a realtime event names a board, only that board is re-fetched and
/// dropped into the list already on screen. The logic lives inline in
/// _refreshBoards; this mirrors it exactly, because the failure modes are
/// quiet ones — a board vanishing, or a stale copy surviving a refresh — and
/// neither shows up as an exception.
List<Board> splice({
  required List<Board> current,
  required Set<String> requested,
  required List<Board?> fetched,
}) {
  final replacements = {for (final board in fetched.nonNulls) board.id: board};
  final removed = requested.difference(replacements.keys.toSet());
  return [
    for (final board in current)
      if (!removed.contains(board.id)) replacements[board.id] ?? board,
  ];
}

Board board(String id, {String name = 'Board', int tasks = 0}) => Board(
  id: id,
  name: name,
  color: Colors.blue,
  groups: [
    TaskGroup(
      id: 'g-$id',
      boardId: id,
      name: 'To do',
      color: Colors.blue,
      tasks: [
        for (var n = 0; n < tasks; n++)
          PlannerTask(
            id: '$id-t$n',
            groupId: 'g-$id',
            boardId: id,
            title: 'Task $n',
            priority: TaskPriority.medium,
            progress: 0,
            position: n.toDouble(),
          ),
      ],
    ),
  ],
);

void main() {
  group('incremental board refresh', () {
    test('replaces only the board that changed', () {
      final current = [board('a', tasks: 1), board('b', tasks: 1)];
      final result = splice(
        current: current,
        requested: {'b'},
        fetched: [board('b', name: 'Renamed', tasks: 3)],
      );

      expect(result.length, 2);
      // Untouched, and the same instance — which is what lets the page's
      // memoisation skip recomputing a board nobody changed.
      expect(identical(result[0], current[0]), isTrue);
      expect(result[1].name, 'Renamed');
      expect(result[1].taskCount, 3);
    });

    test('keeps the order boards were already in', () {
      final result = splice(
        current: [board('a'), board('b'), board('c')],
        requested: {'b'},
        fetched: [board('b', name: 'Middle')],
      );
      expect(result.map((b) => b.id).toList(), ['a', 'b', 'c']);
    });

    test('drops a board that came back null', () {
      // Null means deleted, or no longer visible to this user. Leaving it on
      // screen would let someone click into a board they cannot read.
      final result = splice(
        current: [board('a'), board('b')],
        requested: {'b'},
        fetched: [null],
      );
      expect(result.map((b) => b.id).toList(), ['a']);
    });

    test('handles several boards changing at once', () {
      final result = splice(
        current: [board('a'), board('b'), board('c')],
        requested: {'a', 'c'},
        fetched: [
          board('a', name: 'First'),
          board('c', name: 'Third'),
        ],
      );
      expect(result.map((b) => b.name).toList(), ['First', 'Board', 'Third']);
    });

    test('ignores a board that is not on screen', () {
      // A change can name a board this user has since navigated away from,
      // or never had loaded. It must not be spliced in.
      final result = splice(
        current: [board('a')],
        requested: {'zz'},
        fetched: [board('zz')],
      );
      expect(result.map((b) => b.id).toList(), ['a']);
    });
  });
}
