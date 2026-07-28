import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/planner_models.dart';

/// All reads and writes for the planner. Row level security decides what the
/// signed-in user can see, so queries here never filter by user id themselves.
class PlannerRepository {
  PlannerRepository(this._client);

  final SupabaseClient _client;

  String? get _uid => _client.auth.currentUser?.id;

  // === Workspaces ===

  /// Workspaces the user belongs to, each carrying their role.
  Future<List<Workspace>> loadWorkspaces() async {
    final rows = await _client
        .from('workspace_members')
        .select('role, workspaces(id, name, color, owner_id, join_code)')
        .order('created_at');

    final workspaces = <Workspace>[];
    for (final row in rows) {
      final data = row['workspaces'];
      if (data is Map<String, dynamic>) {
        workspaces.add(
          Workspace.fromMap(data, role: row['role'] as String?),
        );
      }
    }
    return workspaces;
  }

  Future<Workspace> createWorkspace({
    required String name,
    required Color color,
  }) async {
    final userId = _uid;
    if (userId == null) {
      throw StateError('Not signed in.');
    }
    // Insert without chaining .select(). PostgREST applies the SELECT policy to
    // a returning clause, and `workspaces_select` requires membership — which
    // the enrolment trigger has not committed at the point the read-back is
    // evaluated. Chaining them made creating a workspace fail with a permission
    // error and roll the row back, so a new account ended up with no workspace
    // at all.
    await _client.from('workspaces').insert({
      'name': name.trim(),
      'color': color.toARGB32(),
      'owner_id': userId,
    });

    // Read it back in a separate request, by which point the trigger has run
    // and the membership row exists.
    final row = await _client
        .from('workspaces')
        .select('id, name, color, owner_id, join_code')
        .eq('owner_id', userId)
        .order('created_at', ascending: false)
        .limit(1)
        .single();

    return Workspace.fromMap(row, role: 'owner');
  }

  Future<void> renameWorkspace({
    required String workspaceId,
    required String name,
    required Color color,
  }) async {
    await _client
        .from('workspaces')
        .update({'name': name.trim(), 'color': color.toARGB32()})
        .eq('id', workspaceId);
  }

  Future<void> deleteWorkspace(String workspaceId) async {
    final deleted = await _client
        .from('workspaces')
        .delete()
        .eq('id', workspaceId)
        .select('id');

    if (deleted.isEmpty) {
      throw StateError(
        'The workspace was not deleted. Only its owner can remove it.',
      );
    }
  }

  /// Redeems a join code. Returns the workspace name on success, or throws with
  /// a message worth showing the user.
  Future<String> joinWorkspaceWithCode(String code) async {
    final result = await _client.rpc<dynamic>(
      'join_workspace_with_code',
      params: {'code': code},
    );

    final map = result is Map<String, dynamic>
        ? result
        : <String, dynamic>{'ok': false, 'error': 'unexpected'};

    if (map['ok'] == true) {
      return (map['name'] ?? 'the workspace') as String;
    }

    throw switch (map['error']) {
      'not_found' =>
        'No workspace matches that code. Check it and try again.',
      'already_member' =>
        'You are already a member of ${map['name'] ?? 'that workspace'}.',
      'not_signed_in' => 'You need to be signed in to join a workspace.',
      _ => 'Could not join that workspace.',
    };
  }

  Future<String> regenerateJoinCode(String workspaceId) async {
    final result = await _client.rpc<dynamic>(
      'regenerate_join_code',
      params: {'target_workspace': workspaceId},
    );
    return result.toString();
  }

  /// The signed-in user's own profile row.
  ///
  /// Read from  rather than the auth metadata: the profile is what
  /// teammates see, and it is the row the user can actually edit later.
  Future<UserProfile?> loadMyProfile() async {
    final userId = _uid;
    if (userId == null) {
      return null;
    }
    try {
      final row = await _client
          .from('profiles')
          .select('id, email, full_name, avatar_url')
          .eq('id', userId)
          .maybeSingle();
      return row == null ? null : UserProfile.fromMap(row);
    } catch (_) {
      return null;
    }
  }

  // === Members and invites ===

  Future<List<WorkspaceMember>> loadMembers(String workspaceId) async {
    final rows = await _client
        .from('workspace_members')
        .select('role, profiles(id, email, full_name, avatar_url)')
        .eq('workspace_id', workspaceId);

    final members = <WorkspaceMember>[];
    for (final row in rows) {
      final profile = row['profiles'];
      if (profile is Map<String, dynamic>) {
        members.add(
          WorkspaceMember(
            profile: UserProfile.fromMap(profile),
            role: WorkspaceRole.fromName((row['role'] ?? 'member') as String),
          ),
        );
      }
    }
    members.sort((a, b) {
      final byRole = a.role.index.compareTo(b.role.index);
      if (byRole != 0) {
        return byRole;
      }
      return a.profile.displayName.toLowerCase().compareTo(
        b.profile.displayName.toLowerCase(),
      );
    });
    return members;
  }

  Future<List<WorkspaceInvite>> loadInvites(String workspaceId) async {
    final rows = await _client
        .from('workspace_invites')
        .select('id, email, role, accepted_at, created_at')
        .eq('workspace_id', workspaceId)
        .isFilter('accepted_at', null)
        .isFilter('declined_at', null)
        .order('created_at');
    return rows.map(WorkspaceInvite.fromMap).toList();
  }

  /// Invitations addressed to the signed-in user's email that they have not
  /// acted on yet. The RLS policy already limits this to their own address.
  Future<List<PendingInvite>> loadMyInvites() async {
    final email = _client.auth.currentUser?.email;
    if (email == null) {
      return [];
    }

    final rows = await _client
        .from('workspace_invites')
        .select('id, role, created_at, workspaces(id, name, color)')
        .isFilter('accepted_at', null)
        .isFilter('declined_at', null)
        .ilike('email', email);

    final invites = <PendingInvite>[];
    for (final row in rows) {
      final workspace = row['workspaces'];
      if (workspace is Map<String, dynamic>) {
        invites.add(
          PendingInvite(
            id: row['id'] as String,
            workspaceId: workspace['id'] as String,
            workspaceName: (workspace['name'] ?? '') as String,
            workspaceColor: Color(
              (workspace['color'] as num?)?.toInt() ?? 0xFF4C5BD4,
            ),
            role: WorkspaceRole.fromName((row['role'] ?? 'member') as String),
            createdAt:
                DateTime.tryParse((row['created_at'] ?? '') as String) ??
                DateTime.now(),
          ),
        );
      }
    }
    return invites;
  }

  /// Accepts every pending invitation for this user and returns how many.
  Future<int> acceptInvites() async {
    final result = await _client.rpc<dynamic>('accept_pending_invites');
    if (result is int) {
      return result;
    }
    return int.tryParse('$result') ?? 0;
  }

  /// Declines an invitation.
  ///
  /// Marks it rather than deleting it: the delete policy requires workspace
  /// membership, which the invited person does not have. The update policy does
  /// allow them to act on a row addressed to their own email, so a timestamp is
  /// the only route available — and it leaves the inviter able to see that it
  /// was turned down rather than the row silently vanishing.
  Future<void> declineInvite(String inviteId) async {
    await _client
        .from('workspace_invites')
        .update({'declined_at': DateTime.now().toIso8601String()})
        .eq('id', inviteId);
  }

  /// Records an invitation. The person becomes a member the next time they sign
  /// in with that email, via `accept_pending_invites()`.
  Future<void> inviteMember({
    required String workspaceId,
    required String email,
    required WorkspaceRole role,
  }) async {
    final userId = _uid;
    if (userId == null) {
      throw StateError('Not signed in.');
    }
    await _client.from('workspace_invites').upsert({
      'workspace_id': workspaceId,
      'email': email.trim().toLowerCase(),
      'role': role.name,
      'invited_by': userId,
    }, onConflict: 'workspace_id,email');
  }

  Future<void> revokeInvite(String inviteId) async {
    await _client.from('workspace_invites').delete().eq('id', inviteId);
  }

  Future<void> removeMember({
    required String workspaceId,
    required String userId,
  }) async {
    await _client
        .from('workspace_members')
        .delete()
        .eq('workspace_id', workspaceId)
        .eq('user_id', userId);
  }

  Future<void> changeMemberRole({
    required String workspaceId,
    required String userId,
    required WorkspaceRole role,
  }) async {
    await _client
        .from('workspace_members')
        .update({'role': role.name})
        .eq('workspace_id', workspaceId)
        .eq('user_id', userId);
  }

  // === Boards ===

  /// Loads every board in a workspace with its groups and tasks, in three
  /// queries rather than one per level.
  Future<List<Board>> loadBoards(String workspaceId) async {
    final boardRows = await _client
        .from('boards')
        .select('id, name, color, position')
        .eq('workspace_id', workspaceId)
        .order('position');

    if (boardRows.isEmpty) {
      return [];
    }

    final boardIds = boardRows.map((row) => row['id'] as String).toList();
    final groupRows = await _client
        .from('task_groups')
        .select('id, board_id, name, color, position')
        .inFilter('board_id', boardIds)
        .order('position');

    final groupIds = groupRows.map((row) => row['id'] as String).toList();
    final taskRows = groupIds.isEmpty
        ? <Map<String, dynamic>>[]
        : await _client
              .from('tasks')
              .select(
                'id, group_id, title, owner, assignee_id, status, priority, '
                'due_date, start_date, end_date, progress, position',
              )
              .inFilter('group_id', groupIds)
              .order('position');

    // Note counts in one aggregate pass, so the badge does not cost a query
    // per task.
    final noteCounts = await _loadNoteCounts(
      taskRows.map((row) => row['id'] as String).toList(),
    );

    return boardRows.map((boardRow) {
      final boardId = boardRow['id'] as String;
      final groups = groupRows
          .where((groupRow) => groupRow['board_id'] == boardId)
          .map((groupRow) {
            final groupId = groupRow['id'] as String;
            final tasks = taskRows
                .where((taskRow) => taskRow['group_id'] == groupId)
                .map(
                  (taskRow) => PlannerTask.fromMap({
                    ...taskRow,
                    'note_count': noteCounts[taskRow['id']] ?? 0,
                  }),
                )
                .toList();

            return TaskGroup(
              id: groupId,
              boardId: boardId,
              name: (groupRow['name'] ?? '') as String,
              color: Color((groupRow['color'] as num?)?.toInt() ?? 0xFF0F6BFF),
              tasks: tasks,
            );
          })
          .toList();

      return Board(
        id: boardId,
        name: (boardRow['name'] ?? '') as String,
        color: Color((boardRow['color'] as num?)?.toInt() ?? 0xFF0F6BFF),
        groups: groups,
      );
    }).toList();
  }

  Future<Map<String, int>> _loadNoteCounts(List<String> taskIds) async {
    if (taskIds.isEmpty) {
      return {};
    }
    final rows = await _client
        .from('task_notes')
        .select('task_id')
        .inFilter('task_id', taskIds);

    final counts = <String, int>{};
    for (final row in rows) {
      final taskId = row['task_id'] as String;
      counts[taskId] = (counts[taskId] ?? 0) + 1;
    }
    return counts;
  }

  Future<String> createBoard({
    required String workspaceId,
    required String name,
    required Color color,
  }) async {
    final existing = await _client
        .from('boards')
        .select('id')
        .eq('workspace_id', workspaceId);

    final row = await _client
        .from('boards')
        .insert({
          'workspace_id': workspaceId,
          'name': name.trim(),
          'color': color.toARGB32(),
          'position': existing.length,
        })
        .select('id')
        .single();
    return row['id'] as String;
  }

  Future<void> updateBoard({
    required String boardId,
    required String name,
    required Color color,
  }) async {
    await _client
        .from('boards')
        .update({'name': name.trim(), 'color': color.toARGB32()})
        .eq('id', boardId);
  }

  /// Groups and tasks cascade via foreign keys.
  /// Deletes a board. Groups and tasks cascade via foreign keys.
  ///
  ///  on the delete makes it report which rows it removed. Without
  /// it PostgREST returns success even when row level security filtered every
  /// row out, so a delete that did nothing is indistinguishable from one that
  /// worked — the board simply reappears on the next load with no error.
  Future<void> deleteBoard(String boardId) async {
    final deleted = await _client
        .from('boards')
        .delete()
        .eq('id', boardId)
        .select('id');

    if (deleted.isEmpty) {
      throw StateError(
        'The board was not deleted. You may not have permission, or it was '
        'already removed.',
      );
    }
  }

  // === Groups ===

  Future<String> createGroup({
    required String boardId,
    required String name,
    required Color color,
  }) async {
    final existing = await _client
        .from('task_groups')
        .select('id')
        .eq('board_id', boardId);

    final row = await _client
        .from('task_groups')
        .insert({
          'board_id': boardId,
          'name': name.trim(),
          'color': color.toARGB32(),
          'position': existing.length,
        })
        .select('id')
        .single();
    return row['id'] as String;
  }

  Future<void> updateGroup({
    required String groupId,
    required String name,
    required Color color,
  }) async {
    await _client
        .from('task_groups')
        .update({'name': name.trim(), 'color': color.toARGB32()})
        .eq('id', groupId);
  }

  Future<void> deleteGroup(String groupId) async {
    final deleted = await _client
        .from('task_groups')
        .delete()
        .eq('id', groupId)
        .select('id');

    if (deleted.isEmpty) {
      throw StateError(
        'The group was not deleted. You may not have permission, or it was '
        'already removed.',
      );
    }
  }

  // === Tasks ===

  Future<String> createTask({
    required String groupId,
    required String title,
    required String owner,
    required TaskStatus status,
    required TaskPriority priority,
    required double progress,
    required int position,
    String? assigneeId,
    DateTime? dueDate,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final row = await _client
        .from('tasks')
        .insert({
          'group_id': groupId,
          'title': title.trim(),
          'owner': owner.trim(),
          'assignee_id': assigneeId,
          'status': status.name,
          'priority': priority.name,
          'due_date': _dateOnly(dueDate),
          'start_date': _dateOnly(startDate),
          'end_date': _dateOnly(endDate),
          'progress': progress,
          'position': position,
        })
        .select('id')
        .single();

    final taskId = row['id'] as String;
    await _logActivity(taskId: taskId, kind: 'created', detail: title.trim());
    return taskId;
  }

  Future<void> updateTask({
    required String taskId,
    required String groupId,
    required String title,
    required String owner,
    required TaskStatus status,
    required TaskPriority priority,
    required double progress,
    String? assigneeId,
    DateTime? dueDate,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    await _client
        .from('tasks')
        .update({
          'group_id': groupId,
          'title': title.trim(),
          'owner': owner.trim(),
          'assignee_id': assigneeId,
          'status': status.name,
          'priority': priority.name,
          'due_date': _dateOnly(dueDate),
          'start_date': _dateOnly(startDate),
          'end_date': _dateOnly(endDate),
          'progress': progress,
        })
        .eq('id', taskId);
  }

  /// Status and progress move together: finishing a task fills the bar, and
  /// filling the bar finishes the task.
  Future<void> updateTaskStatus(PlannerTask task, TaskStatus status) async {
    var progress = task.progress.clamp(0.0, 0.9);
    if (status == TaskStatus.done) {
      progress = 1.0;
    } else if (status == TaskStatus.notStarted) {
      progress = 0.0;
    }
    await _client
        .from('tasks')
        .update({'status': status.name, 'progress': progress})
        .eq('id', task.id);
    await _logActivity(
      taskId: task.id,
      kind: 'status',
      detail: status.label,
    );
  }

  Future<void> updateTaskProgress(PlannerTask task, double progress) async {
    final normalized = progress.clamp(0.0, 1.0);
    var status = task.status;
    if (normalized <= 0) {
      status = TaskStatus.notStarted;
    } else if (normalized >= 1) {
      status = TaskStatus.done;
    } else if (status == TaskStatus.done || status == TaskStatus.notStarted) {
      status = TaskStatus.working;
    }
    await _client
        .from('tasks')
        .update({'progress': normalized, 'status': status.name})
        .eq('id', task.id);
  }

  Future<void> updateTaskPositions(List<String> orderedTaskIds) async {
    // Supabase has no multi-row update in one call; upsert the changed rows.
    for (var index = 0; index < orderedTaskIds.length; index++) {
      await _client
          .from('tasks')
          .update({'position': index})
          .eq('id', orderedTaskIds[index]);
    }
  }

  Future<void> deleteTask(String taskId) async {
    final deleted = await _client
        .from('tasks')
        .delete()
        .eq('id', taskId)
        .select('id');

    if (deleted.isEmpty) {
      throw StateError(
        'The task was not deleted. You may not have permission, or it was '
        'already removed.',
      );
    }
  }

  // === Task notes (team-visible) ===

  Future<List<TaskNote>> loadNotes(String taskId) async {
    final rows = await _client
        .from('task_notes')
        .select(
          'id, task_id, body, color, pinned, position, created_at, updated_at, '
          'author:profiles!task_notes_author_id_fkey(id, email, full_name, avatar_url), '
          'editor:profiles!task_notes_edited_by_fkey(id, email, full_name, avatar_url)',
        )
        .eq('task_id', taskId)
        .order('pinned', ascending: false)
        .order('created_at');

    if (rows.isEmpty) {
      return [];
    }

    final reactions = await _loadReactions(
      rows.map((row) => row['id'] as String).toList(),
    );

    return rows.map((row) {
      final noteId = row['id'] as String;
      final author = row['author'];
      final editor = row['editor'];
      return TaskNote.fromMap(
        row,
        author: author is Map<String, dynamic>
            ? UserProfile.fromMap(author)
            : null,
        editedBy: editor is Map<String, dynamic>
            ? UserProfile.fromMap(editor)
            : null,
        reactions: reactions[noteId]?.counts ?? const {},
        myReactions: reactions[noteId]?.mine ?? const {},
      );
    }).toList();
  }

  Future<Map<String, _ReactionSummary>> _loadReactions(
    List<String> noteIds,
  ) async {
    if (noteIds.isEmpty) {
      return {};
    }
    final rows = await _client
        .from('task_note_reactions')
        .select('note_id, user_id, emoji')
        .inFilter('note_id', noteIds);

    final me = _uid;
    final summaries = <String, _ReactionSummary>{};
    for (final row in rows) {
      final noteId = row['note_id'] as String;
      final emoji = row['emoji'] as String;
      final summary = summaries.putIfAbsent(noteId, _ReactionSummary.new);
      summary.counts[emoji] = (summary.counts[emoji] ?? 0) + 1;
      if (row['user_id'] == me) {
        summary.mine.add(emoji);
      }
    }
    return summaries;
  }

  Future<String> addNote({
    required String taskId,
    required String body,
    required Color color,
  }) async {
    final userId = _uid;
    if (userId == null) {
      throw StateError('Not signed in.');
    }
    final existing = await _client
        .from('task_notes')
        .select('id')
        .eq('task_id', taskId);

    final row = await _client
        .from('task_notes')
        .insert({
          'task_id': taskId,
          'body': body,
          'color': color.toARGB32(),
          'position': existing.length,
          'author_id': userId,
        })
        .select('id')
        .single();

    await _logActivity(taskId: taskId, kind: 'note_added');
    return row['id'] as String;
  }

  Future<void> updateNote({
    required String noteId,
    required String body,
  }) async {
    // `edited_by` and `updated_at` are set by a trigger.
    await _client.from('task_notes').update({'body': body}).eq('id', noteId);
  }

  Future<void> updateNoteColor({
    required String noteId,
    required Color color,
  }) async {
    await _client
        .from('task_notes')
        .update({'color': color.toARGB32()})
        .eq('id', noteId);
  }

  Future<void> setNotePinned({
    required String noteId,
    required bool pinned,
  }) async {
    await _client.from('task_notes').update({'pinned': pinned}).eq('id', noteId);
  }

  Future<void> deleteNote(String noteId) async {
    await _client.from('task_notes').delete().eq('id', noteId);
  }

  Future<void> toggleReaction({
    required String noteId,
    required String emoji,
    required bool add,
  }) async {
    final userId = _uid;
    if (userId == null) {
      return;
    }
    if (add) {
      await _client.from('task_note_reactions').upsert({
        'note_id': noteId,
        'user_id': userId,
        'emoji': emoji,
      });
    } else {
      await _client
          .from('task_note_reactions')
          .delete()
          .eq('note_id', noteId)
          .eq('user_id', userId)
          .eq('emoji', emoji);
    }
  }

  // === Realtime ===

  /// Fires whenever anything in the workspace's boards changes, so the UI can
  /// reload. Coarse by design: correctness first, refinement later.
  RealtimeChannel subscribeToChanges({
    required String workspaceId,
    required VoidCallback onChange,
  }) {
    return _client
        .channel('workspace:$workspaceId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'tasks',
          callback: (_) => onChange(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'task_groups',
          callback: (_) => onChange(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'boards',
          callback: (_) => onChange(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'task_notes',
          callback: (_) => onChange(),
        )
        .subscribe();
  }

  /// Watches one task's notes and reactions, so an open thread updates as
  /// teammates post. Scoped to the task rather than the workspace: a notes
  /// dialog should not reload for activity on some unrelated board.
  RealtimeChannel subscribeToTaskNotes({
    required String taskId,
    required VoidCallback onChange,
  }) {
    return _client
        .channel('task-notes:$taskId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'task_notes',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'task_id',
            value: taskId,
          ),
          callback: (_) => onChange(),
        )
        // Reactions cannot be filtered by task_id — they only carry note_id —
        // so this listens broadly and lets the reload sort it out. Reaction
        // traffic is low enough that the extra fetches do not matter.
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'task_note_reactions',
          callback: (_) => onChange(),
        )
        .subscribe();
  }

  /// Watches for invitations addressed to the signed-in user, so the navbar
  /// bell appears without a restart.
  ///
  /// Not filtered server-side: the filter would have to match on email, and RLS
  /// already limits what this user can see. The callback just triggers a
  /// reload, which returns only their own invites.
  RealtimeChannel subscribeToMyInvites({required VoidCallback onChange}) {
    return _client
        .channel('my-invites')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'workspace_invites',
          callback: (_) => onChange(),
        )
        .subscribe();
  }

  Future<void> unsubscribe(RealtimeChannel channel) async {
    await _client.removeChannel(channel);
  }

  Future<void> _logActivity({
    required String taskId,
    required String kind,
    String detail = '',
  }) async {
    try {
      await _client.from('task_activity').insert({
        'task_id': taskId,
        'user_id': _uid,
        'kind': kind,
        'detail': detail,
      });
    } catch (_) {
      // Activity is a nice-to-have; never fail the real operation over it.
    }
  }
}

class _ReactionSummary {
  final Map<String, int> counts = {};
  final Set<String> mine = {};
}

/// Postgres `date` columns want a bare calendar date, not an ISO timestamp.
String? _dateOnly(DateTime? value) {
  if (value == null) {
    return null;
  }
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  return '${value.year}-$month-$day';
}
