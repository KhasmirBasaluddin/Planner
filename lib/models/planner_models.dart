import 'package:flutter/material.dart';

/// A person in a workspace. Names come from `profiles`, which mirrors
/// `auth.users`.
class UserProfile {
  const UserProfile({
    required this.id,
    required this.email,
    required this.fullName,
    this.avatarUrl = '',
  });

  factory UserProfile.fromMap(Map<String, dynamic> map) {
    return UserProfile(
      id: map['id'] as String,
      email: (map['email'] ?? '') as String,
      fullName: (map['full_name'] ?? '') as String,
      avatarUrl: (map['avatar_url'] ?? '') as String,
    );
  }

  final String id;
  final String email;
  final String fullName;
  final String avatarUrl;

  /// Falls back to the email local-part when no name has been set.
  String get displayName {
    if (fullName.trim().isNotEmpty) {
      return fullName.trim();
    }
    final at = email.indexOf('@');
    return at > 0 ? email.substring(0, at) : email;
  }

  /// One or two letters for avatar bubbles.
  String get initials {
    final parts = displayName
        .split(RegExp(r'[\s._-]+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) {
      return '?';
    }
    if (parts.length == 1) {
      return parts.first.characters.take(2).toString().toUpperCase();
    }
    return (parts[0].characters.first + parts[1].characters.first)
        .toUpperCase();
  }
}

enum WorkspaceRole {
  owner('Owner'),
  admin('Admin'),
  member('Member'),
  viewer('Viewer');

  const WorkspaceRole(this.label);
  final String label;

  static WorkspaceRole fromName(String value) {
    return WorkspaceRole.values.firstWhere(
      (role) => role.name == value,
      orElse: () => WorkspaceRole.member,
    );
  }

  /// Viewers get read-only access; everyone else can edit content.
  bool get canEdit => this != WorkspaceRole.viewer;
  bool get canManageMembers =>
      this == WorkspaceRole.owner || this == WorkspaceRole.admin;
}

/// A team container. Every board, task and note belongs to exactly one.
class Workspace {
  const Workspace({
    required this.id,
    required this.name,
    required this.color,
    required this.ownerId,
    required this.role,
    this.memberCount = 1,
    this.joinCode = '',
  });

  factory Workspace.fromMap(Map<String, dynamic> map, {String? role}) {
    return Workspace(
      id: map['id'] as String,
      name: (map['name'] ?? '') as String,
      color: Color((map['color'] as num?)?.toInt() ?? 0xFF0F6BFF),
      ownerId: (map['owner_id'] ?? '') as String,
      role: WorkspaceRole.fromName(role ?? (map['role'] ?? 'member') as String),
      memberCount: (map['member_count'] as num?)?.toInt() ?? 1,
      joinCode: (map['join_code'] ?? '') as String,
    );
  }

  final String id;
  final String name;
  final Color color;
  final String ownerId;

  /// The signed-in user's role in this workspace.
  final WorkspaceRole role;
  final int memberCount;

  /// Short shareable code, e.g. PLNR-7K2M, for joining without an email invite.
  final String joinCode;
}

class WorkspaceMember {
  const WorkspaceMember({
    required this.profile,
    required this.role,
  });

  final UserProfile profile;
  final WorkspaceRole role;
}

class WorkspaceInvite {
  const WorkspaceInvite({
    required this.id,
    required this.email,
    required this.role,
    required this.createdAt,
    this.accepted = false,
  });

  factory WorkspaceInvite.fromMap(Map<String, dynamic> map) {
    return WorkspaceInvite(
      id: map['id'] as String,
      email: (map['email'] ?? '') as String,
      role: WorkspaceRole.fromName((map['role'] ?? 'member') as String),
      createdAt:
          DateTime.tryParse((map['created_at'] ?? '') as String) ??
          DateTime.now(),
      accepted: map['accepted_at'] != null,
    );
  }

  final String id;
  final String email;
  final WorkspaceRole role;
  final DateTime createdAt;
  final bool accepted;
}

/// An invitation waiting for the signed-in user to accept or decline.
class PendingInvite {
  const PendingInvite({
    required this.id,
    required this.workspaceId,
    required this.workspaceName,
    required this.workspaceColor,
    required this.role,
    required this.createdAt,
  });

  final String id;
  final String workspaceId;
  final String workspaceName;
  final Color workspaceColor;
  final WorkspaceRole role;
  final DateTime createdAt;
}

class Board {
  const Board({
    required this.id,
    required this.name,
    required this.color,
    required this.groups,
  });

  final String id;
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

  final String id;
  final String boardId;
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
    required this.progress,
    this.assigneeId,
    this.dueDate,
    this.startDate,
    this.endDate,
    this.noteCount = 0,
  });

  final String id;
  final String groupId;
  final String title;

  /// Free-text owner label, kept for tasks with no linked account.
  final String owner;

  /// Set when the task is assigned to a real workspace member.
  final String? assigneeId;
  final TaskStatus status;
  final TaskPriority priority;

  /// Real dates — sorting and overdue checks depend on these being typed.
  final DateTime? dueDate;
  final DateTime? startDate;
  final DateTime? endDate;
  final double progress;
  final int noteCount;

  bool get isOverdue {
    final due = dueDate;
    if (due == null || status == TaskStatus.done) {
      return false;
    }
    final today = DateTime.now();
    final midnight = DateTime(today.year, today.month, today.day);
    return due.isBefore(midnight);
  }

  bool get isDueToday {
    final due = dueDate;
    if (due == null) {
      return false;
    }
    final now = DateTime.now();
    return due.year == now.year && due.month == now.month && due.day == now.day;
  }

  factory PlannerTask.fromMap(Map<String, dynamic> map) {
    return PlannerTask(
      id: map['id'] as String,
      groupId: map['group_id'] as String,
      title: (map['title'] ?? '') as String,
      owner: (map['owner'] ?? '') as String,
      assigneeId: map['assignee_id'] as String?,
      status: TaskStatus.fromName((map['status'] ?? 'notStarted') as String),
      priority: TaskPriority.fromName((map['priority'] ?? 'medium') as String),
      dueDate: _parseDate(map['due_date']),
      startDate: _parseDate(map['start_date']),
      endDate: _parseDate(map['end_date']),
      progress: (map['progress'] as num?)?.toDouble() ?? 0,
      noteCount: (map['note_count'] as num?)?.toInt() ?? 0,
    );
  }
}

DateTime? _parseDate(Object? value) {
  if (value == null) {
    return null;
  }
  return DateTime.tryParse(value.toString());
}

/// A note on a task, visible to the whole workspace and attributed to whoever
/// wrote it.
class TaskNote {
  const TaskNote({
    required this.id,
    required this.taskId,
    required this.body,
    required this.color,
    required this.pinned,
    required this.createdAt,
    required this.updatedAt,
    this.author,
    this.editedBy,
    this.reactions = const {},
    this.myReactions = const {},
  });

  factory TaskNote.fromMap(
    Map<String, dynamic> map, {
    UserProfile? author,
    UserProfile? editedBy,
    Map<String, int> reactions = const {},
    Set<String> myReactions = const {},
  }) {
    return TaskNote(
      id: map['id'] as String,
      taskId: map['task_id'] as String,
      body: (map['body'] ?? '') as String,
      color: Color((map['color'] as num?)?.toInt() ?? 0xFFFFF3B0),
      pinned: (map['pinned'] ?? false) as bool,
      createdAt:
          DateTime.tryParse((map['created_at'] ?? '') as String) ??
          DateTime.now(),
      updatedAt:
          DateTime.tryParse((map['updated_at'] ?? '') as String) ??
          DateTime.now(),
      author: author,
      editedBy: editedBy,
      reactions: reactions,
      myReactions: myReactions,
    );
  }

  final String id;
  final String taskId;

  /// Quill Delta JSON.
  final String body;
  final Color color;
  final bool pinned;
  final DateTime createdAt;
  final DateTime updatedAt;
  final UserProfile? author;

  /// Set when someone other than the author last changed the note.
  final UserProfile? editedBy;

  /// Emoji → count across the whole team.
  final Map<String, int> reactions;

  /// Emoji the signed-in user has reacted with.
  final Set<String> myReactions;

  bool get wasEdited => updatedAt.difference(createdAt).inSeconds > 2;
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
