import 'package:flutter/material.dart';

import '../../../models/planner_models.dart';
import '../../../shared/utils/planner_colors.dart';
import '../../../shared/widgets/user_avatar.dart';
import 'planner_dialogs.dart';

/// Below this even the reduced column set scrolls horizontally rather than
/// compressing further — with only Task, Status and Due left, 520px still
/// gives the status pill the ~100px "Working on it" needs.
const double _minTableWidth = 520;
const double _rowHeight = 54;

/// Which optional columns fit at the current width.
///
/// The table used to hold a 900px minimum and scroll sideways below it, which
/// made it the one view that did not adapt. Instead the least essential
/// columns now step aside one at a time: the timeline first (progress still
/// shows in the task dialog), then the owner avatars, then priority. Task,
/// Status and Due survive to the end — they are what a table row *is*.
class TableColumns {
  const TableColumns({
    this.owner = true,
    this.priority = true,
    this.timeline = true,
  });

  factory TableColumns.forWidth(double width) => TableColumns(
    timeline: width >= 840,
    owner: width >= 720,
    priority: width >= 620,
  );

  final bool owner;
  final bool priority;
  final bool timeline;
}

class BoardTable extends StatefulWidget {
  const BoardTable({
    super.key,
    required this.groups,
    required this.members,
    required this.statuses,
    required this.collapsedGroupIds,
    required this.onToggleGroup,
    required this.onRenameGroup,
    required this.onDeleteGroup,
    required this.onEditTask,
    required this.onDeleteTask,
    required this.onStatusChanged,
    required this.onProgressChanged,
    required this.onOpenChat,
    this.onTaskReorder,
    this.highlightedTaskId,
    this.highlightKey,
  });

  final List<TaskGroup> groups;
  final List<WorkspaceMember> members;

  /// The task the attention banner just revealed, if any. Its row lights up
  /// and carries [highlightKey] so the page can scroll it into view.
  final String? highlightedTaskId;
  final GlobalKey? highlightKey;

  /// The board's statuses, in display order — the choices the status menu
  /// offers and the source for resolving a task's label.
  final List<StatusLabel> statuses;
  final Set<String> collapsedGroupIds;
  final ValueChanged<TaskGroup> onToggleGroup;
  final ValueChanged<TaskGroup> onRenameGroup;
  final ValueChanged<TaskGroup> onDeleteGroup;
  final ValueChanged<PlannerTask> onEditTask;
  final ValueChanged<PlannerTask> onDeleteTask;
  final Future<void> Function(PlannerTask task, StatusLabel status)
  onStatusChanged;
  final Future<void> Function(PlannerTask task, double progress)
  onProgressChanged;
  final ValueChanged<PlannerTask> onOpenChat;
  final void Function(TaskGroup group, int oldIndex, int newIndex)?
  onTaskReorder;

  @override
  State<BoardTable> createState() => _BoardTableState();
}

class _BoardTableState extends State<BoardTable> {
  final ScrollController _verticalController = ScrollController();

  /// The first group containing the highlighted task, or -1. Only that group
  /// is handed the highlight key — see the comment at its use site.
  int get _highlightGroupIndex {
    final id = widget.highlightedTaskId;
    if (id == null) {
      return -1;
    }
    return widget.groups.indexWhere(
      (group) => group.tasks.any((task) => task.id == id),
    );
  }

  @override
  void dispose() {
    _verticalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.groups.isEmpty) {
      return const Center(
        child: Text(
          'No tasks match your search.',
          style: TextStyle(color: plannerMuted, fontSize: 14),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontalPadding = constraints.maxWidth < 720 ? 16.0 : 28.0;
        final availableWidth = constraints.maxWidth - horizontalPadding * 2;
        final tableWidth = availableWidth < _minTableWidth
            ? _minTableWidth
            : availableWidth;
        final columns = TableColumns.forWidth(tableWidth);

        return Scrollbar(
          controller: _verticalController,
          thumbVisibility: true,
          child: SingleChildScrollView(
            controller: _verticalController,
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              20,
              horizontalPadding,
              40,
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: tableWidth,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TableHeader(columns: columns),
                    const SizedBox(height: 10),
                    for (final entry in widget.groups.indexed) ...[
                      GroupSection(
                        group: entry.$2,
                        columns: columns,
                        members: widget.members,
                        statuses: widget.statuses,
                        collapsed: widget.collapsedGroupIds.contains(
                          entry.$2.id,
                        ),
                        onToggle: () => widget.onToggleGroup(entry.$2),
                        onRename: () => widget.onRenameGroup(entry.$2),
                        onDelete: () => widget.onDeleteGroup(entry.$2),
                        onEditTask: widget.onEditTask,
                        onDeleteTask: widget.onDeleteTask,
                        onStatusChanged: widget.onStatusChanged,
                        onProgressChanged: widget.onProgressChanged,
                        onOpenChat: widget.onOpenChat,
                        onTaskReorder: widget.onTaskReorder,
                        highlightedTaskId: widget.highlightedTaskId,
                        // Only the first group holding the task carries the
                        // key. Grouping by assignee puts a task shared by two
                        // people into both groups, and two widgets claiming
                        // one GlobalKey tears the tree apart.
                        highlightKey: entry.$1 == _highlightGroupIndex
                            ? widget.highlightKey
                            : null,
                      ),
                      const SizedBox(height: 22),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class TableHeader extends StatelessWidget {
  const TableHeader({super.key, this.columns = const TableColumns()});

  final TableColumns columns;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FB),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: plannerBorder),
      ),
      child: Row(
        children: [
          const _HeaderCell(flex: 36, label: 'Task'),
          if (columns.owner) const _HeaderCell(flex: 8, label: 'Owner'),
          const _HeaderCell(flex: 13, label: 'Status'),
          if (columns.priority) const _HeaderCell(flex: 12, label: 'Priority'),
          const _HeaderCell(flex: 9, label: 'Due'),
          if (columns.timeline) const _HeaderCell(flex: 16, label: 'Timeline'),
          const _HeaderCell(flex: 5, label: ''),
        ],
      ),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  const _HeaderCell({required this.flex, required this.label});

  final int flex;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Align(
          alignment: label == 'Actions'
              ? Alignment.centerRight
              : Alignment.centerLeft,
          child: Text(
            label.toUpperCase(),
            style: const TextStyle(
              color: plannerMuted,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.4,
            ),
          ),
        ),
      ),
    );
  }
}

class GroupSection extends StatelessWidget {
  const GroupSection({
    super.key,
    required this.group,
    this.columns = const TableColumns(),
    required this.members,
    required this.statuses,
    required this.collapsed,
    required this.onToggle,
    required this.onRename,
    required this.onDelete,
    required this.onEditTask,
    required this.onDeleteTask,
    required this.onStatusChanged,
    required this.onProgressChanged,
    required this.onOpenChat,
    this.onTaskReorder,
    this.highlightedTaskId,
    this.highlightKey,
  });

  final TaskGroup group;
  final TableColumns columns;
  final List<WorkspaceMember> members;
  final List<StatusLabel> statuses;
  final bool collapsed;
  final String? highlightedTaskId;
  final GlobalKey? highlightKey;
  final VoidCallback onToggle;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final ValueChanged<PlannerTask> onEditTask;
  final ValueChanged<PlannerTask> onDeleteTask;
  final Future<void> Function(PlannerTask task, StatusLabel status)
  onStatusChanged;
  final Future<void> Function(PlannerTask task, double progress)
  onProgressChanged;
  final ValueChanged<PlannerTask> onOpenChat;
  final void Function(TaskGroup group, int oldIndex, int newIndex)?
  onTaskReorder;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: plannerBorder),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0A101828),
              blurRadius: 2,
              offset: Offset(0, 1),
            ),
          ],
        ),
        child: Column(
          children: [
            Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: const BoxDecoration(
                borderRadius: BorderRadius.vertical(top: Radius.circular(6)),
              ),
              child: Row(
                children: [
                  IconButton(
                    tooltip: collapsed ? 'Expand group' : 'Collapse group',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(
                      width: 28,
                      height: 28,
                    ),
                    onPressed: onToggle,
                    icon: Icon(
                      collapsed
                          ? Icons.keyboard_arrow_right_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      color: plannerMuted,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: group.color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    group.name,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: plannerInk,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${group.tasks.length}',
                    style: const TextStyle(color: plannerMuted, fontSize: 12),
                  ),
                  const Spacer(),
                  _ActionsMenu(
                    tooltip: 'Group actions',
                    onEdit: onRename,
                    onDelete: onDelete,
                    editLabel: 'Edit group',
                    deleteLabel: 'Delete group',
                  ),
                ],
              ),
            ),
            if (!collapsed)
              // .builder, not a children list. The list form constructs every
              // row up front, so a board with a few hundred tasks built all of
              // them on every rebuild whether or not they were on screen —
              // the main reason a large board felt sluggish. itemExtent lets
              // the viewport skip straight to the rows it needs.
              ReorderableListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                buildDefaultDragHandles: false,
                itemExtent: _rowHeight,
                proxyDecorator: _buildDragProxy,
                onReorder: onTaskReorder == null
                    ? (_, _) {}
                    : (oldIndex, newIndex) =>
                          onTaskReorder!(group, oldIndex, newIndex),
                itemCount: group.tasks.length,
                itemBuilder: (context, index) {
                  final task = group.tasks[index];
                  final highlighted = task.id == highlightedTaskId;
                  return RepaintBoundary(
                    key: ValueKey(task.id),
                    child: TaskRow(
                      task: task,
                      columns: columns,
                      rowIndex: index,
                      groupColor: group.color,
                      members: members,
                      statuses: statuses,
                      onEditTask: onEditTask,
                      onDeleteTask: onDeleteTask,
                      onStatusChanged: onStatusChanged,
                      onProgressChanged: onProgressChanged,
                      onOpenChat: onOpenChat,
                      dragEnabled: onTaskReorder != null,
                      highlighted: highlighted,
                      highlightKey: highlighted ? highlightKey : null,
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

Widget _buildDragProxy(Widget child, int index, Animation<double> animation) {
  return AnimatedBuilder(
    animation: animation,
    builder: (context, _) {
      final value = Curves.easeOutCubic.transform(animation.value);
      return Transform.scale(
        scale: 1 + value * 0.018,
        child: Material(
          color: Colors.white,
          elevation: 14 * value,
          shadowColor: Colors.black.withValues(alpha: 0.18 * value),
          borderRadius: BorderRadius.circular(8),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: child,
          ),
        ),
      );
    },
  );
}

class TaskRow extends StatelessWidget {
  const TaskRow({
    super.key,
    required this.task,
    this.columns = const TableColumns(),
    required this.rowIndex,
    required this.groupColor,
    required this.members,
    required this.statuses,
    required this.onEditTask,
    required this.onDeleteTask,
    required this.onStatusChanged,
    required this.onProgressChanged,
    required this.onOpenChat,
    required this.dragEnabled,
    this.highlighted = false,
    this.highlightKey,
  });

  final PlannerTask task;
  final TableColumns columns;
  final int rowIndex;
  final Color groupColor;

  /// True while the attention banner is pointing at this row; it tints the
  /// row and, via [highlightKey], lets the page scroll it into view.
  final bool highlighted;
  final GlobalKey? highlightKey;
  final List<WorkspaceMember> members;
  final List<StatusLabel> statuses;
  final ValueChanged<PlannerTask> onEditTask;
  final ValueChanged<PlannerTask> onDeleteTask;
  final Future<void> Function(PlannerTask task, StatusLabel status)
  onStatusChanged;
  final Future<void> Function(PlannerTask task, double progress)
  onProgressChanged;
  final ValueChanged<PlannerTask> onOpenChat;
  final bool dragEnabled;

  @override
  Widget build(BuildContext context) {
    final status = statusById(statuses, task.statusId);
    final row = AnimatedContainer(
      duration: const Duration(milliseconds: 350),
      height: _rowHeight,
      decoration: BoxDecoration(
        color: highlighted
            ? Color.alphaBlend(tint(plannerBlue, 0.12), Colors.white)
            : Colors.white,
        border: const Border(top: BorderSide(color: Color(0xFFEDEFF5))),
      ),
      child: Row(
        children: [
          Container(width: 3, color: groupColor),
          Expanded(
            flex: 36,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  dragEnabled
                      ? ReorderableDragStartListener(
                          index: rowIndex,
                          child: const _DragHandle(),
                        )
                      : const _DragHandle(),
                  const SizedBox(width: 8),
                  Expanded(
                    // The full title on hover, for rows narrow enough to
                    // ellipsize it.
                    child: Tooltip(
                      message: task.title,
                      waitDuration: const Duration(milliseconds: 700),
                      child: Text(
                        task.title,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: plannerInk,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ChatButton(task: task, onOpenChat: onOpenChat),
                  const SizedBox(width: 4),
                ],
              ),
            ),
          ),
          if (columns.owner)
            Expanded(
              flex: 8,
              child: Center(
                child: AssigneeAvatars(task: task, members: members),
              ),
            ),
          Expanded(
            flex: 13,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: StatusMenu(
                task: task,
                status: status,
                statuses: statuses,
                onChanged: onStatusChanged,
              ),
            ),
          ),
          if (columns.priority)
            Expanded(
              flex: 12,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: PriorityPill(priority: task.priority),
              ),
            ),
          Expanded(
            flex: 9,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: DueDateCell(task: task, status: status),
            ),
          ),
          if (columns.timeline)
            Expanded(
              flex: 16,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: TimelineCell(
                  task: task,
                  status: status,
                  onProgressChanged: (progress) {
                    onProgressChanged(task, progress);
                  },
                ),
              ),
            ),
          Expanded(
            flex: 5,
            child: Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(right: 10),
                child: _ActionsMenu(
                  tooltip: 'Task actions',
                  onEdit: () => onEditTask(task),
                  onDelete: () => onDeleteTask(task),
                  editLabel: 'Edit task',
                  deleteLabel: 'Delete task',
                ),
              ),
            ),
          ),
        ],
      ),
    );

    final key = highlightKey;
    return key == null ? row : KeyedSubtree(key: key, child: row);
  }
}

class _DragHandle extends StatelessWidget {
  const _DragHandle();

  @override
  Widget build(BuildContext context) {
    return const Tooltip(
      message: 'Drag to reorder',
      waitDuration: Duration(milliseconds: 500),
      child: MouseRegion(
        cursor: SystemMouseCursors.grab,
        child: SizedBox(
          width: 22,
          height: 34,
          child: Icon(
            Icons.drag_indicator_rounded,
            color: Color(0xFFC3C8D6),
            size: 16,
          ),
        ),
      ),
    );
  }
}

/// The people on a task, or a muted placeholder when it is unassigned.
///
/// Assignments are stored as ids, so anyone no longer in the workspace simply
/// drops out of the row rather than showing as a stale name.
class AssigneeAvatars extends StatelessWidget {
  const AssigneeAvatars({
    super.key,
    required this.task,
    required this.members,
    this.size = 26,
    this.maxVisible = 2,
  });

  final PlannerTask task;
  final List<WorkspaceMember> members;
  final double size;
  final int maxVisible;

  @override
  Widget build(BuildContext context) {
    final profiles = assigneeProfiles(task, members);
    if (profiles.isEmpty) {
      return _UnassignedAvatar(size: size);
    }
    return AvatarStack(profiles: profiles, size: size, maxVisible: maxVisible);
  }
}

class _UnassignedAvatar extends StatelessWidget {
  const _UnassignedAvatar({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Unassigned',
      child: Container(
        width: size,
        height: size,
        decoration: const BoxDecoration(
          color: Color(0xFFE9EBF1),
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Icon(
          Icons.person_outline_rounded,
          color: plannerFaint,
          size: size * 0.58,
        ),
      ),
    );
  }
}

class StatusMenu extends StatelessWidget {
  const StatusMenu({
    super.key,
    required this.task,
    required this.status,
    required this.statuses,
    required this.onChanged,
  });

  final PlannerTask task;

  /// The task's current label, already resolved. Null when the board deleted
  /// the label the task pointed at.
  final StatusLabel? status;
  final List<StatusLabel> statuses;
  final Future<void> Function(PlannerTask task, StatusLabel status) onChanged;

  @override
  Widget build(BuildContext context) {
    final color = statusColor(status);
    return Align(
      alignment: Alignment.centerLeft,
      child: PopupMenuButton<StatusLabel>(
        tooltip: 'Change status',
        onSelected: (choice) => onChanged(task, choice),
        itemBuilder: (context) => statuses.map((choice) {
          return PopupMenuItem(
            value: choice,
            height: 38,
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: statusColor(choice),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  choice.name,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
        child: Container(
          height: 26,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              // Flexible, so a long label ellipsizes instead of pushing the
              // pill past its column. "Working on it" is wider than the status
              // column at narrow window widths, and with a bare Text the Row
              // simply overflowed and painted the stripe across the row.
              Flexible(
                child: Text(
                  status?.name ?? 'No status',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Color.lerp(color, plannerInk, 0.25),
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PriorityPill extends StatelessWidget {
  const PriorityPill({super.key, required this.priority});

  final TaskPriority priority;

  @override
  Widget build(BuildContext context) {
    final color = priorityColor(priority);
    return Align(
      alignment: Alignment.centerLeft,
      child: Tooltip(
        message: 'Priority: ${priority.label} — change it by editing the task',
        child: Container(
          height: 26,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(5),
            border: Border.all(color: plannerBorder),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.flag_rounded, size: 11, color: color),
              const SizedBox(width: 5),
              // Same reason as the status pill: "Medium" and "Urgent" outgrow
              // the priority column before the window gets especially narrow.
              Flexible(
                child: Text(
                  priority.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: plannerText,
                    fontWeight: FontWeight.w500,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class TimelineCell extends StatelessWidget {
  const TimelineCell({
    super.key,
    required this.task,
    required this.status,
    this.onProgressChanged,
  });

  final PlannerTask task;
  final StatusLabel? status;
  final ValueChanged<double>? onProgressChanged;

  @override
  Widget build(BuildContext context) {
    final progressPercent = (task.progress * 100).round();
    final progressColor = statusColor(status);
    final content = Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(6)),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _timelineLabel(task),
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: task.startDate == null && task.endDate == null
                        ? plannerFaint
                        : plannerMuted,
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '$progressPercent%',
                style: const TextStyle(
                  color: plannerText,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: task.progress,
              minHeight: 4,
              backgroundColor: const Color(0xFFE8EAF1),
              valueColor: AlwaysStoppedAnimation<Color>(progressColor),
            ),
          ),
        ],
      ),
    );

    if (onProgressChanged == null) {
      return content;
    }

    return Tooltip(
      message: 'Update progress',
      waitDuration: const Duration(milliseconds: 650),
      preferBelow: false,
      verticalOffset: 16,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: () => _showProgressDialog(context),
          mouseCursor: SystemMouseCursors.click,
          borderRadius: BorderRadius.circular(8),
          hoverColor: progressColor.withValues(alpha: 0.08),
          highlightColor: progressColor.withValues(alpha: 0.10),
          splashColor: progressColor.withValues(alpha: 0.14),
          child: content,
        ),
      ),
    );
  }

  void _showProgressDialog(BuildContext context) async {
    final newProgress = await showDialog<double>(
      context: context,
      builder: (context) => _ProgressDialog(currentProgress: task.progress),
    );
    if (newProgress != null) {
      onProgressChanged?.call(newProgress);
    }
  }
}

class _ProgressDialog extends StatefulWidget {
  const _ProgressDialog({required this.currentProgress});

  final double currentProgress;

  @override
  State<_ProgressDialog> createState() => _ProgressDialogState();
}

class _ProgressDialogState extends State<_ProgressDialog> {
  late double _progress;

  @override
  void initState() {
    super.initState();
    _progress = widget.currentProgress;
  }

  @override
  Widget build(BuildContext context) {
    final percent = (_progress * 100).round();
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 18, 24, 8),
      actionsPadding: const EdgeInsets.fromLTRB(24, 4, 24, 16),
      title: const Text(
        'Update progress',
        style: TextStyle(
          color: plannerInk,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    '$percent',
                    style: const TextStyle(
                      color: plannerInk,
                      fontSize: 40,
                      fontWeight: FontWeight.w600,
                      height: 1,
                      letterSpacing: -1,
                    ),
                  ),
                  const Text(
                    '%',
                    style: TextStyle(
                      color: plannerMuted,
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 5,
                activeTrackColor: plannerBlue,
                inactiveTrackColor: const Color(0xFFE4E7EF),
                thumbColor: Colors.white,
                overlayColor: plannerBlue.withValues(alpha: 0.10),
                thumbShape: const RoundSliderThumbShape(
                  enabledThumbRadius: 9,
                  elevation: 2,
                ),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
                trackShape: const RoundedRectSliderTrackShape(),
              ),
              child: Slider(
                value: _progress,
                divisions: 20,
                label: '$percent%',
                onChanged: (value) {
                  setState(() => _progress = value);
                },
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                for (final value in const [0.0, 0.25, 0.5, 0.75, 1.0]) ...[
                  Expanded(
                    child: _ProgressPresetChip(
                      value: value,
                      selected: _progress == value,
                      onSelected: () => setState(() => _progress = value),
                    ),
                  ),
                  if (value != 1.0) const SizedBox(width: 6),
                ],
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_progress),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _ProgressPresetChip extends StatelessWidget {
  const _ProgressPresetChip({
    required this.value,
    required this.selected,
    required this.onSelected,
  });

  final double value;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final label = '${(value * 100).round()}%';
    return InkWell(
      onTap: onSelected,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        height: 32,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFEAF1FE) : Colors.white,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: selected ? const Color(0xFFBFD4FA) : plannerBorder,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? plannerBlue : plannerText,
            fontSize: 12.5,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _ActionsMenu extends StatelessWidget {
  const _ActionsMenu({
    required this.tooltip,
    required this.onEdit,
    required this.onDelete,
    required this.editLabel,
    required this.deleteLabel,
  });

  final String tooltip;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final String editLabel;
  final String deleteLabel;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_TableAction>(
      tooltip: tooltip,
      offset: const Offset(0, 32),
      constraints: const BoxConstraints(minWidth: 190, maxWidth: 260),
      onSelected: (action) {
        switch (action) {
          case _TableAction.edit:
            onEdit();
            break;
          case _TableAction.delete:
            onDelete();
            break;
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: _TableAction.edit,
          height: 38,
          child: _ActionMenuLabel(icon: Icons.edit_outlined, label: editLabel),
        ),
        PopupMenuItem(
          value: _TableAction.delete,
          height: 38,
          child: _ActionMenuLabel(
            icon: Icons.delete_outline_rounded,
            label: deleteLabel,
            danger: true,
          ),
        ),
      ],
      child: const SizedBox(
        width: 28,
        height: 28,
        child: Icon(Icons.more_horiz_rounded, color: plannerMuted, size: 18),
      ),
    );
  }
}

enum _TableAction { edit, delete }

class _ActionMenuLabel extends StatelessWidget {
  const _ActionMenuLabel({
    required this.icon,
    required this.label,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger ? plannerRed : plannerText;
    return Row(
      children: [
        Icon(icon, color: color, size: 16),
        const SizedBox(width: 10),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

/// The due-date cell. Typed dates let us flag overdue and due-today work,
/// which the old display-string storage could not support.
class DueDateCell extends StatelessWidget {
  const DueDateCell({super.key, required this.task, required this.status});

  final PlannerTask task;
  final StatusLabel? status;

  @override
  Widget build(BuildContext context) {
    final due = task.dueDate;
    if (due == null) {
      return const Tooltip(
        message: 'No due date set — add one by editing the task',
        child: Text(
          'No date',
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: plannerFaint, fontSize: 13),
        ),
      );
    }

    final done = status?.isDone ?? false;
    final overdue = task.isOverdue(done: done);
    final today = task.isDueToday && !done;
    final color = overdue ? plannerRed : (today ? plannerOrange : plannerText);

    final row = Row(
      children: [
        if (overdue || today) ...[
          Icon(
            overdue ? Icons.error_outline_rounded : Icons.today_rounded,
            size: 13,
            color: color,
          ),
          const SizedBox(width: 5),
        ],
        Flexible(
          child: Text(
            today ? 'Today' : formatDate(due),
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontSize: 13,
              fontWeight: overdue || today ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ],
    );

    return Tooltip(
      message: overdue
          ? 'Overdue — was due ${formatDate(due)}'
          : today
          ? 'Due today'
          : 'Due ${formatDate(due)}',
      child: row,
    );
  }
}

/// The label [id] names, or null when the board no longer defines it.
///
/// The views hold a plain status list rather than the [Board], so they cannot
/// use `Board.statusById`.
StatusLabel? statusById(List<StatusLabel> statuses, String? id) {
  if (id == null) {
    return null;
  }
  return statuses.where((status) => status.id == id).firstOrNull;
}

/// The profiles behind a task's assignee ids, in workspace-member order.
List<UserProfile> assigneeProfiles(
  PlannerTask task,
  List<WorkspaceMember> members,
) {
  return members
      .where((member) => task.assigneeIds.contains(member.profile.id))
      .map((member) => member.profile)
      .toList();
}

/// Renders a task's start/end pair, degrading gracefully when only one end is
/// set.
String _timelineLabel(PlannerTask task) {
  final start = task.startDate;
  final end = task.endDate;
  if (start == null && end == null) {
    return 'Unscheduled';
  }
  if (start != null && end != null) {
    return '${formatDate(start)} – ${formatDate(end)}';
  }
  if (start != null) {
    return 'From ${formatDate(start)}';
  }
  return 'Until ${formatDate(end!)}';
}
