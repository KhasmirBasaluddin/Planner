import 'package:flutter/material.dart';

class Board {
  const Board({
    required this.id,
    required this.name,
    required this.color,
    required this.groups,
  });

  final int id;
  final String name;
  final Color color;
  final List<TaskGroup> groups;

  int get taskCount => groups.fold(0, (sum, group) => sum + group.tasks.length);

  int get doneCount => groups.fold(0, (sum, group) {
    return sum +
        group.tasks.where((task) => task.status == TaskStatus.done).length;
  });
}

class TaskGroup {
  const TaskGroup({
    required this.id,
    required this.boardId,
    required this.name,
    required this.color,
    required this.tasks,
  });

  final int id;
  final int boardId;
  final String name;
  final Color color;
  final List<PlannerTask> tasks;
}

class PlannerTask {
  const PlannerTask({
    required this.id,
    required this.groupId,
    required this.title,
    required this.owner,
    required this.status,
    required this.priority,
    required this.dueDate,
    required this.timeline,
    required this.progress,
    this.notes = const [],
  });

  final int id;
  final int groupId;
  final String title;
  final String owner;
  final TaskStatus status;
  final TaskPriority priority;
  final String dueDate;
  final String timeline;
  final double progress;

  /// Multiple free-text notes attached to the task (newest last).
  final List<String> notes;
}

enum TaskStatus {
  done('Done'),
  working('Working'),
  stuck('Stuck'),
  notStarted('Not started');

  const TaskStatus(this.label);
  final String label;

  static TaskStatus fromName(String value) {
    return TaskStatus.values.firstWhere(
      (status) => status.name == value,
      orElse: () => TaskStatus.notStarted,
    );
  }
}

enum TaskPriority {
  high('High'),
  medium('Medium'),
  low('Low');

  const TaskPriority(this.label);
  final String label;

  static TaskPriority fromName(String value) {
    return TaskPriority.values.firstWhere(
      (priority) => priority.name == value,
      orElse: () => TaskPriority.medium,
    );
  }
}

/// A free-floating note on the sticky board. Position, size and stacking are
/// persisted so the canvas is restored exactly as the user arranged it.
class StickyNote {
  const StickyNote({
    required this.id,
    required this.title,
    required this.body,
    required this.color,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.z,
    required this.pinned,
    required this.taskId,
    required this.createdAt,
    required this.updatedAt,
  });

  final int id;
  final String title;

  /// Quill Delta JSON, matching the format used by task notes.
  final String body;
  final Color color;
  final double x;
  final double y;
  final double width;
  final double height;
  final int z;
  final bool pinned;

  /// Set when the note was created from a task, so the card can link back.
  final int? taskId;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isLinkedToTask => taskId != null;

  StickyNote copyWith({
    String? title,
    String? body,
    Color? color,
    double? x,
    double? y,
    double? width,
    double? height,
    int? z,
    bool? pinned,
    DateTime? updatedAt,
  }) {
    return StickyNote(
      id: id,
      title: title ?? this.title,
      body: body ?? this.body,
      color: color ?? this.color,
      x: x ?? this.x,
      y: y ?? this.y,
      width: width ?? this.width,
      height: height ?? this.height,
      z: z ?? this.z,
      pinned: pinned ?? this.pinned,
      taskId: taskId,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

enum ViewMode { table, kanban, calendar }

/// Top-level destinations in the sidebar.
enum WorkspaceView { board, notes }

enum TaskOrder {
  manual('Manual'),
  title('Title'),
  dueDate('Due date'),
  priority('Priority'),
  status('Status');

  const TaskOrder(this.label);
  final String label;
}
