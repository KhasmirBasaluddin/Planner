import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/board_filter.dart';
import '../../models/planner_models.dart';

/// All reads and writes for the planner. Row level security decides what the
/// signed-in user can see, so queries here never filter by user id themselves.
class PlannerRepository {
  PlannerRepository(this._client);

  final SupabaseClient _client;

  String? get _uid => _client.auth.currentUser?.id;

  /// The signed-in user, for callers that need to reason about ownership —
  /// "my tasks" in the filter panel, for one.
  String? get currentUserId => _uid;

  // === Workspaces ===

  /// Workspaces the user belongs to, each carrying **their own** role.
  ///
  /// The `user_id` filter is essential, not redundant. `members_select` lets
  /// you read every membership row in a workspace you belong to — that is what
  /// the members dialog lists — so without it this returned one row per
  /// teammate. Keyed by workspace id, the last row won: a member sitting
  /// alongside an owner was handed the *owner's* role, and the sidebar offered
  /// them Delete workspace.
  Future<List<Workspace>> loadWorkspaces() async {
    final userId = _uid;
    if (userId == null) {
      return [];
    }

    final rows = await _client
        .from('workspace_members')
        .select('role, workspaces(id, name, color, owner_id, join_code)')
        .eq('user_id', userId)
        .order('created_at');

    final workspaces = <String, Workspace>{};
    for (final row in rows) {
      final data = row['workspaces'];
      if (data is Map<String, dynamic>) {
        final workspace = Workspace.fromMap(data, role: row['role'] as String?);
        workspaces[workspace.id] = workspace;
      }
    }
    return workspaces.values.toList();
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

    // Read it back separately, by which point the trigger has run and the
    // membership row exists.
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
      'not_found' => 'No workspace matches that code. Check it and try again.',
      'too_many_attempts' =>
        'Too many incorrect codes. Wait an hour, or ask someone in the '
            'workspace to invite you directly.',
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
  /// Read from `profiles` rather than the auth metadata: the profile is what
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

  Future<void> updateMyProfile({required String fullName}) async {
    final userId = _uid;
    if (userId == null) {
      return;
    }
    await _client
        .from('profiles')
        .update({'full_name': fullName.trim()})
        .eq('id', userId);
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
        .select(
          'id, email, role, accepted_at, created_at, '
          'invitee:profiles!workspace_invites_invitee_id_fkey'
          '(id, email, full_name, avatar_url)',
        )
        .eq('workspace_id', workspaceId)
        .isFilter('accepted_at', null)
        .isFilter('declined_at', null)
        .order('created_at');

    return rows.map((row) {
      final invitee = row['invitee'];
      return WorkspaceInvite.fromMap(
        row,
        invitee: invitee is Map<String, dynamic>
            ? UserProfile.fromMap(invitee)
            : null,
      );
    }).toList();
  }

  /// Invitations awaiting the signed-in user's answer, with the context needed
  /// to answer them: who sent it, the workspace, and how big the team is.
  ///
  /// One RPC rather than a table query. Three things made the direct version
  /// fragile, and the function settles all of them server-side:
  ///
  ///   * the member count reads `workspace_members`, which someone who is not
  ///     yet a member cannot see
  ///   * `workspaces(...)` embedded from `workspace_invites` returned null
  ///     under RLS, and the invitation was dropped for having no name
  ///   * matching both `invitee_id` and `email` in one PostgREST filter meant
  ///     an `or=` expression, whose syntax an email address breaks silently
  Future<List<PendingInvite>> loadMyInvites() async {
    if (_uid == null) {
      return [];
    }

    final result = await _client.rpc<dynamic>('my_pending_invites');
    if (result is! List) {
      return [];
    }

    return result.whereType<Map<String, dynamic>>().map((row) {
      final inviter = row['invited_by'];
      return PendingInvite(
        id: row['id'] as String,
        workspaceId: (row['workspace_id'] ?? '') as String,
        workspaceName: (row['name'] ?? 'a workspace') as String,
        workspaceColor: Color((row['color'] as num?)?.toInt() ?? 0xFF4C5BD4),
        role: WorkspaceRole.fromName((row['role'] ?? 'member') as String),
        createdAt:
            DateTime.tryParse((row['created_at'] ?? '') as String) ??
            DateTime.now(),
        invitedBy: inviter is Map<String, dynamic>
            ? UserProfile.fromMap(inviter)
            : null,
        memberCount: (row['member_count'] as num?)?.toInt() ?? 0,
      );
    }).toList();
  }

  /// Accepts an invitation, or every pending one when [inviteId] is null.
  ///
  /// Never called on sign-in: an invitation waits in the notification centre
  /// until the person acts on it.
  Future<int> acceptInvites({String? inviteId}) async {
    final result = await _client.rpc<dynamic>(
      'accept_pending_invites',
      params: {'target_invite': inviteId},
    );
    if (result is int) {
      return result;
    }
    return int.tryParse('$result') ?? 0;
  }

  /// Declines an invitation.
  ///
  /// Marks it rather than deleting it: the delete policy requires workspace
  /// membership, which the invited person does not have. The update policy does
  /// allow them to act on a row addressed to their own email, and it leaves the
  /// inviter able to see it was turned down rather than silently vanishing.
  Future<void> declineInvite(String inviteId) async {
    await _client
        .from('workspace_invites')
        .update({'declined_at': DateTime.now().toIso8601String()})
        .eq('id', inviteId);
  }

  /// People matching what the user has typed, for the invite picker.
  ///
  /// Already-members and already-invited are filtered out server-side, so what
  /// comes back is exactly who can be invited. Returns nothing under two
  /// characters — the RPC refuses to enumerate the directory.
  Future<List<UserProfile>> searchInvitableUsers({
    required String workspaceId,
    required String query,
  }) async {
    if (query.trim().length < 2) {
      return [];
    }
    final result = await _client.rpc<dynamic>(
      'search_invitable_users',
      params: {'target_workspace': workspaceId, 'query': query.trim()},
    );
    if (result is! List) {
      return [];
    }
    return result
        .whereType<Map<String, dynamic>>()
        .map(UserProfile.fromMap)
        .toList();
  }

  /// Invites someone who already has an account, by id.
  ///
  /// This is the normal path: the picker resolves a real user, so the
  /// invitation is linked to them rather than to a string that has to match
  /// later.
  Future<void> inviteUser({
    required String workspaceId,
    required String userId,
    required WorkspaceRole role,
  }) async {
    final result = await _client.rpc<dynamic>(
      'invite_user',
      params: {
        'target_workspace': workspaceId,
        'target_user': userId,
        'invite_role': role.name,
      },
    );

    final map = result is Map<String, dynamic> ? result : const {};
    if (map['ok'] == true) {
      return;
    }
    throw StateError(switch (map['error']) {
      'already_member' => 'They are already in this workspace.',
      'no_such_user' => 'That account no longer exists.',
      _ => 'Could not send that invitation.',
    });
  }

  /// Invites someone by email address.
  ///
  /// Kept for people who have not signed up yet — there is no account to point
  /// at, so the address is the only handle. A trigger links the invitation to
  /// their profile the moment they register, and `accept_pending_invites()`
  /// turns it into a membership when they first sign in.
  Future<void> inviteMember({
    required String workspaceId,
    required String email,
    required WorkspaceRole role,
  }) async {
    final userId = _uid;
    if (userId == null) {
      throw StateError('Not signed in.');
    }
    await _client.from('workspace_invites').insert({
      'workspace_id': workspaceId,
      'email': email.trim().toLowerCase(),
      'role': role.name,
      'invited_by': userId,
    });
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

  /// Leaves a workspace, giving up access to everything in it.
  ///
  /// The owner cannot: their workspace would be left with nobody able to manage
  /// it, and `workspaces_delete` is theirs alone. They delete it or hand it on
  /// instead. Checked here for a clear message, and again by the database.
  Future<void> leaveWorkspace({
    required String workspaceId,
    required bool isOwner,
  }) async {
    final userId = _uid;
    if (userId == null) {
      throw StateError('Not signed in.');
    }
    if (isOwner) {
      throw StateError(
        'You own this workspace, so you cannot leave it. Delete it instead, or '
        'make someone else the owner first.',
      );
    }

    // .select() makes the delete report what it removed. Without it PostgREST
    // returns success even when row level security filtered every row out, so
    // a no-op is indistinguishable from a real departure.
    final removed = await _client
        .from('workspace_members')
        .delete()
        .eq('workspace_id', workspaceId)
        .eq('user_id', userId)
        .select('workspace_id');

    if (removed.isEmpty) {
      throw StateError('Could not leave that workspace. Try again.');
    }
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

  /// Every board in a workspace, with its statuses, groups, tasks and
  /// assignees, in one round trip.
  ///
  /// `board_tree` assembles the nested structure server-side. This used to be
  /// four sequential queries joined in Dart, plus a fetch of every note row
  /// just to count them.
  Future<List<Board>> loadBoards(String workspaceId) async {
    final result = await _client.rpc<dynamic>(
      'board_tree',
      params: {'target_workspace': workspaceId},
    );

    if (result is! List) {
      return [];
    }
    return result.whereType<Map<String, dynamic>>().map(Board.fromMap).toList();
  }

  Future<String> createBoard({
    required String workspaceId,
    required String name,
    required Color color,
  }) async {
    final row = await _client
        .from('boards')
        .insert({
          'workspace_id': workspaceId,
          'name': name.trim(),
          'color': color.toARGB32(),
          'position': await _nextPosition(
            table: 'boards',
            column: 'workspace_id',
            parentId: workspaceId,
          ),
          'created_by': _uid,
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

  /// Pins or unpins a board, floating it to the top of the sidebar.
  ///
  /// Per workspace, not per person: the whole team sees the same board first.
  Future<void> setBoardPinned({
    required String boardId,
    required bool pinned,
  }) async {
    // .select() makes the update report which rows it touched. PostgREST
    // returns success even when row level security filtered every row out, so
    // without this a pin that changed nothing is indistinguishable from one
    // that worked — which is exactly how it looked.
    final updated = await _client
        .from('boards')
        .update({'pinned': pinned})
        .eq('id', boardId)
        .select('id, pinned');

    if (updated.isEmpty) {
      throw StateError(
        'The board was not pinned. You may not have permission, or it was '
        'already removed.',
      );
    }
  }

  /// Moves a board to the recycle bin. Groups, tasks and notes go with it and
  /// come back together via [restoreBoard].
  Future<void> deleteBoard(String boardId) async {
    await _softDelete('boards', boardId);
  }

  // ---------------------------------------------------------------------------
  // Saved filter views
  //
  // Backed by board_views, which already had a name, a jsonb config, and a
  // created_by. Favorites are private: every query here is scoped to the
  // signed-in user, and RLS enforces the same rule server-side.
  // ---------------------------------------------------------------------------

  /// The current user's saved views for [boardId], newest last.
  Future<List<SavedView>> savedViews(String boardId) async {
    final userId = _uid;
    if (userId == null) {
      return const [];
    }
    // Filtered on created_by even though board_views_select already hides other
    // people's private views. Shared views written by an earlier build are
    // still readable through that policy, and without this filter they would
    // appear in a list the user cannot meaningfully own.
    final rows = await _client
        .from('board_views')
        .select('id, board_id, name, config, created_at')
        .eq('board_id', boardId)
        .eq('created_by', userId)
        .order('created_at');

    return rows.map<SavedView>(SavedView.fromMap).toList();
  }

  /// Saves the active search under [name] and returns it with its new id.
  Future<SavedView> saveView({
    required String boardId,
    required String workspaceId,
    required String name,
    required BoardSearch search,
    bool isDefault = false,
  }) async {
    final userId = _uid;
    if (userId == null) {
      throw StateError('You must be signed in to save a view.');
    }

    // Clear the old default first. board_views_one_default_idx makes two
    // defaults impossible, so without this the insert below fails outright
    // rather than replacing what was there.
    if (isDefault) {
      await _clearDefaultView(boardId, userId);
    }

    final view = SavedView(
      id: '',
      boardId: boardId,
      name: name.trim(),
      search: search,
      isDefault: isDefault,
    );

    final inserted = await _client
        .from('board_views')
        .insert({
          'board_id': boardId,
          'workspace_id': workspaceId,
          'name': view.name,
          'kind': 'table',
          'config': view.toConfig(),
          'is_shared': false,
          'created_by': userId,
        })
        .select('id, board_id, name, config')
        .single();

    return SavedView.fromMap(inserted);
  }

  /// Renames a saved filter, replaces the search it holds, or changes its
  /// default flag.
  ///
  /// Distinct from [updateView], which is the generic board_views editor: this
  /// one round-trips through [SavedView] so the jsonb config keeps its shape,
  /// and it enforces the one-default rule.
  Future<void> updateSavedView({
    required String viewId,
    required String boardId,
    String? name,
    BoardSearch? search,
    bool? isDefault,
  }) async {
    final userId = _uid;
    if (userId == null) {
      throw StateError('You must be signed in to change a view.');
    }

    final current = await _client
        .from('board_views')
        .select('id, board_id, name, config')
        .eq('id', viewId)
        .eq('created_by', userId)
        .maybeSingle();

    if (current == null) {
      throw StateError('That view no longer exists.');
    }

    final existing = SavedView.fromMap(current);
    final next = existing.copyWith(
      name: name?.trim(),
      search: search,
      isDefault: isDefault,
    );

    if (isDefault == true && !existing.isDefault) {
      await _clearDefaultView(boardId, userId);
    }

    final updated = await _client
        .from('board_views')
        .update({'name': next.name, 'config': next.toConfig()})
        .eq('id', viewId)
        .eq('created_by', userId)
        .select('id');

    // As with setBoardPinned: PostgREST reports success when RLS filtered every
    // row away, so an update that changed nothing needs saying out loud.
    if (updated.isEmpty) {
      throw StateError('That view could not be updated.');
    }
  }

  /// Deletes one of your own saved filters.
  ///
  /// Scoped to created_by, unlike [deleteView]: a favorite is personal, and
  /// deleting by id alone would let a stale id from another board through.
  Future<void> deleteSavedView(String viewId) async {
    final userId = _uid;
    if (userId == null) {
      return;
    }
    await _client
        .from('board_views')
        .delete()
        .eq('id', viewId)
        .eq('created_by', userId);
  }

  /// Drops the default flag from whichever of this user's views holds it.
  Future<void> _clearDefaultView(String boardId, String userId) async {
    final rows = await _client
        .from('board_views')
        .select('id, board_id, name, config')
        .eq('board_id', boardId)
        .eq('created_by', userId);

    for (final row in rows) {
      final view = SavedView.fromMap(row);
      if (!view.isDefault) {
        continue;
      }
      await _client
          .from('board_views')
          .update({'config': view.copyWith(isDefault: false).toConfig()})
          .eq('id', view.id)
          .eq('created_by', userId);
    }
  }

  Future<void> restoreBoard(String boardId) async {
    await _client.rpc<void>(
      'restore',
      params: {'entity': 'boards', 'target_id': boardId},
    );
  }

  // === Status labels ===

  Future<String> createStatusLabel({
    required String boardId,
    required String name,
    required Color color,
    bool isDone = false,
  }) async {
    final row = await _client
        .from('board_status_labels')
        .insert({
          'board_id': boardId,
          'name': name.trim(),
          'color': color.toARGB32(),
          'is_done': isDone,
          'position': await _nextPosition(
            table: 'board_status_labels',
            column: 'board_id',
            parentId: boardId,
          ),
        })
        .select('id')
        .single();
    return row['id'] as String;
  }

  /// Renaming a status is one row, however many tasks carry it — they hold the
  /// id, not the word.
  Future<void> updateStatusLabel({
    required String labelId,
    String? name,
    Color? color,
    bool? isDone,
  }) async {
    final patch = <String, dynamic>{
      if (name != null) 'name': name.trim(),
      if (color != null) 'color': color.toARGB32(),
      'is_done': ?isDone,
    };
    if (patch.isEmpty) {
      return;
    }
    await _client.from('board_status_labels').update(patch).eq('id', labelId);
  }

  /// Tasks holding this label fall back to null, which the UI renders as "no
  /// status" rather than losing the task.
  Future<void> deleteStatusLabel(String labelId) async {
    await _client.from('board_status_labels').delete().eq('id', labelId);
  }

  // === Groups ===

  Future<String> createGroup({
    required String boardId,
    required String name,
    required Color color,
  }) async {
    final row = await _client
        .from('task_groups')
        .insert({
          'board_id': boardId,
          'name': name.trim(),
          'color': color.toARGB32(),
          'position': await _nextPosition(
            table: 'task_groups',
            column: 'board_id',
            parentId: boardId,
          ),
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

  Future<void> setGroupCollapsed({
    required String groupId,
    required bool collapsed,
  }) async {
    await _client
        .from('task_groups')
        .update({'collapsed': collapsed})
        .eq('id', groupId);
  }

  Future<void> deleteGroup(String groupId) async {
    await _softDelete('task_groups', groupId);
  }

  Future<void> restoreGroup(String groupId) async {
    await _client.rpc<void>(
      'restore',
      params: {'entity': 'task_groups', 'target_id': groupId},
    );
  }

  // === Tasks ===

  Future<String> createTask({
    required String groupId,
    required String title,
    required TaskPriority priority,
    required double progress,
    String? statusId,
    List<String> assigneeIds = const [],
    DateTime? dueDate,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final row = await _client
        .from('tasks')
        .insert({
          'group_id': groupId,
          'title': title.trim(),
          // Omitted when null so the board's default status trigger applies.
          'status_id': ?statusId,
          'priority': priority.name,
          'due_date': _dateOnly(dueDate),
          'start_date': _dateOnly(startDate),
          'end_date': _dateOnly(endDate),
          'progress': progress,
          'position': await _nextPosition(
            table: 'tasks',
            column: 'group_id',
            parentId: groupId,
          ),
          'created_by': _uid,
        })
        .select('id')
        .single();

    final taskId = row['id'] as String;
    if (assigneeIds.isNotEmpty) {
      await setTaskAssignees(taskId: taskId, userIds: assigneeIds);
    }
    await _logActivity(
      taskId: taskId,
      kind: ActivityKind.created,
      detail: {'title': title.trim()},
    );
    return taskId;
  }

  Future<void> updateTask({
    required String taskId,
    required String groupId,
    required String title,
    required TaskPriority priority,
    required double progress,
    String? statusId,
    List<String>? assigneeIds,
    DateTime? dueDate,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    await _client
        .from('tasks')
        .update({
          'group_id': groupId,
          'title': title.trim(),
          'status_id': statusId,
          'priority': priority.name,
          'due_date': _dateOnly(dueDate),
          'start_date': _dateOnly(startDate),
          'end_date': _dateOnly(endDate),
          'progress': progress,
        })
        .eq('id', taskId);

    if (assigneeIds != null) {
      await setTaskAssignees(taskId: taskId, userIds: assigneeIds);
    }
  }

  /// Status and progress move together: finishing a task fills the bar, and
  /// filling the bar finishes the task.
  ///
  /// Which status counts as finished is the board's call, hence [isDone].
  Future<void> updateTaskStatus(
    PlannerTask task,
    StatusLabel status, {
    StatusLabel? previous,
  }) async {
    await _client
        .from('tasks')
        .update({
          'status_id': status.id,
          'progress': progressForStatus(status, task.progress),
        })
        .eq('id', task.id);

    await _logActivity(
      taskId: task.id,
      kind: ActivityKind.statusChanged,
      detail: {'from': previous?.name ?? '', 'to': status.name},
    );
  }

  /// Dragging the progress bar to either end moves the status with it, using
  /// the board's own labels rather than a hardcoded name.
  Future<void> updateTaskProgress(
    PlannerTask task,
    double progress, {
    required List<StatusLabel> statuses,
  }) async {
    final normalized = progress.clamp(0.0, 1.0);
    String? statusId = task.statusId;

    if (normalized >= 1) {
      statusId = statuses.where((s) => s.isDone).firstOrNull?.id ?? statusId;
    } else if (normalized <= 0) {
      statusId = statuses.where((s) => s.isDefault).firstOrNull?.id ?? statusId;
    } else {
      // Mid-progress contradicts both ends, so leave either behind.
      final current = statuses.where((s) => s.id == task.statusId).firstOrNull;
      if ((current?.isDone ?? false) || (current?.isDefault ?? false)) {
        statusId =
            statuses.where((s) => !s.isDone && !s.isDefault).firstOrNull?.id ??
            statusId;
      }
    }

    await _client
        .from('tasks')
        .update({'progress': normalized, 'status_id': statusId})
        .eq('id', task.id);
  }

  /// Moves a task between [before] and [after], or to the end of [groupId] when
  /// both are null.
  ///
  /// One request, one row updated, whatever the board size. The old approach
  /// renumbered every task after the insertion point — one round trip each,
  /// non-atomic, and corrupted when two people dragged at once.
  Future<void> moveTask({
    required String taskId,
    required String groupId,
    String? beforeTaskId,
    String? afterTaskId,
  }) async {
    await _client.rpc<dynamic>(
      'reorder_task',
      params: {
        'target_task': taskId,
        'target_group': groupId,
        'before_task': beforeTaskId,
        'after_task': afterTaskId,
      },
    );
  }

  /// Resets a group's positions to whole numbers.
  ///
  /// Each move takes the midpoint between two neighbours, halving the gap, so a
  /// long enough drag sequence eventually exhausts precision. Call this if
  /// ordering ever starts misbehaving.
  Future<void> renormalizeGroup(String groupId) async {
    await _client.rpc<void>(
      'renormalize_task_positions',
      params: {'target_group': groupId},
    );
  }

  Future<void> deleteTask(String taskId) async {
    await _softDelete('tasks', taskId);
  }

  Future<void> restoreTask(String taskId) async {
    await _client.rpc<void>(
      'restore',
      params: {'entity': 'tasks', 'target_id': taskId},
    );
  }

  // === Assignees ===

  /// Replaces a task's assignees wholesale, which is how the task dialog thinks
  /// about it: pick a set, save.
  Future<void> setTaskAssignees({
    required String taskId,
    required List<String> userIds,
  }) async {
    await _client.rpc<void>(
      'set_task_assignees',
      params: {'target_task': taskId, 'user_ids': userIds},
    );
  }

  // === Recycle bin ===

  Future<Map<String, dynamic>> loadDeletedItems(String workspaceId) async {
    final result = await _client.rpc<dynamic>(
      'deleted_items',
      params: {'target_workspace': workspaceId},
    );
    return result is Map<String, dynamic> ? result : <String, dynamic>{};
  }

  Future<void> _softDelete(String entity, String id) async {
    await _client.rpc<void>(
      'soft_delete',
      params: {'entity': entity, 'target_id': id},
    );
  }

  // === Custom columns ===

  Future<List<BoardColumn>> loadColumns(String boardId) async {
    final rows = await _client
        .from('board_columns')
        .select('id, board_id, name, kind, settings, position, width')
        .eq('board_id', boardId)
        .order('position');
    return rows.map(BoardColumn.fromMap).toList();
  }

  Future<String> createColumn({
    required String boardId,
    required String name,
    required ColumnKind kind,
    Map<String, dynamic> settings = const {},
  }) async {
    final row = await _client
        .from('board_columns')
        .insert({
          'board_id': boardId,
          'name': name.trim(),
          'kind': kind.wire,
          'settings': settings,
          'position': await _nextPosition(
            table: 'board_columns',
            column: 'board_id',
            parentId: boardId,
          ),
        })
        .select('id')
        .single();
    return row['id'] as String;
  }

  Future<void> updateColumn({
    required String columnId,
    String? name,
    Map<String, dynamic>? settings,
    int? width,
  }) async {
    final patch = <String, dynamic>{
      if (name != null) 'name': name.trim(),
      'settings': ?settings,
      'width': ?width,
    };
    if (patch.isEmpty) {
      return;
    }
    await _client.from('board_columns').update(patch).eq('id', columnId);
  }

  Future<void> deleteColumn(String columnId) async {
    await _client.from('board_columns').delete().eq('id', columnId);
  }

  /// Custom column values for a board's tasks, as `taskId -> columnId -> value`.
  Future<Map<String, Map<String, dynamic>>> loadColumnValues(
    List<String> taskIds,
  ) async {
    if (taskIds.isEmpty) {
      return {};
    }
    final rows = await _client
        .from('task_column_values')
        .select('task_id, column_id, value')
        .inFilter('task_id', taskIds);

    final values = <String, Map<String, dynamic>>{};
    for (final row in rows) {
      final taskId = row['task_id'] as String;
      values.putIfAbsent(taskId, () => {})[row['column_id'] as String] =
          row['value'];
    }
    return values;
  }

  Future<void> setColumnValue({
    required String taskId,
    required String columnId,
    required dynamic value,
  }) async {
    await _client.from('task_column_values').upsert({
      'task_id': taskId,
      'column_id': columnId,
      'value': value,
      'updated_by': _uid,
      'updated_at': DateTime.now().toIso8601String(),
    }, onConflict: 'task_id,column_id');
  }

  // === Saved views ===

  Future<List<BoardView>> loadViews(String boardId) async {
    final rows = await _client
        .from('board_views')
        .select(
          'id, board_id, name, kind, config, position, is_shared, created_by',
        )
        .eq('board_id', boardId)
        .order('position');
    return rows.map(BoardView.fromMap).toList();
  }

  Future<String> createView({
    required String boardId,
    required String name,
    required ViewMode kind,
    Map<String, dynamic> config = const {},
    bool isShared = true,
  }) async {
    final userId = _uid;
    if (userId == null) {
      throw StateError('Not signed in.');
    }
    final row = await _client
        .from('board_views')
        .insert({
          'board_id': boardId,
          'name': name.trim(),
          'kind': kind.name,
          'config': config,
          'is_shared': isShared,
          'created_by': userId,
          'position': await _nextPosition(
            table: 'board_views',
            column: 'board_id',
            parentId: boardId,
          ),
        })
        .select('id')
        .single();
    return row['id'] as String;
  }

  Future<void> updateView({
    required String viewId,
    String? name,
    Map<String, dynamic>? config,
    bool? isShared,
  }) async {
    final patch = <String, dynamic>{
      if (name != null) 'name': name.trim(),
      'config': ?config,
      'is_shared': ?isShared,
    };
    if (patch.isEmpty) {
      return;
    }
    await _client.from('board_views').update(patch).eq('id', viewId);
  }

  Future<void> deleteView(String viewId) async {
    await _client.from('board_views').delete().eq('id', viewId);
  }

  // === Task chat ===

  /// Every message on a task, threaded.
  ///
  /// Top-level messages come back oldest-first with their replies nested, which
  /// is the order a conversation reads in. Reactions and mentions are fetched
  /// alongside rather than per message — a thread of thirty would otherwise be
  /// sixty extra round trips.
  Future<List<TaskComment>> loadComments(String taskId) async {
    final rows = await _client
        .from('task_comments')
        .select(
          'id, task_id, parent_id, body, edited_at, created_at, '
          'author:profiles!task_comments_author_id_fkey'
          '(id, email, full_name, avatar_url)',
        )
        .eq('task_id', taskId)
        .order('created_at');

    if (rows.isEmpty) {
      return [];
    }

    final ids = rows.map((row) => row['id'] as String).toList();
    final reactions = await _loadCommentReactions(ids);
    final mentions = await _loadCommentMentions(ids);

    TaskComment build(Map<String, dynamic> row, List<TaskComment> replies) {
      final author = row['author'];
      final id = row['id'] as String;
      return TaskComment.fromMap(
        row,
        author: author is Map<String, dynamic>
            ? UserProfile.fromMap(author)
            : null,
        reactions: reactions[id]?.counts ?? const {},
        myReactions: reactions[id]?.mine ?? const {},
        mentionedIds: mentions[id] ?? const [],
        replies: replies,
      );
    }

    // Replies grouped by parent, then attached — one pass rather than a scan
    // of the whole list per message.
    final repliesByParent = <String, List<TaskComment>>{};
    for (final row in rows) {
      final parentId = row['parent_id'] as String?;
      if (parentId != null) {
        repliesByParent
            .putIfAbsent(parentId, () => [])
            .add(build(row, const []));
      }
    }

    return rows
        .where((row) => row['parent_id'] == null)
        .map((row) => build(row, repliesByParent[row['id']] ?? const []))
        .toList();
  }

  Future<Map<String, _ReactionSummary>> _loadCommentReactions(
    List<String> commentIds,
  ) async {
    if (commentIds.isEmpty) {
      return {};
    }
    final rows = await _client
        .from('task_comment_reactions')
        .select('comment_id, user_id, emoji')
        .inFilter('comment_id', commentIds);

    final me = _uid;
    final summaries = <String, _ReactionSummary>{};
    for (final row in rows) {
      final id = row['comment_id'] as String;
      final emoji = row['emoji'] as String;
      final summary = summaries.putIfAbsent(id, _ReactionSummary.new);
      summary.counts[emoji] = (summary.counts[emoji] ?? 0) + 1;
      if (row['user_id'] == me) {
        summary.mine.add(emoji);
      }
    }
    return summaries;
  }

  Future<Map<String, List<String>>> _loadCommentMentions(
    List<String> commentIds,
  ) async {
    if (commentIds.isEmpty) {
      return {};
    }
    final rows = await _client
        .from('task_comment_mentions')
        .select('comment_id, user_id')
        .inFilter('comment_id', commentIds);

    final mentions = <String, List<String>>{};
    for (final row in rows) {
      mentions
          .putIfAbsent(row['comment_id'] as String, () => [])
          .add(row['user_id'] as String);
    }
    return mentions;
  }

  /// Posts a message, or a reply when [parentId] is given.
  ///
  /// Mentions are parsed server-side by a trigger, so an @name works however
  /// the text was typed and cannot be spoofed by a modified client.
  Future<String> addComment({
    required String taskId,
    required String body,
    String? parentId,
  }) async {
    final userId = _uid;
    if (userId == null) {
      throw StateError('Not signed in.');
    }
    final row = await _client
        .from('task_comments')
        .insert({
          'task_id': taskId,
          'author_id': userId,
          'body': body.trim(),
          'parent_id': parentId,
        })
        .select('id')
        .single();

    await _logActivity(taskId: taskId, kind: ActivityKind.commentAdded);
    return row['id'] as String;
  }

  /// Edits your own message. `edited_at` marks it so the UI can say so.
  ///
  /// The author filter is belt and braces: the update policy also allows
  /// managers, so they can soft-delete, and without this a manager could
  /// rewrite someone else's words.
  Future<void> editComment({
    required String commentId,
    required String body,
  }) async {
    final updated = await _client
        .from('task_comments')
        .update({
          'body': body.trim(),
          'edited_at': DateTime.now().toIso8601String(),
        })
        .eq('id', commentId)
        .eq('author_id', _uid ?? '')
        .select('id');

    if (updated.isEmpty) {
      throw StateError('You can only edit your own messages.');
    }
  }

  /// Removes a message. Soft, so a reply does not lose the thread it hangs off.
  Future<void> deleteComment(String commentId) async {
    await _softDelete('task_comments', commentId);
  }

  Future<void> toggleCommentReaction({
    required String commentId,
    required String emoji,
    required bool add,
  }) async {
    final userId = _uid;
    if (userId == null) {
      return;
    }
    if (add) {
      await _client.from('task_comment_reactions').upsert({
        'comment_id': commentId,
        'user_id': userId,
        'emoji': emoji,
      });
    } else {
      await _client
          .from('task_comment_reactions')
          .delete()
          .eq('comment_id', commentId)
          .eq('user_id', userId)
          .eq('emoji', emoji);
    }
  }

  // === Activity ===

  Future<List<TaskActivity>> loadActivity(
    String taskId, {
    int limit = 50,
  }) async {
    final rows = await _client
        .from('task_activity')
        .select(
          'id, kind, detail, created_at, '
          'actor:profiles!task_activity_actor_id_fkey(id, email, full_name, avatar_url)',
        )
        .eq('task_id', taskId)
        .order('created_at', ascending: false)
        .limit(limit);

    return rows.map((row) {
      final actor = row['actor'];
      return TaskActivity.fromMap(
        row,
        actor: actor is Map<String, dynamic>
            ? UserProfile.fromMap(actor)
            : null,
      );
    }).toList();
  }

  // === Notifications ===

  /// The signed-in user's notifications, newest first. RLS restricts this to
  /// their own rows, so there is no user filter here.
  Future<List<AppNotification>> loadNotifications({
    bool unreadOnly = false,
    int limit = 50,
  }) async {
    var query = _client
        .from('notifications')
        .select(
          'id, kind, title, body, workspace_id, task_id, board_id, invite_id, '
          'read_at, created_at, '
          'actor:profiles!notifications_actor_id_fkey'
          '(id, email, full_name, avatar_url)',
        );

    if (unreadOnly) {
      query = query.isFilter('read_at', null);
    }

    final rows = await query.order('created_at', ascending: false).limit(limit);

    return rows.map((row) {
      final actor = row['actor'];
      return AppNotification.fromMap(
        row,
        actor: actor is Map<String, dynamic>
            ? UserProfile.fromMap(actor)
            : null,
      );
    }).toList();
  }

  /// Just the badge number, without fetching the rows behind it.
  Future<int> unreadNotificationCount() async {
    final result = await _client.rpc<dynamic>('unread_notification_count');
    if (result is int) {
      return result;
    }
    return int.tryParse('$result') ?? 0;
  }

  /// Marks the given notifications read, or all of them when [ids] is null.
  Future<int> markNotificationsRead({List<String>? ids}) async {
    final result = await _client.rpc<dynamic>(
      'mark_notifications_read',
      params: {'ids': ids},
    );
    if (result is int) {
      return result;
    }
    return int.tryParse('$result') ?? 0;
  }

  Future<void> deleteNotification(String id) async {
    await _client.from('notifications').delete().eq('id', id);
  }

  /// Watches the signed-in user's notifications, so the bell updates the moment
  /// something happens.
  ///
  /// Filtered on user_id server-side: notifications are the one table where
  /// every row belongs to exactly one person, so there is no reason to receive
  /// anyone else's traffic.
  RealtimeChannel subscribeToNotifications({required VoidCallback onChange}) {
    final userId = _uid;
    if (userId == null) {
      throw StateError('Not signed in.');
    }
    return _client
        .channel('notifications:$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: (_) => onChange(),
        )
        .subscribe();
  }

  // === Realtime ===

  /// Fires whenever anything in the workspace changes, so the UI can reload.
  /// Coarse by design: correctness first, refinement later.
  RealtimeChannel subscribeToChanges({
    required String workspaceId,
    required VoidCallback onChange,
  }) {
    var channel = _client.channel('workspace:$workspaceId');

    // Board content, filtered server-side to this workspace so a busy
    // neighbouring team costs nothing.
    for (final table in const [
      'tasks',
      'task_groups',
      'boards',
      'task_comments',
      'task_assignees',
      'task_column_values',
    ]) {
      channel = channel.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: table,
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'workspace_id',
          value: workspaceId,
        ),
        callback: (_) => onChange(),
      );
    }

    // Status labels carry board_id, not workspace_id, so they cannot be
    // filtered the same way. Low traffic — a reload sorts it out.
    channel = channel.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'board_status_labels',
      callback: (_) => onChange(),
    );

    return channel.subscribe();
  }

  /// Watches who is in a workspace: joins by code, invitations, role changes and
  /// removals, all live. Separate from [subscribeToChanges] so the members
  /// dialog can listen without also reloading every board.
  RealtimeChannel subscribeToTeam({
    required String workspaceId,
    required VoidCallback onChange,
  }) {
    return _client
        .channel('workspace-team:$workspaceId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'workspace_members',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'workspace_id',
            value: workspaceId,
          ),
          callback: (_) => onChange(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'workspace_invites',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'workspace_id',
            value: workspaceId,
          ),
          callback: (_) => onChange(),
        )
        // A rename should update the name everywhere it appears. Unfiltered:
        // profiles have no workspace_id, and the payload cannot be matched
        // against the member list server-side.
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'profiles',
          callback: (_) => onChange(),
        )
        .subscribe();
  }

  /// Watches one task's chat, so an open thread updates as teammates post.
  ///
  /// Scoped to the task: a conversation should not reload for activity on some
  /// unrelated board.
  RealtimeChannel subscribeToTaskChat({
    required String taskId,
    required VoidCallback onChange,
  }) {
    return _client
        .channel('task-chat:$taskId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'task_comments',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'task_id',
            value: taskId,
          ),
          callback: (_) => onChange(),
        )
        // Reactions carry comment_id, not task_id, so they cannot be filtered
        // to this task. Reaction traffic is low enough that the extra fetches
        // do not matter.
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'task_comment_reactions',
          callback: (_) => onChange(),
        )
        .subscribe();
  }

  /// Watches for invitations addressed to the signed-in user, so the navbar
  /// bell appears without a restart.
  ///
  /// Not filtered server-side: the filter would have to match on email, and RLS
  /// already limits what this user can see. The callback triggers a reload,
  /// which returns only their own invites.
  RealtimeChannel subscribeToMyInvites({required VoidCallback onChange}) {
    return _client
        .channel('my-invites')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'workspace_invites',
          callback: (_) => onChange(),
        )
        // Being added to a workspace by an admin, or removed from one.
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'workspace_members',
          callback: (_) => onChange(),
        )
        .subscribe();
  }

  Future<void> unsubscribe(RealtimeChannel channel) async {
    await _client.removeChannel(channel);
  }

  // === Helpers ===

  /// One past the highest position among a parent's children.
  ///
  /// Positions are fractional, so appending only needs the current maximum —
  /// no renumbering of anything already there.
  Future<double> _nextPosition({
    required String table,
    required String column,
    required String parentId,
  }) async {
    final rows = await _client
        .from(table)
        .select('position')
        .eq(column, parentId)
        .order('position', ascending: false)
        .limit(1);

    if (rows.isEmpty) {
      return 0;
    }
    return ((rows.first['position'] as num?)?.toDouble() ?? 0) + 1;
  }

  Future<void> _logActivity({
    required String taskId,
    required ActivityKind kind,
    Map<String, dynamic> detail = const {},
  }) async {
    try {
      await _client.rpc<void>(
        'log_activity',
        params: {
          'target_task': taskId,
          'entry_kind': kind.wire,
          'entry_detail': detail,
        },
      );
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
