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

/// What a work note is for.
///
/// Mirrors the `task_note_kind` enum. Wire names are snake_case.
enum TaskNoteKind {
  /// Progress, written at any point.
  update('update', 'Update', Icons.sticky_note_2_outlined),

  /// "This is done, here is what I did."
  submission('submission', 'Submitted', Icons.outbox_rounded),

  /// Sent back: "this is not right yet, because…"
  rejection('rejection', 'Sent back', Icons.undo_rounded),

  /// Accepted by whoever was reviewing it.
  approval('approval', 'Approved', Icons.verified_rounded);

  const TaskNoteKind(this.wire, this.label, this.icon);

  final String wire;
  final String label;
  final IconData icon;

  static TaskNoteKind fromName(String value) {
    return TaskNoteKind.values.firstWhere(
      (kind) => kind.wire == value,
      orElse: () => TaskNoteKind.update,
    );
  }

  /// Approving and sending back are verdicts on someone else's work, so they
  /// are reserved for whoever manages the team. Writing an update or
  /// submitting your own work is not.
  bool get isVerdict =>
      this == TaskNoteKind.rejection || this == TaskNoteKind.approval;
}

/// One entry in a task's work log.
///
/// Distinct from a comment: a comment is conversation, this is the record of
/// what was done and the evidence for it. It carries the status the task moved
/// between, so the timeline reads as a history of the work rather than a list
/// of remarks.
class TaskNote {
  const TaskNote({
    required this.id,
    required this.taskId,
    required this.kind,
    required this.body,
    required this.createdAt,
    this.author,
    this.statusFrom,
    this.statusTo,
    this.editedAt,
  });

  factory TaskNote.fromMap(
    Map<String, dynamic> map, {
    UserProfile? author,
  }) {
    return TaskNote(
      id: map['id'] as String,
      taskId: (map['task_id'] ?? '') as String,
      kind: TaskNoteKind.fromName((map['kind'] ?? 'update') as String),
      body: (map['body'] ?? '') as String,
      author: author,
      statusFrom: map['status_from'] as String?,
      statusTo: map['status_to'] as String?,
      editedAt: _parseDate(map['edited_at']),
      createdAt: _parseDate(map['created_at']) ?? DateTime.now(),
    );
  }

  final String id;
  final String taskId;
  final TaskNoteKind kind;
  final String body;
  final UserProfile? author;

  /// The status names at the time, not ids: a label can be renamed or deleted
  /// later, and the note has to keep saying what actually happened.
  final String? statusFrom;
  final String? statusTo;

  final DateTime? editedAt;
  final DateTime createdAt;

  bool get wasEdited => editedAt != null;

  /// Whether this note records a status move worth showing beside it.
  bool get movedStatus =>
      statusTo != null && statusTo!.isNotEmpty && statusFrom != statusTo;
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

/// Whether the display name can be changed, and when it can be if not.
///
/// A name is how teammates recognise each other across every board and comment
/// in the workspace, so changes are rate limited to one a week. The database
/// decides — see migration 0012 — and this is what it reports back.
class NameChangeStatus {
  const NameChangeStatus({
    required this.canChangeNow,
    required this.nextAllowedAt,
  });

  factory NameChangeStatus.fromMap(Map<String, dynamic> map) {
    final next = DateTime.tryParse((map['next_allowed_at'] ?? '') as String);
    return NameChangeStatus(
      canChangeNow: (map['can_change_now'] as bool?) ?? true,
      nextAllowedAt: next?.toLocal(),
    );
  }

  final bool canChangeNow;

  /// Null when the name has never been changed, so nothing is being waited on.
  final DateTime? nextAllowedAt;

  /// Whole days left, rounded up — "in 3 days" reads better than a timestamp,
  /// and rounding up avoids promising a change that is still hours away.
  int get daysRemaining {
    final until = nextAllowedAt;
    if (canChangeNow || until == null) {
      return 0;
    }
    final left = until.difference(DateTime.now());
    if (left.isNegative) {
      return 0;
    }
    return left.inHours ~/ 24 + (left.inHours % 24 == 0 ? 0 : 1);
  }
}

class WorkspaceMember {
  const WorkspaceMember({required this.profile, required this.role});

  final UserProfile profile;
  final WorkspaceRole role;
}

class WorkspaceInvite {
  const WorkspaceInvite({
    required this.id,
    required this.email,
    required this.role,
    required this.createdAt,
    this.invitee,
    this.accepted = false,
  });

  factory WorkspaceInvite.fromMap(
    Map<String, dynamic> map, {
    UserProfile? invitee,
  }) {
    return WorkspaceInvite(
      id: map['id'] as String,
      email: (map['email'] ?? '') as String,
      role: WorkspaceRole.fromName((map['role'] ?? 'member') as String),
      createdAt:
          DateTime.tryParse((map['created_at'] ?? '') as String) ??
          DateTime.now(),
      invitee: invitee,
      accepted: map['accepted_at'] != null,
    );
  }

  final String id;
  final String email;
  final WorkspaceRole role;
  final DateTime createdAt;

  /// The invited person's profile, when they already have an account. Null for
  /// someone invited by email who has not signed up yet — the one case where
  /// the address is all there is to show.
  final UserProfile? invitee;

  final bool accepted;

  /// Their name if we know it, otherwise the address they were invited at.
  String get displayName => invitee?.displayName ?? email;

  /// True when this invitation is waiting on someone who has not registered.
  bool get isPendingSignup => invitee == null;
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
    this.invitedBy,
    this.memberCount = 0,
  });

  final String id;
  final String workspaceId;
  final String workspaceName;
  final Color workspaceColor;
  final WorkspaceRole role;
  final DateTime createdAt;

  /// Who sent it. Null if that account has since been deleted — the invitation
  /// survives them, so this cannot be required.
  final UserProfile? invitedBy;

  /// How many people are already in the workspace. Zero when unknown.
  final int memberCount;

  /// "Maria invited you" — the first thing worth knowing about an invitation.
  String get inviterLine {
    final who = invitedBy?.displayName;
    return who == null ? 'You have been invited' : '$who invited you';
  }

  /// "4 members · 2d ago", omitting either half when it is not known.
  String get contextLine {
    final parts = <String>[
      if (memberCount > 0)
        '$memberCount ${memberCount == 1 ? 'member' : 'members'}',
      _age,
    ];
    return parts.join(' · ');
  }

  String get _age {
    final elapsed = DateTime.now().difference(createdAt);
    if (elapsed.inMinutes < 1) {
      return 'just now';
    }
    if (elapsed.inHours < 1) {
      return '${elapsed.inMinutes}m ago';
    }
    if (elapsed.inDays < 1) {
      return '${elapsed.inHours}h ago';
    }
    if (elapsed.inDays < 7) {
      return '${elapsed.inDays}d ago';
    }
    return '${(elapsed.inDays / 7).floor()}w ago';
  }

  /// What the role actually lets you do, in the words the roles table uses.
  String get roleSummary => switch (role) {
    WorkspaceRole.owner => 'Full control of the workspace',
    WorkspaceRole.admin => 'Can edit work and manage people',
    WorkspaceRole.member => 'Can create and edit boards and tasks',
    WorkspaceRole.viewer => 'Read-only — can see work but not change it',
  };
}

/// Progress that agrees with a status, given what it was before.
///
/// Status and progress describe the same thing twice, so they have to move
/// together or the board contradicts itself — "Working" on a full bar, or
/// "Done" on an empty one.
///
/// The rule:
///   * a done status fills the bar
///   * a not-started status empties it
///   * anything in between keeps the current value, *unless* that value sits
///     at an end which the new status contradicts — 100% is not "Working" and
///     0% is not "Working" either, so both fall back to a neutral midpoint
///
/// Only the contradiction is corrected. A task at 40% moved to "Stuck" stays
/// at 40%, because nothing about being stuck says how far along it is.
double progressForStatus(StatusLabel status, double current) {
  if (status.isDone) {
    return 1;
  }
  if (status.isDefault) {
    return 0;
  }
  // An in-between status cannot be complete, and cannot be untouched either.
  // 0.5 rather than nudging off the end by a hair: an invented number should
  // at least look invented, not like a real measurement.
  if (current >= 1 || current <= 0) {
    return 0.5;
  }
  return current;
}

/// A status a board defines for its tasks.
///
/// Boards name their own, so "Working on it" can become "In progress" without
/// touching a single task — the task holds the id, not the word.
class StatusLabel {
  const StatusLabel({
    required this.id,
    required this.name,
    required this.color,
    required this.position,
    this.isDone = false,
    this.isDefault = false,
  });

  factory StatusLabel.fromMap(Map<String, dynamic> map) {
    return StatusLabel(
      id: map['id'] as String,
      name: (map['name'] ?? '') as String,
      color: Color((map['color'] as num?)?.toInt() ?? 0xFF9AA4B2),
      position: (map['position'] as num?)?.toDouble() ?? 0,
      isDone: (map['is_done'] ?? false) as bool,
      isDefault: (map['is_default'] ?? false) as bool,
    );
  }

  final String id;
  final String name;
  final Color color;
  final double position;

  /// Which labels count as complete. Progress rollups test this rather than
  /// comparing against the word "Done".
  final bool isDone;
  final bool isDefault;
}

class Board {
  const Board({
    required this.id,
    required this.name,
    required this.color,
    required this.groups,
    this.statuses = const [],
    this.pinned = false,
  });

  factory Board.fromMap(Map<String, dynamic> map) {
    final statusMaps = (map['statuses'] as List?) ?? const [];
    final statuses = statusMaps
        .whereType<Map<String, dynamic>>()
        .map(StatusLabel.fromMap)
        .toList();

    final groupMaps = (map['groups'] as List?) ?? const [];
    final groups = groupMaps
        .whereType<Map<String, dynamic>>()
        .map(TaskGroup.fromMap)
        .toList();

    return Board(
      id: map['id'] as String,
      name: (map['name'] ?? '') as String,
      color: Color((map['color'] as num?)?.toInt() ?? 0xFF0F6BFF),
      pinned: (map['pinned'] ?? false) as bool,
      statuses: statuses,
      groups: groups,
    );
  }

  final String id;
  final String name;
  final Color color;
  final List<TaskGroup> groups;

  /// Pinned boards sort above the rest in the sidebar. Per workspace, so the
  /// whole team sees the same board at the top.
  final bool pinned;

  /// The statuses this board defines, in display order.
  final List<StatusLabel> statuses;

  /// A task on this board by id, or null once it has been moved or deleted.
  ///
  /// Used where a task has to be re-read after a write: the row a callback was
  /// handed is a snapshot, and acting on it twice would act on stale values.
  PlannerTask? taskById(String id) {
    for (final group in groups) {
      for (final task in group.tasks) {
        if (task.id == id) {
          return task;
        }
      }
    }
    return null;
  }

  StatusLabel? statusById(String? id) {
    if (id == null) {
      return null;
    }
    for (final status in statuses) {
      if (status.id == id) {
        return status;
      }
    }
    return null;
  }

  StatusLabel? get defaultStatus {
    for (final status in statuses) {
      if (status.isDefault) {
        return status;
      }
    }
    return statuses.isEmpty ? null : statuses.first;
  }

  int get taskCount => groups.fold(0, (sum, group) => sum + group.tasks.length);

  int get doneCount => groups.fold(0, (sum, group) {
    return sum + group.tasks.where((task) => isDone(task)).length;
  });

  /// Completion is a property of the board's labels, not of the task.
  bool isDone(PlannerTask task) => statusById(task.statusId)?.isDone ?? false;
}

class TaskGroup {
  const TaskGroup({
    required this.id,
    required this.boardId,
    required this.name,
    required this.color,
    required this.tasks,
    this.collapsed = false,
  });

  factory TaskGroup.fromMap(Map<String, dynamic> map) {
    final taskMaps = (map['tasks'] as List?) ?? const [];
    return TaskGroup(
      id: map['id'] as String,
      boardId: (map['board_id'] ?? '') as String,
      name: (map['name'] ?? '') as String,
      color: Color((map['color'] as num?)?.toInt() ?? 0xFF0F6BFF),
      collapsed: (map['collapsed'] ?? false) as bool,
      tasks: taskMaps
          .whereType<Map<String, dynamic>>()
          .map(PlannerTask.fromMap)
          .toList(),
    );
  }

  final String id;
  final String boardId;
  final String name;
  final Color color;
  final List<PlannerTask> tasks;
  final bool collapsed;
}

class PlannerTask {
  const PlannerTask({
    required this.id,
    required this.groupId,
    required this.boardId,
    required this.title,
    required this.priority,
    required this.progress,
    required this.position,
    this.progressAt,
    this.statusId,
    this.assigneeIds = const [],
    this.dueDate,
    this.startDate,
    this.endDate,
    this.commentCount = 0,
    this.noteCount = 0,
    this.statusBy,
    this.statusAt,
  });

  factory PlannerTask.fromMap(Map<String, dynamic> map) {
    final assignees = (map['assignee_ids'] as List?) ?? const [];
    return PlannerTask(
      id: map['id'] as String,
      groupId: map['group_id'] as String,
      boardId: (map['board_id'] ?? '') as String,
      title: (map['title'] ?? '') as String,
      statusId: map['status_id'] as String?,
      priority: TaskPriority.fromName((map['priority'] ?? 'medium') as String),
      dueDate: _parseDate(map['due_date']),
      startDate: _parseDate(map['start_date']),
      endDate: _parseDate(map['end_date']),
      progress: (map['progress'] as num?)?.toDouble() ?? 0,
      position: (map['position'] as num?)?.toDouble() ?? 0,
      progressAt: _parseDate(map['progress_at']),
      commentCount: (map['comment_count'] as num?)?.toInt() ?? 0,
      noteCount: (map['note_count'] as num?)?.toInt() ?? 0,
      statusBy: map['status_by'] is Map<String, dynamic>
          ? UserProfile.fromMap(map['status_by'] as Map<String, dynamic>)
          : null,
      statusAt: _parseDate(map['status_at']),
      assigneeIds: assignees.whereType<String>().toList(),
    );
  }

  final String id;
  final String groupId;
  final String boardId;
  final String title;

  /// Points at one of the board's [StatusLabel]s. Null only if the label was
  /// deleted out from under the task.
  final String? statusId;

  /// Everyone assigned. A task can have several, or none.
  final List<String> assigneeIds;
  final TaskPriority priority;

  /// Real dates — sorting and overdue checks depend on these being typed.
  final DateTime? dueDate;
  final DateTime? startDate;
  final DateTime? endDate;
  final double progress;

  /// Fractional, so a task moves between two neighbours without renumbering
  /// the rest of the group.
  final double position;

  /// When the progress bar last moved — not the same as when the task was last
  /// edited. Renaming it or changing a date does not count, which is what lets
  /// the stale sweep tell a stalled task from a busy one.
  final DateTime? progressAt;
  final int commentCount;
  final int noteCount;

  /// Who last moved this task's status, and when.
  ///
  /// A task can have several assignees, so the avatars on the row say who is
  /// responsible — not who actually marked it done. This answers that, and it
  /// is the question every review conversation starts with.
  ///
  /// Null when a trigger or a scheduled sweep moved it rather than a person.
  final UserProfile? statusBy;
  final DateTime? statusAt;

  /// Overdue needs to know whether the task is finished, which is the board's
  /// business — hence the parameter rather than a bare getter.
  bool isOverdue({bool done = false}) {
    final due = dueDate;
    if (due == null || done) {
      return false;
    }
    final today = DateTime.now();
    return due.isBefore(DateTime(today.year, today.month, today.day));
  }

  bool get isDueToday {
    final due = dueDate;
    if (due == null) {
      return false;
    }
    final now = DateTime.now();
    return due.year == now.year && due.month == now.month && due.day == now.day;
  }
}

DateTime? _parseDate(Object? value) {
  if (value == null) {
    return null;
  }
  return DateTime.tryParse(value.toString());
}

/// A message in a task's chat.
///
/// Replaces the sticky-note model: teams were writing messages to each other on
/// the notes anyway, so this is the shape the use already had.
class TaskComment {
  const TaskComment({
    required this.id,
    required this.taskId,
    required this.body,
    required this.createdAt,
    this.parentId,
    this.author,
    this.editedAt,
    this.reactions = const {},
    this.myReactions = const {},
    this.reactionUsers = const {},
    this.mentionedIds = const [],
    this.replies = const [],
  });

  factory TaskComment.fromMap(
    Map<String, dynamic> map, {
    UserProfile? author,
    Map<String, int> reactions = const {},
    Set<String> myReactions = const {},
    Map<String, List<String>> reactionUsers = const {},
    List<String> mentionedIds = const [],
    List<TaskComment> replies = const [],
  }) {
    return TaskComment(
      id: map['id'] as String,
      taskId: map['task_id'] as String,
      parentId: map['parent_id'] as String?,
      body: (map['body'] ?? '') as String,
      createdAt:
          DateTime.tryParse((map['created_at'] ?? '') as String) ??
          DateTime.now(),
      editedAt: DateTime.tryParse((map['edited_at'] ?? '') as String? ?? ''),
      author: author,
      reactions: reactions,
      myReactions: myReactions,
      reactionUsers: reactionUsers,
      mentionedIds: mentionedIds,
      replies: replies,
    );
  }

  final String id;
  final String taskId;

  /// Set on a reply. Threads stay one level deep — a reply to a reply attaches
  /// to the same parent, so the conversation cannot march off the right edge.
  final String? parentId;
  final String body;
  final DateTime createdAt;
  final UserProfile? author;

  /// Set only when the text was actually changed. Null means untouched, which
  /// comparing timestamps could not distinguish from an edit a second after
  /// posting.
  final DateTime? editedAt;

  /// Emoji → how many people used it.
  final Map<String, int> reactions;

  /// Emoji the signed-in user picked, so their own are highlighted.
  final Set<String> myReactions;

  /// Emoji → who used it, so a chip can name its people on hover.
  final Map<String, List<String>> reactionUsers;

  /// Who was named with @. Stored rather than re-parsed, so an edit that drops
  /// the name does not un-notify someone already pinged.
  final List<String> mentionedIds;

  /// Replies to this message, oldest first. Empty on a reply itself.
  final List<TaskComment> replies;

  bool get isReply => parentId != null;
  bool get wasEdited => editedAt != null;
  bool get hasReplies => replies.isNotEmpty;

  /// "just now", "5m", "3h", "2d" — compact enough to sit beside a name.
  String get age {
    final elapsed = DateTime.now().difference(createdAt);
    if (elapsed.inMinutes < 1) {
      return 'just now';
    }
    if (elapsed.inHours < 1) {
      return '${elapsed.inMinutes}m';
    }
    if (elapsed.inDays < 1) {
      return '${elapsed.inHours}h';
    }
    if (elapsed.inDays < 7) {
      return '${elapsed.inDays}d';
    }
    return '${(elapsed.inDays / 7).floor()}w';
  }

  TaskComment copyWith({
    List<TaskComment>? replies,
    Map<String, int>? reactions,
    Set<String>? myReactions,
    Map<String, List<String>>? reactionUsers,
  }) {
    return TaskComment(
      id: id,
      taskId: taskId,
      body: body,
      createdAt: createdAt,
      parentId: parentId,
      author: author,
      editedAt: editedAt,
      reactions: reactions ?? this.reactions,
      myReactions: myReactions ?? this.myReactions,
      reactionUsers: reactionUsers ?? this.reactionUsers,
      mentionedIds: mentionedIds,
      replies: replies ?? this.replies,
    );
  }
}

/// One entry in a task's history.
class TaskActivity {
  const TaskActivity({
    required this.id,
    required this.kind,
    required this.detail,
    required this.createdAt,
    this.actor,
  });

  factory TaskActivity.fromMap(Map<String, dynamic> map, {UserProfile? actor}) {
    return TaskActivity(
      id: map['id'] as String,
      kind: ActivityKind.fromName((map['kind'] ?? '') as String),
      detail: (map['detail'] as Map<String, dynamic>?) ?? const {},
      createdAt:
          DateTime.tryParse((map['created_at'] ?? '') as String) ??
          DateTime.now(),
      actor: actor,
    );
  }

  final String id;
  final ActivityKind kind;

  /// Structured rather than a sentence, so the wording lives here in the
  /// client: `{"from": "Working", "to": "Done"}`.
  final Map<String, dynamic> detail;
  final DateTime createdAt;
  final UserProfile? actor;

  String get summary {
    final who = actor?.displayName ?? 'Someone';
    final from = detail['from'];
    final to = detail['to'];
    return switch (kind) {
      ActivityKind.created => '$who created this task',
      ActivityKind.renamed => '$who renamed it to "$to"',
      ActivityKind.statusChanged => '$who moved it from $from to $to',
      ActivityKind.priorityChanged => '$who set priority to $to',
      ActivityKind.assigned => '$who assigned $to',
      ActivityKind.unassigned => '$who unassigned $to',
      ActivityKind.dueDateChanged => '$who set the due date to $to',
      ActivityKind.moved => '$who moved it to $to',
      ActivityKind.progressChanged => '$who set progress to $to',
      ActivityKind.noteAdded => '$who added a note',
      ActivityKind.commentAdded => '$who commented',
      ActivityKind.deleted => '$who deleted this task',
      ActivityKind.restored => '$who restored this task',
    };
  }
}

/// Mirrors the `activity_kind` enum. Wire names are snake_case.
enum ActivityKind {
  created('created'),
  renamed('renamed'),
  statusChanged('status_changed'),
  priorityChanged('priority_changed'),
  assigned('assigned'),
  unassigned('unassigned'),
  dueDateChanged('due_date_changed'),
  moved('moved'),
  progressChanged('progress_changed'),
  noteAdded('note_added'),
  commentAdded('comment_added'),
  deleted('deleted'),
  restored('restored');

  const ActivityKind(this.wire);

  /// The Postgres enum value, which differs from the Dart name.
  final String wire;

  static ActivityKind fromName(String value) {
    return ActivityKind.values.firstWhere(
      (kind) => kind.wire == value,
      orElse: () => ActivityKind.created,
    );
  }
}

/// Something the signed-in user needs to know about.
///
/// One row per person: a task assigned to three people makes three
/// notifications, because each is read and dismissed independently.
class AppNotification {
  const AppNotification({
    required this.id,
    required this.kind,
    required this.title,
    required this.createdAt,
    this.body = '',
    this.workspaceId,
    this.taskId,
    this.boardId,
    this.inviteId,
    this.actor,
    this.readAt,
  });

  /// The same notification, marked read.
  ///
  /// Lets "mark all read" repaint the list at once instead of waiting for the
  /// realtime echo, which leaves the rows looking untouched for a beat.
  AppNotification markedRead() {
    return AppNotification(
      id: id,
      kind: kind,
      title: title,
      createdAt: createdAt,
      body: body,
      workspaceId: workspaceId,
      taskId: taskId,
      boardId: boardId,
      inviteId: inviteId,
      actor: actor,
      readAt: readAt ?? DateTime.now(),
    );
  }

  factory AppNotification.fromMap(
    Map<String, dynamic> map, {
    UserProfile? actor,
  }) {
    return AppNotification(
      id: map['id'] as String,
      kind: NotificationKind.fromName((map['kind'] ?? '') as String),
      title: (map['title'] ?? '') as String,
      body: (map['body'] ?? '') as String,
      workspaceId: map['workspace_id'] as String?,
      taskId: map['task_id'] as String?,
      boardId: map['board_id'] as String?,
      inviteId: map['invite_id'] as String?,
      actor: actor,
      readAt: DateTime.tryParse((map['read_at'] ?? '') as String? ?? ''),
      createdAt:
          DateTime.tryParse((map['created_at'] ?? '') as String) ??
          DateTime.now(),
    );
  }

  final String id;
  final NotificationKind kind;
  final String title;
  final String body;

  /// Where it points, so tapping it can open the right screen. All null for a
  /// notification that has no destination.
  final String? workspaceId;
  final String? taskId;
  final String? boardId;
  final String? inviteId;

  /// Who caused it. Null when the system raised it on its own, such as a due
  /// date passing.
  final UserProfile? actor;

  final DateTime? readAt;
  final DateTime createdAt;

  bool get isUnread => readAt == null;

  /// True when acting on this means answering an invitation rather than just
  /// navigating somewhere.
  bool get isActionable => kind == NotificationKind.workspaceInvite;

  /// "just now", "5m", "3h", "2d" — compact enough for a notification list.
  String get age {
    final elapsed = DateTime.now().difference(createdAt);
    if (elapsed.inMinutes < 1) {
      return 'just now';
    }
    if (elapsed.inHours < 1) {
      return '${elapsed.inMinutes}m';
    }
    if (elapsed.inDays < 1) {
      return '${elapsed.inHours}h';
    }
    if (elapsed.inDays < 7) {
      return '${elapsed.inDays}d';
    }
    return '${(elapsed.inDays / 7).floor()}w';
  }
}

/// Mirrors the `notification_kind` enum. Wire names are snake_case.
enum NotificationKind {
  workspaceInvite('workspace_invite', Icons.mail_outline),
  inviteAccepted('invite_accepted', Icons.how_to_reg_outlined),
  memberJoined('member_joined', Icons.person_add_alt),
  roleChanged('role_changed', Icons.badge_outlined),
  removedFromWorkspace('removed_from_workspace', Icons.person_remove_outlined),
  taskAssigned('task_assigned', Icons.assignment_ind_outlined),
  taskUnassigned('task_unassigned', Icons.assignment_late_outlined),
  taskDueSoon('task_due_soon', Icons.schedule),
  taskOverdue('task_overdue', Icons.warning_amber_rounded),
  taskStatusChanged('task_status_changed', Icons.swap_horiz),
  noteAdded('note_added', Icons.sticky_note_2_outlined),
  commentAdded('comment_added', Icons.chat_bubble_outline),
  mentioned('mentioned', Icons.alternate_email);

  const NotificationKind(this.wire, this.icon);

  /// The Postgres enum value, which differs from the Dart name.
  final String wire;
  final IconData icon;

  static NotificationKind fromName(String value) {
    return NotificationKind.values.firstWhere(
      (kind) => kind.wire == value,
      orElse: () => NotificationKind.memberJoined,
    );
  }

  /// Overdue and invitations want to stand out from routine chatter.
  bool get isUrgent =>
      this == NotificationKind.taskOverdue ||
      this == NotificationKind.workspaceInvite;
}

enum TaskPriority {
  urgent('Urgent'),
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

/// A custom column a board defines beyond the built-ins.
class BoardColumn {
  const BoardColumn({
    required this.id,
    required this.boardId,
    required this.name,
    required this.kind,
    required this.position,
    this.settings = const {},
    this.width = 160,
  });

  factory BoardColumn.fromMap(Map<String, dynamic> map) {
    return BoardColumn(
      id: map['id'] as String,
      boardId: (map['board_id'] ?? '') as String,
      name: (map['name'] ?? '') as String,
      kind: ColumnKind.fromName((map['kind'] ?? 'text') as String),
      settings: (map['settings'] as Map<String, dynamic>?) ?? const {},
      position: (map['position'] as num?)?.toDouble() ?? 0,
      width: (map['width'] as num?)?.toInt() ?? 160,
    );
  }

  final String id;
  final String boardId;
  final String name;
  final ColumnKind kind;

  /// Per-kind config: dropdown choices, number format, formula body.
  final Map<String, dynamic> settings;
  final double position;
  final int width;
}

/// Mirrors the `column_kind` enum.
enum ColumnKind {
  text('Text', 'text'),
  longText('Long text', 'long_text'),
  number('Number', 'number'),
  status('Status', 'status'),
  people('People', 'people'),
  date('Date', 'date'),
  timeline('Timeline', 'timeline'),
  checkbox('Checkbox', 'checkbox'),
  rating('Rating', 'rating'),
  dropdown('Dropdown', 'dropdown'),
  link('Link', 'link'),
  email('Email', 'email'),
  phone('Phone', 'phone'),
  formula('Formula', 'formula');

  const ColumnKind(this.label, this.wire);
  final String label;
  final String wire;

  static ColumnKind fromName(String value) {
    return ColumnKind.values.firstWhere(
      (kind) => kind.wire == value,
      orElse: () => ColumnKind.text,
    );
  }
}

/// A saved view: a board presented one way, with its own filters and sort.
class BoardView {
  const BoardView({
    required this.id,
    required this.boardId,
    required this.name,
    required this.kind,
    required this.position,
    this.config = const {},
    this.isShared = true,
    this.createdBy,
  });

  factory BoardView.fromMap(Map<String, dynamic> map) {
    return BoardView(
      id: map['id'] as String,
      boardId: (map['board_id'] ?? '') as String,
      name: (map['name'] ?? '') as String,
      kind: ViewMode.fromName((map['kind'] ?? 'table') as String),
      config: (map['config'] as Map<String, dynamic>?) ?? const {},
      position: (map['position'] as num?)?.toDouble() ?? 0,
      isShared: (map['is_shared'] ?? true) as bool,
      createdBy: map['created_by'] as String?,
    );
  }

  final String id;
  final String boardId;
  final String name;
  final ViewMode kind;

  /// Filters, sort and grouping, opaque to the database.
  final Map<String, dynamic> config;
  final double position;

  /// Personal views are visible only to their creator.
  final bool isShared;
  final String? createdBy;
}

/// Mirrors the `view_kind` enum. Only the first three are implemented in the
/// UI; the rest are accepted by the database so a view can be saved before its
/// renderer exists.
enum ViewMode {
  table('Table'),
  kanban('Kanban'),
  calendar('Calendar'),
  timeline('Timeline'),
  gantt('Gantt'),
  chart('Chart');

  const ViewMode(this.label);
  final String label;

  static ViewMode fromName(String value) {
    return ViewMode.values.firstWhere(
      (mode) => mode.name == value,
      orElse: () => ViewMode.table,
    );
  }
}

enum TaskOrder {
  manual('Manual'),
  title('Title'),
  dueDate('Due date'),
  priority('Priority'),
  status('Status');

  const TaskOrder(this.label);
  final String label;
}
