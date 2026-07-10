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

enum ViewMode { table, kanban, calendar }

enum TaskOrder {
  manual('Manual'),
  title('Title'),
  dueDate('Due date'),
  priority('Priority'),
  status('Status');

  const TaskOrder(this.label);
  final String label;
}
