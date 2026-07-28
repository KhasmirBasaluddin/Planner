import 'package:flutter/material.dart';

import '../../core/drift/app_database.dart' show AppDatabase;
import '../../models/planner_models.dart';
import '../../shared/utils/planner_colors.dart';
import '../notes/notes_canvas_page.dart';
import 'widgets/board_calendar.dart';
import 'widgets/board_header.dart';
import 'widgets/board_kanban.dart';
import 'widgets/board_table.dart';
import 'widgets/board_toolbar.dart';
import 'widgets/planner_dialogs.dart';
import 'widgets/planner_sidebar.dart';

class PlannerPage extends StatefulWidget {
  const PlannerPage({super.key, required this.database});

  final AppDatabase database;

  @override
  State<PlannerPage> createState() => _PlannerPageState();
}

class _PlannerPageState extends State<PlannerPage> {
  final TextEditingController _searchController = TextEditingController();
  final Set<int> _collapsedGroupIds = <int>{};
  List<Board> _boards = [];
  int _selectedBoardIndex = 0;
  String _query = '';
  ViewMode _mode = ViewMode.table;
  TaskOrder _taskOrder = TaskOrder.manual;
  WorkspaceView _view = WorkspaceView.board;
  int _noteCount = 0;
  bool _loading = true;
  String? _error;

  Board? get _selectedBoard {
    if (_boards.isEmpty) {
      return null;
    }
    return _boards[_selectedBoardIndex.clamp(0, _boards.length - 1)];
  }

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
        ordered.sort(
          (a, b) =>
              _priorityRank(a.priority).compareTo(_priorityRank(b.priority)),
        );
      case TaskOrder.status:
        ordered.sort(
          (a, b) => _statusRank(a.status).compareTo(_statusRank(b.status)),
        );
    }
    return ordered;
  }

  int _compareDueDate(PlannerTask a, PlannerTask b) {
    final aMissing = a.dueDate == 'No date';
    final bMissing = b.dueDate == 'No date';
    if (aMissing != bMissing) {
      return aMissing ? 1 : -1;
    }
    return a.dueDate.toLowerCase().compareTo(b.dueDate.toLowerCase());
  }

  int _priorityRank(TaskPriority priority) {
    return switch (priority) {
      TaskPriority.high => 0,
      TaskPriority.medium => 1,
      TaskPriority.low => 2,
    };
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
    _loadBoards();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadBoards() async {
    try {
      final boards = await widget.database.loadBoards();
      final noteCount = (await widget.database.loadStickyNotes()).length;
      if (!mounted) {
        return;
      }
      setState(() {
        _boards = boards;
        _noteCount = noteCount;
        _selectedBoardIndex = _selectedBoardIndex.clamp(
          0,
          boards.isEmpty ? 0 : boards.length - 1,
        );
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  /// Runs a database mutation, surfacing any failure as a snackbar instead of
  /// silently swallowing it. Returns true on success.
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
              behavior: SnackBarBehavior.floating,
              backgroundColor: plannerRed,
              content: Text(failureMessage ?? 'Something went wrong: $error'),
            ),
          );
      }
      return false;
    }
  }

  Future<void> _createBoard() async {
    final result = await showNameDialog(
      context: context,
      title: 'New board',
      label: 'Board name',
      initialValue: 'New board ${_boards.length + 1}',
    );
    if (result == null) {
      return;
    }

    int? boardId;
    final ok = await _guard(() async {
      boardId = await widget.database.createBoard(
        name: result.name,
        color: result.color,
      );
      await _loadBoards();
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
    final result = await showNameDialog(
      context: context,
      title: 'Edit board',
      label: 'Board name',
      initialValue: board.name,
      initialColor: board.color,
    );
    if (result == null) {
      return;
    }

    await _guard(() async {
      await widget.database.updateBoardName(
        boardId: board.id,
        name: result.name,
      );
      await widget.database.updateBoardColor(
        boardId: board.id,
        color: result.color,
      );
      await _loadBoards();
    }, failureMessage: 'Could not save the board.');
  }

  Future<void> _deleteBoard(Board board) async {
    final confirmed = await showDeleteConfirmDialog(
      context: context,
      title: 'Delete board',
      message:
          'Delete "${board.name}" and all groups and tasks inside it? This cannot be undone.',
    );
    if (!confirmed) {
      return;
    }

    await _guard(() async {
      await widget.database.deleteBoard(board.id);
      await _loadBoards();
    }, failureMessage: 'Could not delete the board.');
  }

  Future<void> _addGroup() async {
    final board = _selectedBoard;
    if (board == null) {
      return;
    }

    final result = await showNameDialog(
      context: context,
      title: 'New group',
      label: 'Group name',
      initialValue: 'New group ${board.groups.length + 1}',
    );
    if (result == null) {
      return;
    }

    await _guard(() async {
      await widget.database.createGroup(
        boardId: board.id,
        name: result.name,
        color: result.color,
      );
      await _loadBoards();
    }, failureMessage: 'Could not create the group.');
  }

  Future<void> _renameGroup(TaskGroup group) async {
    final result = await showNameDialog(
      context: context,
      title: 'Edit group',
      label: 'Group name',
      initialValue: group.name,
      initialColor: group.color,
    );
    if (result == null) {
      return;
    }

    await _guard(() async {
      await widget.database.updateGroupName(
        groupId: group.id,
        name: result.name,
      );
      await widget.database.updateGroupColor(
        groupId: group.id,
        color: result.color,
      );
      await _loadBoards();
    }, failureMessage: 'Could not save the group.');
  }

  Future<void> _deleteGroup(TaskGroup group) async {
    final confirmed = await showDeleteConfirmDialog(
      context: context,
      title: 'Delete group',
      message:
          'Delete "${group.name}" and all tasks inside it? This cannot be undone.',
    );
    if (!confirmed) {
      return;
    }

    await _guard(() async {
      await widget.database.deleteGroup(group.id);
      _collapsedGroupIds.remove(group.id);
      await _loadBoards();
    }, failureMessage: 'Could not delete the group.');
  }

  Future<void> _addTask() async {
    final board = _selectedBoard;
    if (board == null || board.groups.isEmpty) {
      return;
    }

    final result = await showTaskDialog(context: context, groups: board.groups);
    if (result == null) {
      return;
    }

    final group = board.groups.firstWhere(
      (group) => group.id == result.groupId,
    );
    await _guard(() async {
      await widget.database.addTask(
        groupId: result.groupId,
        title: result.title,
        owner: result.owner,
        status: result.status,
        priority: result.priority,
        dueDate: result.dueDate,
        timeline: result.timeline,
        progress: result.progress,
        position: group.tasks.length,
      );
      await _loadBoards();
    }, failureMessage: 'Could not create the task.');
  }

  Future<void> _editTask(PlannerTask task) async {
    final board = _selectedBoard;
    if (board == null || board.groups.isEmpty) {
      return;
    }

    final result = await showTaskDialog(
      context: context,
      groups: board.groups,
      task: task,
    );
    if (result == null) {
      return;
    }

    await _guard(() async {
      await widget.database.updateTask(
        task: task,
        groupId: result.groupId,
        title: result.title,
        owner: result.owner,
        status: result.status,
        priority: result.priority,
        dueDate: result.dueDate,
        timeline: result.timeline,
        progress: result.progress,
      );
      await _loadBoards();
    }, failureMessage: 'Could not save the task.');
  }

  Future<void> _deleteTask(PlannerTask task) async {
    final confirmed = await showDeleteConfirmDialog(
      context: context,
      title: 'Delete task',
      message: 'Delete "${task.title}"? This cannot be undone.',
    );
    if (!confirmed) {
      return;
    }

    await _guard(() async {
      await widget.database.deleteTask(task.id);
      await _loadBoards();
    }, failureMessage: 'Could not delete the task.');
  }

  Future<void> _changeStatus(PlannerTask task, TaskStatus status) async {
    await _guard(() async {
      await widget.database.updateTaskStatus(task, status);
      await _loadBoards();
    }, failureMessage: 'Could not update the status.');
  }

  Future<void> _changeProgress(PlannerTask task, double progress) async {
    await _guard(() async {
      await widget.database.updateTaskProgress(task, progress);
      await _loadBoards();
    }, failureMessage: 'Could not update the progress.');
  }

  Future<void> _reorderTask(TaskGroup group, int oldIndex, int newIndex) async {
    if (_taskOrder != TaskOrder.manual) {
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
      await widget.database.updateTaskPositions(
        group.id,
        tasks.map((task) => task.id).toList(),
      );
    }, failureMessage: 'Could not reorder tasks.');
  }

  Future<void> _changeNotes(PlannerTask task, List<String> notes) async {
    await _guard(() async {
      await widget.database.updateTaskNotes(task, notes);
      await _loadBoards();
    }, failureMessage: 'Could not save the notes.');
  }

  /// Creates a sticky note on the Notes canvas seeded from a task, keeping a
  /// link back to it.
  Future<void> _pinTaskToNotes(PlannerTask task) async {
    // Spread pinned notes over a loose grid so several never land on top of
    // each other.
    final slot = _noteCount;
    final x = 80.0 + (slot % 5) * 290.0;
    final y = 80.0 + (slot ~/ 5) * 270.0;

    final ok = await _guard(() async {
      await widget.database.createStickyNote(
        x: x,
        y: y,
        color: notePalette[slot % notePalette.length],
        title: task.title,
        taskId: task.id,
      );
      await _loadBoards();
    }, failureMessage: 'Could not pin the task to Notes.');

    if (!ok || !mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('Pinned "${task.title}" to Notes'),
          action: SnackBarAction(
            label: 'View',
            onPressed: () => setState(() => _view = WorkspaceView.notes),
          ),
        ),
      );
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
          final compactSidebar = constraints.maxWidth < 980;
          final board = _selectedBoard;

          return Row(
            children: [
              PlannerSidebar(
                boards: _boards,
                selectedBoardIndex: _selectedBoardIndex,
                compact: compactSidebar,
                view: _view,
                noteCount: _noteCount,
                onCreateBoard: _createBoard,
                onRenameBoard: _renameBoard,
                onDeleteBoard: _deleteBoard,
                onNotesSelected: () {
                  setState(() => _view = WorkspaceView.notes);
                },
                onBoardSelected: (index) {
                  setState(() {
                    _view = WorkspaceView.board;
                    _selectedBoardIndex = index;
                    _query = '';
                    _searchController.clear();
                  });
                },
              ),
              if (_view == WorkspaceView.notes)
                Expanded(
                  child: NotesCanvasPage(
                    database: widget.database,
                    // Keep the sidebar badge accurate as notes are added or
                    // removed on the canvas.
                    onNotesChanged: (count) {
                      if (mounted && count != _noteCount) {
                        setState(() => _noteCount = count);
                      }
                    },
                  ),
                )
              else
                Expanded(
                  child: _PlannerContent(
                    loading: _loading,
                    error: _error,
                    board: board,
                    groups: _visibleGroups,
                    collapsedGroupIds: _collapsedGroupIds,
                    mode: _mode,
                    searchController: _searchController,
                    query: _query,
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
                    onNotesChanged: _changeNotes,
                    onTaskReorder: _reorderTask,
                    onPinTaskToNotes: _pinTaskToNotes,
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
    required this.groups,
    required this.collapsedGroupIds,
    required this.mode,
    required this.searchController,
    required this.query,
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
    required this.onNotesChanged,
    required this.onTaskReorder,
    required this.onPinTaskToNotes,
  });

  final bool loading;
  final String? error;
  final Board? board;
  final List<TaskGroup> groups;
  final Set<int> collapsedGroupIds;
  final ViewMode mode;
  final TextEditingController searchController;
  final String query;
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
  final Future<void> Function(PlannerTask task, List<String> notes)
  onNotesChanged;
  final void Function(TaskGroup group, int oldIndex, int newIndex)?
  onTaskReorder;
  final ValueChanged<PlannerTask> onPinTaskToNotes;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (error != null) {
      return Center(
        child: Text(error!, style: const TextStyle(color: plannerRed)),
      );
    }
    if (board == null) {
      return EmptyPlannerState(onCreateBoard: onCreateBoard);
    }

    return Column(
      children: [
        BoardHeader(
          board: board!,
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
            duration: const Duration(milliseconds: 240),
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
                collapsedGroupIds: collapsedGroupIds,
                onToggleGroup: onToggleGroup,
                onRenameGroup: onRenameGroup,
                onDeleteGroup: onDeleteGroup,
                onEditTask: onEditTask,
                onDeleteTask: onDeleteTask,
                onStatusChanged: onStatusChanged,
                onProgressChanged: onProgressChanged,
                onNotesChanged: onNotesChanged,
                onPinTaskToNotes: onPinTaskToNotes,
                onTaskReorder: taskOrder == TaskOrder.manual
                    ? onTaskReorder
                    : null,
              ),
              ViewMode.kanban => BoardKanban(
                key: ValueKey('kanban-${board!.id}-$query'),
                groups: groups,
                onEditTask: onEditTask,
                onDeleteTask: onDeleteTask,
                onStatusChanged: onStatusChanged,
                onProgressChanged: onProgressChanged,
                onNotesChanged: onNotesChanged,
              ),
              ViewMode.calendar => BoardCalendar(
                key: ValueKey('calendar-${board!.id}-$query'),
                groups: groups,
                onEditTask: onEditTask,
                onDeleteTask: onDeleteTask,
                onStatusChanged: onStatusChanged,
                onProgressChanged: onProgressChanged,
                onNotesChanged: onNotesChanged,
              ),
            },
          ),
        ),
      ],
    );
  }
}

class EmptyPlannerState extends StatelessWidget {
  const EmptyPlannerState({super.key, required this.onCreateBoard});

  final VoidCallback onCreateBoard;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'No boards yet',
            style: TextStyle(
              color: plannerInk,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Create a board to start organizing tasks.',
            textAlign: TextAlign.center,
            style: TextStyle(color: plannerMuted, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onCreateBoard,
            icon: const Icon(Icons.add_rounded, size: 16),
            label: const Text('New board'),
          ),
        ],
      ),
    );
  }
}


