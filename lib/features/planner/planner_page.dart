import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show RealtimeChannel;

import '../../core/supabase/auth_service.dart';
import '../../core/supabase/planner_repository.dart';
import '../../models/planner_models.dart';
import '../../shared/utils/planner_colors.dart';
import '../workspace/join_workspace_dialog.dart';
import '../workspace/members_dialog.dart';
import 'widgets/app_navbar.dart';
import 'widgets/board_calendar.dart';
import 'widgets/board_header.dart';
import 'widgets/board_kanban.dart';
import 'widgets/board_table.dart';
import 'widgets/board_toolbar.dart';
import 'widgets/planner_dialogs.dart';
import 'widgets/planner_sidebar.dart';

class PlannerPage extends StatefulWidget {
  const PlannerPage({
    super.key,
    required this.auth,
    required this.repository,
  });

  final AuthService auth;
  final PlannerRepository repository;

  @override
  State<PlannerPage> createState() => _PlannerPageState();
}

class _PlannerPageState extends State<PlannerPage> {
  final TextEditingController _searchController = TextEditingController();
  final Set<String> _collapsedGroupIds = <String>{};

  List<Workspace> _workspaces = [];
  List<Board> _boards = [];
  List<WorkspaceMember> _members = [];
  int _selectedWorkspaceIndex = 0;
  int _selectedBoardIndex = 0;
  String _query = '';
  ViewMode _mode = ViewMode.table;
  TaskOrder _taskOrder = TaskOrder.manual;
  bool _loading = true;
  String? _error;
  RealtimeChannel? _channel;
  RealtimeChannel? _inviteChannel;
  List<PendingInvite> _pendingInvites = [];
  String _myProfileName = '';

  Workspace? get _workspace {
    if (_workspaces.isEmpty) {
      return null;
    }
    return _workspaces[_selectedWorkspaceIndex.clamp(0, _workspaces.length - 1)];
  }

  Board? get _selectedBoard {
    if (_boards.isEmpty) {
      return null;
    }
    return _boards[_selectedBoardIndex.clamp(0, _boards.length - 1)];
  }

  bool get _canEdit => _workspace?.role.canEdit ?? false;

  List<TaskGroup> get _visibleGroups {
    final board = _selectedBoard;
    if (board == null) {
      return [];
    }

    final query = _query.trim().toLowerCase();
    return board.groups
        .map((group) {
          final tasks = query.isEmpty
              ? group.tasks
              : group.tasks
                    .where((task) => task.title.toLowerCase().contains(query))
                    .toList();

          return TaskGroup(
            id: group.id,
            boardId: group.boardId,
            name: group.name,
            color: group.color,
            tasks: _orderedTasks(tasks),
          );
        })
        .where((group) => query.isEmpty || group.tasks.isNotEmpty)
        .toList();
  }

  List<PlannerTask> _orderedTasks(List<PlannerTask> tasks) {
    final ordered = List<PlannerTask>.from(tasks);
    switch (_taskOrder) {
      case TaskOrder.manual:
        return ordered;
      case TaskOrder.title:
        ordered.sort(
          (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
        );
      case TaskOrder.dueDate:
        ordered.sort(_compareDueDate);
      case TaskOrder.priority:
        ordered.sort((a, b) => a.priority.index.compareTo(b.priority.index));
      case TaskOrder.status:
        ordered.sort((a, b) => _statusRank(a.status).compareTo(
          _statusRank(b.status),
        ));
    }
    return ordered;
  }

  /// Undated tasks sort last; otherwise chronological.
  int _compareDueDate(PlannerTask a, PlannerTask b) {
    final aDate = a.dueDate;
    final bDate = b.dueDate;
    if (aDate == null || bDate == null) {
      if (aDate == bDate) {
        return 0;
      }
      return aDate == null ? 1 : -1;
    }
    return aDate.compareTo(bDate);
  }

  int _statusRank(TaskStatus status) {
    return switch (status) {
      TaskStatus.notStarted => 0,
      TaskStatus.working => 1,
      TaskStatus.stuck => 2,
      TaskStatus.done => 3,
    };
  }

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _searchController.dispose();
    final channel = _channel;
    if (channel != null) {
      widget.repository.unsubscribe(channel);
    }
    final inviteChannel = _inviteChannel;
    if (inviteChannel != null) {
      widget.repository.unsubscribe(inviteChannel);
    }
    super.dispose();
  }

  Future<void> _bootstrap() async {
    // Seed from auth metadata so the navbar is not blank on first paint, then
    // replace it with the profile row, which is the name teammates see.
    _myProfileName =
        (widget.auth.currentUser?.userMetadata?['full_name'] ?? '') as String;
    unawaited(_loadInvites());
    unawaited(_loadMyProfile());
    // Keeps the bell live, so an invitation that arrives while the app is open
    // shows up without a restart.
    _inviteChannel = widget.repository.subscribeToMyInvites(
      onChange: () {
        if (mounted) {
          _loadInvites();
        }
      },
    );
    try {
      final workspaces = await widget.repository.loadWorkspaces();
      if (!mounted) {
        return;
      }

      if (workspaces.isEmpty) {
        // A brand-new account. Show the welcome screen rather than silently
        // creating something — a first-time user should be told what a
        // workspace is, not dropped into one they did not ask for.
        setState(() {
          _workspaces = [];
          _loading = false;
          _error = null;
        });
        return;
      }

      setState(() => _workspaces = workspaces);
      await _loadWorkspaceData();
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = _describe(error);
        });
      }
    }
  }

  Future<void> _loadWorkspaceData() async {
    final workspace = _workspace;
    if (workspace == null) {
      setState(() => _loading = false);
      return;
    }

    try {
      final boards = await widget.repository.loadBoards(workspace.id);
      // The member list is supporting detail — avatars and the assignee
      // picker. If it fails, the board itself is still perfectly usable, so
      // this must not take the whole screen down with it.
      final members = await widget.repository
          .loadMembers(workspace.id)
          .catchError((Object _) => <WorkspaceMember>[]);
      if (!mounted) {
        return;
      }
      setState(() {
        _boards = boards;
        _members = members;
        _selectedBoardIndex = _selectedBoardIndex.clamp(
          0,
          boards.isEmpty ? 0 : boards.length - 1,
        );
        _loading = false;
        _error = null;
      });
      _resubscribe(workspace.id);
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = _describe(error);
        });
      }
    }
  }

  /// Re-points the realtime subscription at the active workspace so teammates'
  /// changes arrive without a manual refresh.
  void _resubscribe(String workspaceId) {
    final existing = _channel;
    if (existing != null) {
      widget.repository.unsubscribe(existing);
    }
    _channel = widget.repository.subscribeToChanges(
      workspaceId: workspaceId,
      onChange: () {
        if (mounted) {
          _refreshBoards();
        }
      },
    );
  }

  /// Reloads boards without touching loading state, for background refreshes.
  Future<void> _refreshBoards() async {
    final workspace = _workspace;
    if (workspace == null) {
      return;
    }
    try {
      final boards = await widget.repository.loadBoards(workspace.id);
      if (mounted) {
        setState(() => _boards = boards);
      }
    } catch (_) {
      // A failed background refresh is not worth interrupting the user.
    }
  }

  String _describe(Object error) {
    final text = error.toString();
    if (text.contains('SocketException') ||
        text.contains('Failed host lookup')) {
      return 'Cannot reach Supabase. Check your internet connection.';
    }
    if (text.contains('row-level security') ||
        text.contains('violates row-level')) {
      return 'You do not have permission to do that in this workspace.';
    }
    if (text.contains('relation') && text.contains('does not exist')) {
      return 'The database schema is missing. Run supabase/schema.sql in your '
          'Supabase project, then restart.';
    }
    return text;
  }

  /// Runs a mutation, surfacing failures instead of swallowing them.
  Future<bool> _guard(
    Future<void> Function() action, {
    String? failureMessage,
  }) async {
    try {
      await action();
      return true;
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              backgroundColor: plannerRed,
              content: Text(failureMessage ?? _describe(error)),
            ),
          );
      }
      return false;
    }
  }

  /// Blocks writes for viewers with an explanation rather than a silent no-op.
  bool _requireEditor() {
    if (_canEdit) {
      return true;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('You have view-only access to this workspace.'),
        ),
      );
    return false;
  }

  // === Workspaces ===

  /// First-run setup: creates the workspace and a starter board in one step, so
  /// a new account lands on something usable rather than an empty shell.
  Future<void> _setUpFirstWorkspace() async {
    final result = await showNameDialog(
      context: context,
      title: 'Name your workspace',
      label: 'Workspace name',
      maxLength: NameLimits.workspace,
      initialValue: 'My workspace',
      existingNames: _workspaces.map((w) => w.name).toList(),
      duplicateNoun: 'workspace',
    );
    if (result == null) {
      return;
    }

    setState(() => _loading = true);

    final ok = await _guard(() async {
      final workspace = await widget.repository.createWorkspace(
        name: result.name,
        color: result.color,
      );
      // Seed a board so the next screen has something in it.
      final boardId = await widget.repository.createBoard(
        workspaceId: workspace.id,
        name: 'My first board',
        color: result.color,
      );
      await widget.repository.createGroup(
        boardId: boardId,
        name: 'To do',
        color: plannerBlue,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _workspaces = [workspace];
        _selectedWorkspaceIndex = 0;
      });
      await _loadWorkspaceData();
    }, failureMessage: 'Could not set up your workspace.');

    if (!ok && mounted) {
      setState(() => _loading = false);
    }
  }

  /// Joins an existing workspace by code, then switches to it.
  Future<void> _joinWorkspace() async {
    final name = await showJoinWorkspaceDialog(
      context: context,
      repository: widget.repository,
    );
    if (name == null || !mounted) {
      return;
    }

    setState(() => _loading = true);
    final workspaces = await widget.repository.loadWorkspaces();
    if (!mounted) {
      return;
    }
    final index = workspaces.indexWhere((w) => w.name == name);
    setState(() {
      _workspaces = workspaces;
      _selectedWorkspaceIndex = index >= 0 ? index : 0;
      _boards = [];
    });
    await _loadWorkspaceData();

    if (mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('Joined $name')));
    }
  }

  Future<void> _createWorkspace() async {
    final result = await showNameDialog(
      context: context,
      title: 'New workspace',
      label: 'Workspace name',
      maxLength: NameLimits.workspace,
      initialValue: 'Workspace ${_workspaces.length + 1}',
      existingNames: _workspaces.map((w) => w.name).toList(),
      duplicateNoun: 'workspace',
    );
    if (result == null) {
      return;
    }

    await _guard(() async {
      final created = await widget.repository.createWorkspace(
        name: result.name,
        color: result.color,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _workspaces = [..._workspaces, created];
        _selectedWorkspaceIndex = _workspaces.length - 1;
        _boards = [];
        _loading = true;
      });
      await _loadWorkspaceData();
    }, failureMessage: 'Could not create the workspace.');
  }

  Future<void> _switchWorkspace(int index) async {
    if (index == _selectedWorkspaceIndex) {
      return;
    }
    setState(() {
      _selectedWorkspaceIndex = index;
      _selectedBoardIndex = 0;
      _boards = [];
      _query = '';
      _searchController.clear();
      _collapsedGroupIds.clear();
      _loading = true;
    });
    await _loadWorkspaceData();
  }

  Future<void> _manageMembers() async {
    final workspace = _workspace;
    if (workspace == null) {
      return;
    }
    await showMembersDialog(
      context: context,
      workspace: workspace,
      repository: widget.repository,
      currentUserId: widget.auth.currentUser?.id ?? '',
    );
    await _loadWorkspaceData();
  }

  Future<void> _renameWorkspace() async {
    final workspace = _workspace;
    if (workspace == null || !_requireEditor()) {
      return;
    }
    final result = await showNameDialog(
      context: context,
      title: 'Edit workspace',
      label: 'Workspace name',
      maxLength: NameLimits.workspace,
      initialValue: workspace.name,
      initialColor: workspace.color,
      existingNames: _workspaces.map((w) => w.name).toList(),
      duplicateNoun: 'workspace',
    );
    if (result == null) {
      return;
    }

    await _guard(() async {
      await widget.repository.renameWorkspace(
        workspaceId: workspace.id,
        name: result.name,
        color: result.color,
      );
      final workspaces = await widget.repository.loadWorkspaces();
      if (mounted) {
        setState(() => _workspaces = workspaces);
      }
    }, failureMessage: 'Could not save the workspace.');
  }

  /// Deletes the workspace and everything in it. Owner only.
  ///
  /// The confirmation is deliberately heavier when other people are involved:
  /// removing a workspace with members also removes their access, and that is
  /// not obvious from "delete".
  Future<void> _deleteWorkspace() async {
    final workspace = _workspace;
    if (workspace == null) {
      return;
    }

    if (workspace.role != WorkspaceRole.owner) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Only the workspace owner can delete it.'),
          ),
        );
      return;
    }

    final others = _members.length > 1 ? _members.length - 1 : 0;
    final boardCount = _boards.length;

    final confirmed = await showDeleteConfirmDialog(
      context: context,
      title: others > 0
          ? 'Delete workspace and remove $others ' 
                '${others == 1 ? "person" : "people"}?'
          : 'Delete this workspace?',
      message: others > 0
          ? '"${workspace.name}" will be deleted along with '
                '$boardCount ${boardCount == 1 ? "board" : "boards"} and every '
                'task and note inside. $others '
                '${others == 1 ? "person loses" : "people lose"} access '
                'immediately. This cannot be undone.'
          : '"${workspace.name}" will be deleted along with '
                '$boardCount ${boardCount == 1 ? "board" : "boards"} and every '
                'task and note inside. This cannot be undone.',
      confirmLabel: 'Delete workspace',
    );
    if (!confirmed) {
      return;
    }

    final ok = await _guard(() async {
      await widget.repository.deleteWorkspace(workspace.id);
      final workspaces = await widget.repository.loadWorkspaces();
      if (!mounted) {
        return;
      }
      setState(() {
        _workspaces = workspaces;
        _selectedWorkspaceIndex = 0;
        _boards = [];
        _members = [];
        _loading = workspaces.isNotEmpty;
      });
      if (workspaces.isNotEmpty) {
        await _loadWorkspaceData();
      }
    }, failureMessage: 'Could not delete the workspace.');

    if (ok && mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text('Deleted "${workspace.name}"')),
        );
    }
  }

  Future<void> _loadMyProfile() async {
    final profile = await widget.repository.loadMyProfile();
    if (profile != null && mounted) {
      setState(() => _myProfileName = profile.displayName);
    }
  }

  /// Loads invitations addressed to this user, for the navbar bell.
  Future<void> _loadInvites() async {
    try {
      final invites = await widget.repository.loadMyInvites();
      if (mounted) {
        setState(() => _pendingInvites = invites);
      }
    } catch (_) {
      // The bell is supplementary; a failure here should not surface an error.
    }
  }

  Future<void> _acceptInvite(PendingInvite invite) async {
    final ok = await _guard(() async {
      await widget.repository.acceptInvites();
      final workspaces = await widget.repository.loadWorkspaces();
      if (!mounted) {
        return;
      }
      final index = workspaces.indexWhere((w) => w.id == invite.workspaceId);
      setState(() {
        _workspaces = workspaces;
        _selectedWorkspaceIndex = index >= 0 ? index : 0;
        _boards = [];
        _loading = true;
      });
      await _loadWorkspaceData();
      await _loadInvites();
    }, failureMessage: 'Could not accept the invitation.');

    if (ok && mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text('Joined ${invite.workspaceName}')),
        );
    }
  }

  Future<void> _declineInvite(PendingInvite invite) async {
    await _guard(() async {
      await widget.repository.declineInvite(invite.id);
      await _loadInvites();
    }, failureMessage: 'Could not decline the invitation.');
  }

  Future<void> _signOut() async {
    final confirmed = await showDeleteConfirmDialog(
      context: context,
      title: 'Sign out?',
      message:
          'You will need to sign in again to get back to your boards. '
          'Nothing is deleted.',
      confirmLabel: 'Sign out',
      danger: false,
    );
    if (!confirmed) {
      return;
    }
    await widget.auth.signOut();
  }

  // === Boards ===

  Future<void> _createBoard() async {
    final workspace = _workspace;
    if (workspace == null || !_requireEditor()) {
      return;
    }
    final result = await showNameDialog(
      context: context,
      title: 'New board',
      label: 'Board name',
      maxLength: NameLimits.board,
      initialValue: 'New board ${_boards.length + 1}',
      existingNames: _boards.map((b) => b.name).toList(),
      duplicateNoun: 'board',
    );
    if (result == null) {
      return;
    }

    String? boardId;
    final ok = await _guard(() async {
      boardId = await widget.repository.createBoard(
        workspaceId: workspace.id,
        name: result.name,
        color: result.color,
      );
      await _loadWorkspaceData();
    }, failureMessage: 'Could not create the board.');

    if (!ok || !mounted) {
      return;
    }
    final index = _boards.indexWhere((board) => board.id == boardId);
    if (index >= 0) {
      setState(() => _selectedBoardIndex = index);
    }
  }

  Future<void> _renameBoard(Board board) async {
    if (!_requireEditor()) {
      return;
    }
    final result = await showNameDialog(
      context: context,
      title: 'Edit board',
      label: 'Board name',
      maxLength: NameLimits.board,
      initialValue: board.name,
      initialColor: board.color,
      existingNames: _boards.map((b) => b.name).toList(),
      duplicateNoun: 'board',
    );
    if (result == null) {
      return;
    }

    await _guard(() async {
      await widget.repository.updateBoard(
        boardId: board.id,
        name: result.name,
        color: result.color,
      );
      await _loadWorkspaceData();
    }, failureMessage: 'Could not save the board.');
  }

  Future<void> _deleteBoard(Board board) async {
    if (!_requireEditor()) {
      return;
    }
    final confirmed = await showDeleteConfirmDialog(
      context: context,
      title: 'Delete board',
      message:
          'Delete "${board.name}" and everything inside it? '
          'This cannot be undone.',
    );
    if (!confirmed) {
      return;
    }

    await _guard(() async {
      await widget.repository.deleteBoard(board.id);
      await _loadWorkspaceData();
    }, failureMessage: 'Could not delete the board.');
  }

  // === Groups ===

  Future<void> _addGroup() async {
    final board = _selectedBoard;
    if (board == null || !_requireEditor()) {
      return;
    }
    final result = await showNameDialog(
      context: context,
      title: 'New group',
      label: 'Group name',
      maxLength: NameLimits.group,
      initialValue: 'New group ${board.groups.length + 1}',
      existingNames: board.groups.map((g) => g.name).toList(),
      duplicateNoun: 'group on this board',
    );
    if (result == null) {
      return;
    }

    await _guard(() async {
      await widget.repository.createGroup(
        boardId: board.id,
        name: result.name,
        color: result.color,
      );
      await _loadWorkspaceData();
    }, failureMessage: 'Could not create the group.');
  }

  Future<void> _renameGroup(TaskGroup group) async {
    if (!_requireEditor()) {
      return;
    }
    final result = await showNameDialog(
      context: context,
      title: 'Edit group',
      label: 'Group name',
      maxLength: NameLimits.group,
      initialValue: group.name,
      initialColor: group.color,
      existingNames:
          _selectedBoard?.groups.map((g) => g.name).toList() ?? const [],
      duplicateNoun: 'group on this board',
    );
    if (result == null) {
      return;
    }

    await _guard(() async {
      await widget.repository.updateGroup(
        groupId: group.id,
        name: result.name,
        color: result.color,
      );
      await _loadWorkspaceData();
    }, failureMessage: 'Could not save the group.');
  }

  Future<void> _deleteGroup(TaskGroup group) async {
    if (!_requireEditor()) {
      return;
    }
    final confirmed = await showDeleteConfirmDialog(
      context: context,
      title: 'Delete group',
      message:
          'Delete "${group.name}" and all tasks inside it? '
          'This cannot be undone.',
    );
    if (!confirmed) {
      return;
    }

    await _guard(() async {
      await widget.repository.deleteGroup(group.id);
      _collapsedGroupIds.remove(group.id);
      await _loadWorkspaceData();
    }, failureMessage: 'Could not delete the group.');
  }

  // === Tasks ===

  Future<void> _addTask() async {
    final board = _selectedBoard;
    if (board == null || board.groups.isEmpty || !_requireEditor()) {
      return;
    }
    final result = await showTaskDialog(
      context: context,
      groups: board.groups,
      members: _members,
    );
    if (result == null) {
      return;
    }

    final group = board.groups.firstWhere(
      (group) => group.id == result.groupId,
    );
    await _guard(() async {
      await widget.repository.createTask(
        groupId: result.groupId,
        title: result.title,
        owner: result.owner,
        assigneeId: result.assigneeId,
        status: result.status,
        priority: result.priority,
        dueDate: result.dueDate,
        startDate: result.startDate,
        endDate: result.endDate,
        progress: result.progress,
        position: group.tasks.length,
      );
      await _loadWorkspaceData();
    }, failureMessage: 'Could not create the task.');
  }

  Future<void> _editTask(PlannerTask task) async {
    final board = _selectedBoard;
    if (board == null || board.groups.isEmpty || !_requireEditor()) {
      return;
    }
    final result = await showTaskDialog(
      context: context,
      groups: board.groups,
      members: _members,
      task: task,
    );
    if (result == null) {
      return;
    }

    await _guard(() async {
      await widget.repository.updateTask(
        taskId: task.id,
        groupId: result.groupId,
        title: result.title,
        owner: result.owner,
        assigneeId: result.assigneeId,
        status: result.status,
        priority: result.priority,
        dueDate: result.dueDate,
        startDate: result.startDate,
        endDate: result.endDate,
        progress: result.progress,
      );
      await _loadWorkspaceData();
    }, failureMessage: 'Could not save the task.');
  }

  Future<void> _deleteTask(PlannerTask task) async {
    if (!_requireEditor()) {
      return;
    }
    final confirmed = await showDeleteConfirmDialog(
      context: context,
      title: 'Delete task',
      message: 'Delete "${task.title}"? This cannot be undone.',
    );
    if (!confirmed) {
      return;
    }

    await _guard(() async {
      await widget.repository.deleteTask(task.id);
      await _loadWorkspaceData();
    }, failureMessage: 'Could not delete the task.');
  }

  Future<void> _changeStatus(PlannerTask task, TaskStatus status) async {
    if (!_requireEditor()) {
      return;
    }
    await _guard(() async {
      await widget.repository.updateTaskStatus(task, status);
      await _refreshBoards();
    }, failureMessage: 'Could not update the status.');
  }

  Future<void> _changeProgress(PlannerTask task, double progress) async {
    if (!_requireEditor()) {
      return;
    }
    await _guard(() async {
      await widget.repository.updateTaskProgress(task, progress);
      await _refreshBoards();
    }, failureMessage: 'Could not update the progress.');
  }

  Future<void> _reorderTask(TaskGroup group, int oldIndex, int newIndex) async {
    if (_taskOrder != TaskOrder.manual || !_canEdit) {
      return;
    }
    final board = _selectedBoard;
    if (board == null) {
      return;
    }
    final groupIndex = board.groups.indexWhere((item) => item.id == group.id);
    if (groupIndex < 0) {
      return;
    }

    final tasks = List<PlannerTask>.from(board.groups[groupIndex].tasks);
    if (oldIndex < 0 ||
        oldIndex >= tasks.length ||
        newIndex < 0 ||
        newIndex > tasks.length) {
      return;
    }

    final adjustedNewIndex = newIndex > oldIndex ? newIndex - 1 : newIndex;
    if (oldIndex == adjustedNewIndex) {
      return;
    }

    final task = tasks.removeAt(oldIndex);
    tasks.insert(adjustedNewIndex, task);

    // Optimistic: reflect the new order before the round trip.
    final updatedGroups = List<TaskGroup>.from(board.groups);
    final currentGroup = updatedGroups[groupIndex];
    updatedGroups[groupIndex] = TaskGroup(
      id: currentGroup.id,
      boardId: currentGroup.boardId,
      name: currentGroup.name,
      color: currentGroup.color,
      tasks: tasks,
    );

    final boardIndex = _boards.indexWhere((item) => item.id == board.id);
    if (boardIndex >= 0 && mounted) {
      setState(() {
        final updatedBoards = List<Board>.from(_boards);
        updatedBoards[boardIndex] = Board(
          id: board.id,
          name: board.name,
          color: board.color,
          groups: updatedGroups,
        );
        _boards = updatedBoards;
      });
    }

    await _guard(() async {
      await widget.repository.updateTaskPositions(
        tasks.map((task) => task.id).toList(),
      );
    }, failureMessage: 'Could not reorder tasks.');
  }

  Future<void> _openNotes(PlannerTask task) async {
    await showTaskNotesDialog(
      context: context,
      task: task,
      repository: widget.repository,
      members: _members,
      currentUserId: widget.auth.currentUser?.id ?? '',
      canEdit: _canEdit,
    );
    await _refreshBoards();
  }

  void _toggleGroup(TaskGroup group) {
    setState(() {
      if (_collapsedGroupIds.contains(group.id)) {
        _collapsedGroupIds.remove(group.id);
      } else {
        _collapsedGroupIds.add(group.id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final compactSidebar = constraints.maxWidth < 1040;
          // Sidebar spans the full height with the navbar beside it, rather
          // than a bar across the top of everything: the rail is the app's
          // primary frame, and the bar belongs to the content area.
          return Row(
            children: [
              PlannerSidebar(
                workspaces: _workspaces,
                selectedWorkspaceIndex: _selectedWorkspaceIndex,
                boards: _boards,
                selectedBoardIndex: _selectedBoardIndex,
                members: _members,
                loading: _loading,
                compact: compactSidebar,
                onWorkspaceSelected: _switchWorkspace,
                onCreateWorkspace: _createWorkspace,
                onJoinWorkspace: _joinWorkspace,
                onRenameWorkspace: _renameWorkspace,
                onManageMembers: _manageMembers,
                onDeleteWorkspace: _deleteWorkspace,
                onSignOut: _signOut,
                onCreateBoard: _createBoard,
                onRenameBoard: _renameBoard,
                onDeleteBoard: _deleteBoard,
                onBoardSelected: (index) {
                  setState(() {
                    _selectedBoardIndex = index;
                    _query = '';
                    _searchController.clear();
                  });
                },
              ),
              Expanded(
                child: Column(
                  children: [
                    AppNavbar(
                      fullName: _myProfileName,
                      email: widget.auth.currentUser?.email ?? '',
                      invites: _pendingInvites,
                      onAcceptInvite: _acceptInvite,
                      onDeclineInvite: _declineInvite,
                    ),
                    // A brand-new account has no workspace yet. The welcome
                    // sits in the content area so the sidebar stays visible and
                    // the layout does not jump once a workspace exists.
                    if (!_loading && _error == null && _workspaces.isEmpty)
                      Expanded(
                        child: FirstRunWelcome(
                          onGetStarted: _setUpFirstWorkspace,
                          onJoinWorkspace: _joinWorkspace,
                        ),
                      )
                    else
                    Expanded(
                child: _PlannerContent(
                  loading: _loading,
                  workspaceName: _workspace?.name ?? 'your workspace',
                  error: _error,
                  board: _selectedBoard,
                  groups: _visibleGroups,
                  members: _members,
                  collapsedGroupIds: _collapsedGroupIds,
                  mode: _mode,
                  readOnly: !_canEdit,
                  searchController: _searchController,
                  query: _query,
                  onRetry: () {
                    setState(() {
                      _loading = true;
                      _error = null;
                    });
                    _bootstrap();
                  },
                  onSearchChanged: (value) => setState(() => _query = value),
                  onModeChanged: (mode) => setState(() => _mode = mode),
                  taskOrder: _taskOrder,
                  onTaskOrderChanged: (order) =>
                      setState(() => _taskOrder = order),
                  onCreateBoard: _createBoard,
                  onRenameBoard: _renameBoard,
                  onDeleteBoard: _deleteBoard,
                  onAddGroup: _addGroup,
                  onRenameGroup: _renameGroup,
                  onDeleteGroup: _deleteGroup,
                  onToggleGroup: _toggleGroup,
                  onAddTask: _addTask,
                  onEditTask: _editTask,
                  onDeleteTask: _deleteTask,
                  onStatusChanged: _changeStatus,
                  onProgressChanged: _changeProgress,
                  onOpenNotes: _openNotes,
                  onTaskReorder: _reorderTask,
                ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _PlannerContent extends StatelessWidget {
  const _PlannerContent({
    required this.loading,
    required this.error,
    required this.board,
    required this.workspaceName,
    required this.groups,
    required this.members,
    required this.collapsedGroupIds,
    required this.mode,
    required this.readOnly,
    required this.searchController,
    required this.query,
    required this.onRetry,
    required this.onSearchChanged,
    required this.onModeChanged,
    required this.taskOrder,
    required this.onTaskOrderChanged,
    required this.onCreateBoard,
    required this.onRenameBoard,
    required this.onDeleteBoard,
    required this.onAddGroup,
    required this.onRenameGroup,
    required this.onDeleteGroup,
    required this.onToggleGroup,
    required this.onAddTask,
    required this.onEditTask,
    required this.onDeleteTask,
    required this.onStatusChanged,
    required this.onProgressChanged,
    required this.onOpenNotes,
    required this.onTaskReorder,
  });

  final bool loading;
  final String? error;
  final Board? board;
  final String workspaceName;
  final List<TaskGroup> groups;
  final List<WorkspaceMember> members;
  final Set<String> collapsedGroupIds;
  final ViewMode mode;
  final bool readOnly;
  final TextEditingController searchController;
  final String query;
  final VoidCallback onRetry;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<ViewMode> onModeChanged;
  final TaskOrder taskOrder;
  final ValueChanged<TaskOrder> onTaskOrderChanged;
  final VoidCallback onCreateBoard;
  final ValueChanged<Board> onRenameBoard;
  final ValueChanged<Board> onDeleteBoard;
  final VoidCallback onAddGroup;
  final ValueChanged<TaskGroup> onRenameGroup;
  final ValueChanged<TaskGroup> onDeleteGroup;
  final ValueChanged<TaskGroup> onToggleGroup;
  final VoidCallback onAddTask;
  final ValueChanged<PlannerTask> onEditTask;
  final ValueChanged<PlannerTask> onDeleteTask;
  final Future<void> Function(PlannerTask task, TaskStatus status)
  onStatusChanged;
  final Future<void> Function(PlannerTask task, double progress)
  onProgressChanged;
  final ValueChanged<PlannerTask> onOpenNotes;
  final void Function(TaskGroup group, int oldIndex, int newIndex)?
  onTaskReorder;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2.5));
    }
    if (error != null) {
      return _ErrorState(message: error!, onRetry: onRetry);
    }
    if (board == null) {
      return EmptyPlannerState(
        onCreateBoard: onCreateBoard,
        workspaceName: workspaceName,
      );
    }

    return Column(
      children: [
        BoardHeader(
          board: board!,
          members: members,
          readOnly: readOnly,
          searchController: searchController,
          query: query,
          onSearchChanged: onSearchChanged,
          onAddTask: onAddTask,
          onAddGroup: onAddGroup,
          onRenameBoard: () => onRenameBoard(board!),
          onDeleteBoard: () => onDeleteBoard(board!),
        ),
        BoardToolbar(
          mode: mode,
          taskOrder: taskOrder,
          onModeChanged: onModeChanged,
          onTaskOrderChanged: onTaskOrderChanged,
        ),
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            layoutBuilder: (currentChild, previousChildren) {
              return Stack(
                alignment: Alignment.topLeft,
                children: [
                  for (final child in previousChildren)
                    Positioned.fill(child: child),
                  if (currentChild != null)
                    Positioned.fill(child: currentChild),
                ],
              );
            },
            child: switch (mode) {
              ViewMode.table => BoardTable(
                key: ValueKey('table-${board!.id}-$query'),
                groups: groups,
                members: members,
                collapsedGroupIds: collapsedGroupIds,
                onToggleGroup: onToggleGroup,
                onRenameGroup: onRenameGroup,
                onDeleteGroup: onDeleteGroup,
                onEditTask: onEditTask,
                onDeleteTask: onDeleteTask,
                onStatusChanged: onStatusChanged,
                onProgressChanged: onProgressChanged,
                onOpenNotes: onOpenNotes,
                onTaskReorder: taskOrder == TaskOrder.manual
                    ? onTaskReorder
                    : null,
              ),
              ViewMode.kanban => BoardKanban(
                key: ValueKey('kanban-${board!.id}-$query'),
                groups: groups,
                members: members,
                onEditTask: onEditTask,
                onDeleteTask: onDeleteTask,
                onStatusChanged: onStatusChanged,
                onProgressChanged: onProgressChanged,
                onOpenNotes: onOpenNotes,
              ),
              ViewMode.calendar => BoardCalendar(
                key: ValueKey('calendar-${board!.id}-$query'),
                groups: groups,
                members: members,
                onEditTask: onEditTask,
                onDeleteTask: onDeleteTask,
                onStatusChanged: onStatusChanged,
                onProgressChanged: onProgressChanged,
                onOpenNotes: onOpenNotes,
              ),
            },
          ),
        ),
      ],
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: tint(plannerRed, 0.10),
                borderRadius: BorderRadius.circular(radiusLg),
              ),
              child: const Icon(
                Icons.wifi_tethering_error_rounded,
                color: plannerRed,
                size: 21,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Something went wrong',
              style: TextStyle(
                color: plannerInk,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: plannerMuted,
                fontSize: 13,
                height: 1.55,
              ),
            ),
            const SizedBox(height: 18),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}

/// The first thing a new user sees.
///
/// The old version said "No boards yet" and offered a button, which assumes
/// you already know what a board is and how it relates to groups and tasks.
/// This names the three levels, so the empty screen teaches the model instead
/// of just reporting an absence.
class EmptyPlannerState extends StatelessWidget {
  const EmptyPlannerState({
    super.key,
    required this.onCreateBoard,
    required this.workspaceName,
  });

  final VoidCallback onCreateBoard;
  final String workspaceName;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 430),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Names the next action rather than greeting. "Welcome to X" also
            // broke when the workspace name was empty, leaving a dangling
            // "Welcome to" with nothing after it.
            Text(
              workspaceName.trim().isEmpty
                  ? 'Add your first board'
                  : 'Add your first board to $workspaceName',
              style: const TextStyle(
                color: plannerInk,
                fontSize: 21,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'A board holds one project. Work inside it is organised in two '
              'levels:',
              style: TextStyle(color: plannerMuted, fontSize: 13.5, height: 1.55),
            ),
            const SizedBox(height: 22),

            const _ConceptRow(
              icon: Icons.dashboard_outlined,
              color: plannerBlue,
              title: 'Boards',
              detail: 'One per project, team or client.',
            ),
            const _ConceptRow(
              icon: Icons.segment_rounded,
              color: plannerViolet,
              title: 'Groups',
              detail: 'Phases or categories inside a board.',
            ),
            const _ConceptRow(
              icon: Icons.check_circle_outline_rounded,
              color: plannerGreen,
              title: 'Tasks',
              detail: 'The actual work, with owners, dates and status.',
              last: true,
            ),

            const SizedBox(height: 24),
            Row(
              children: [
                FilledButton.icon(
                  onPressed: onCreateBoard,
                  icon: const Icon(Icons.add_rounded, size: 16),
                  label: const Text('Create your first board'),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'You can also use + beside BOARDS in the sidebar.',
                    style: TextStyle(color: plannerFaint, fontSize: 12, height: 1.4),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// One line of the three-level explanation.
class _ConceptRow extends StatelessWidget {
  const _ConceptRow({
    required this.icon,
    required this.color,
    required this.title,
    required this.detail,
    this.last = false,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String detail;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: tint(color, 0.10),
              borderRadius: BorderRadius.circular(radiusMd),
            ),
            child: Icon(icon, color: color, size: 16),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: plannerInk,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  detail,
                  style: const TextStyle(
                    color: plannerMuted,
                    fontSize: 12.5,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// What a brand-new account sees in the content area before any workspace
/// exists.
///
/// Replaces the previous behaviour, which created a workspace silently and —
/// when that failed — showed "Something went wrong" as the very first screen.
/// A first-time user needs to be told what a workspace is and given clear
/// choices, not handed an error about permissions they have never heard of.
class FirstRunWelcome extends StatelessWidget {
  const FirstRunWelcome({
    super.key,
    required this.onGetStarted,
    required this.onJoinWorkspace,
  });

  final VoidCallback onGetStarted;
  final VoidCallback onJoinWorkspace;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(40),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Welcome to Planner',
                style: TextStyle(
                  color: plannerInk,
                  fontSize: 25,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.7,
                ),
              ),
              const SizedBox(height: 9),
              const Text(
                'Start your own workspace, or join one a teammate has already '
                'set up with their code.',
                style: TextStyle(
                  color: plannerMuted,
                  fontSize: 14,
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 26),
              const Text(
                'HOW IT FITS TOGETHER',
                style: TextStyle(
                  color: plannerFaint,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 10),

              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: plannerCard,
                  borderRadius: BorderRadius.circular(radiusLg),
                  border: Border.all(color: plannerBorder),
                ),
                child: const Column(
                  children: [
                    _ConceptRow(
                      icon: Icons.groups_outlined,
                      color: plannerViolet,
                      title: 'Workspace',
                      detail: 'Your team. People join this — and then see '
                          'every board inside it.',
                    ),
                    _ConceptRow(
                      icon: Icons.dashboard_outlined,
                      color: plannerBlue,
                      title: 'Boards',
                      detail: 'One project each, inside the workspace.',
                    ),
                    _ConceptRow(
                      icon: Icons.check_circle_outline_rounded,
                      color: plannerGreen,
                      title: 'Groups and tasks',
                      detail: 'Phases inside a board, and the work itself.',
                      last: true,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),
              Row(
                children: [
                  SizedBox(
                    height: 44,
                    child: FilledButton.icon(
                      onPressed: onGetStarted,
                      icon: const Icon(Icons.add_rounded, size: 17),
                      label: const Text('Create a workspace'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    height: 44,
                    child: OutlinedButton.icon(
                      onPressed: onJoinWorkspace,
                      icon: const Icon(Icons.login_rounded, size: 16),
                      label: const Text('Join with a code'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              const Text(
                'Creating a workspace also adds your first board, so you can '
                'start straight away.',
                style: TextStyle(color: plannerFaint, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
