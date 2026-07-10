import 'package:flutter/material.dart';

import '../../../models/planner_models.dart';
import '../../../shared/utils/planner_colors.dart';

const double _minTableWidth = 760;
const double _rowHeight = 62;

class BoardTable extends StatefulWidget {
  const BoardTable({
    super.key,
    required this.groups,
    required this.collapsedGroupIds,
    required this.onToggleGroup,
    required this.onRenameGroup,
    required this.onDeleteGroup,
    required this.onEditTask,
    required this.onDeleteTask,
    required this.onStatusChanged,
    required this.onProgressChanged,
    this.onTaskReorder,
  });

  final List<TaskGroup> groups;
  final Set<int> collapsedGroupIds;
  final ValueChanged<TaskGroup> onToggleGroup;
  final ValueChanged<TaskGroup> onRenameGroup;
  final ValueChanged<TaskGroup> onDeleteGroup;
  final ValueChanged<PlannerTask> onEditTask;
  final ValueChanged<PlannerTask> onDeleteTask;
  final Future<void> Function(PlannerTask task, TaskStatus status)
  onStatusChanged;
  final Future<void> Function(PlannerTask task, double progress)
  onProgressChanged;
  final void Function(TaskGroup group, int oldIndex, int newIndex)?
  onTaskReorder;

  @override
  State<BoardTable> createState() => _BoardTableState();
}

class _BoardTableState extends State<BoardTable> {
  final ScrollController _verticalController = ScrollController();

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
          style: TextStyle(color: plannerMuted, fontSize: 16),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontalPadding = constraints.maxWidth < 720 ? 16.0 : 24.0;
        final availableWidth = constraints.maxWidth - horizontalPadding * 2;
        final tableWidth = availableWidth < _minTableWidth
            ? _minTableWidth
            : availableWidth;

        return Scrollbar(
          controller: _verticalController,
          thumbVisibility: true,
          child: SingleChildScrollView(
            controller: _verticalController,
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              16,
              horizontalPadding,
              36,
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: tableWidth,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const TableHeader(),
                    const SizedBox(height: 10),
                    for (final group in widget.groups) ...[
                      GroupSection(
                        group: group,
                        collapsed: widget.collapsedGroupIds.contains(group.id),
                        onToggle: () => widget.onToggleGroup(group),
                        onRename: () => widget.onRenameGroup(group),
                        onDelete: () => widget.onDeleteGroup(group),
                        onEditTask: widget.onEditTask,
                        onDeleteTask: widget.onDeleteTask,
                        onStatusChanged: widget.onStatusChanged,
                        onProgressChanged: widget.onProgressChanged,
                        onTaskReorder: widget.onTaskReorder,
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
  const TableHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 42,
      decoration: BoxDecoration(
        color: const Color(0xFFF0F2F8),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: plannerBorder),
      ),
      child: const Row(
        children: [
          _HeaderCell(flex: 36, label: 'Task'),
          _HeaderCell(flex: 8, label: 'Owner'),
          _HeaderCell(flex: 13, label: 'Status'),
          _HeaderCell(flex: 12, label: 'Priority'),
          _HeaderCell(flex: 9, label: 'Due'),
          _HeaderCell(flex: 16, label: 'Timeline'),
          _HeaderCell(flex: 5, label: ''),
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
            label,
            style: const TextStyle(
              color: plannerMuted,
              fontSize: 12,
              fontWeight: FontWeight.w800,
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
    required this.collapsed,
    required this.onToggle,
    required this.onRename,
    required this.onDelete,
    required this.onEditTask,
    required this.onDeleteTask,
    required this.onStatusChanged,
    required this.onProgressChanged,
    this.onTaskReorder,
  });

  final TaskGroup group;
  final bool collapsed;
  final VoidCallback onToggle;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final ValueChanged<PlannerTask> onEditTask;
  final ValueChanged<PlannerTask> onDeleteTask;
  final Future<void> Function(PlannerTask task, TaskStatus status)
  onStatusChanged;
  final Future<void> Function(PlannerTask task, double progress)
  onProgressChanged;
  final void Function(TaskGroup group, int oldIndex, int newIndex)?
  onTaskReorder;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: plannerBorder),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0F101828),
              blurRadius: 18,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          children: [
            Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: group.color.withValues(alpha: 0.10),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(8),
                ),
              ),
              child: Row(
                children: [
                  IconButton(
                    tooltip: collapsed ? 'Expand group' : 'Collapse group',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(
                      width: 32,
                      height: 32,
                    ),
                    onPressed: onToggle,
                    icon: Icon(
                      collapsed
                          ? Icons.keyboard_arrow_right_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      color: group.color,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    group.name,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: group.color,
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '${group.tasks.length} items',
                    style: const TextStyle(color: plannerMuted, fontSize: 13),
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
              ReorderableListView(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                buildDefaultDragHandles: false,
                itemExtent: _rowHeight,
                proxyDecorator: _buildDragProxy,
                onReorder: onTaskReorder == null
                    ? (_, _) {}
                    : (oldIndex, newIndex) =>
                          onTaskReorder!(group, oldIndex, newIndex),
                children: [
                  for (final entry in group.tasks.indexed)
                    TaskRow(
                      key: ValueKey(entry.$2.id),
                      task: entry.$2,
                      rowIndex: entry.$1,
                      groupColor: group.color,
                      onEditTask: onEditTask,
                      onDeleteTask: onDeleteTask,
                      onStatusChanged: onStatusChanged,
                      onProgressChanged: onProgressChanged,
                      dragEnabled: onTaskReorder != null,
                    ),
                ],
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
    required this.rowIndex,
    required this.groupColor,
    required this.onEditTask,
    required this.onDeleteTask,
    required this.onStatusChanged,
    required this.onProgressChanged,
    required this.dragEnabled,
  });

  final PlannerTask task;
  final int rowIndex;
  final Color groupColor;
  final ValueChanged<PlannerTask> onEditTask;
  final ValueChanged<PlannerTask> onDeleteTask;
  final Future<void> Function(PlannerTask task, TaskStatus status)
  onStatusChanged;
  final Future<void> Function(PlannerTask task, double progress)
  onProgressChanged;
  final bool dragEnabled;

  @override
  Widget build(BuildContext context) {
    final row = Container(
      height: _rowHeight,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFEDEFF5))),
      ),
      child: Row(
        children: [
          Container(width: 4, color: groupColor),
          Expanded(
            flex: 36,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                children: [
                  dragEnabled
                      ? ReorderableDragStartListener(
                          index: rowIndex,
                          child: const _DragHandle(),
                        )
                      : const _DragHandle(),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      task.title,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: plannerInk,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            flex: 8,
            child: Center(child: OwnerAvatar(label: task.owner)),
          ),
          Expanded(
            flex: 13,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: StatusMenu(task: task, onChanged: onStatusChanged),
            ),
          ),
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
              child: Text(
                task.dueDate,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: plannerText),
              ),
            ),
          ),
          Expanded(
            flex: 16,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: TimelineCell(
                task: task,
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

    return row;
  }
}

class _DragHandle extends StatelessWidget {
  const _DragHandle();

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.grab,
      child: Container(
        width: 28,
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xFFF3F5FA),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(
          Icons.drag_indicator_rounded,
          color: Color(0xFF9CA3B8),
          size: 18,
        ),
      ),
    );
  }
}

class OwnerAvatar extends StatelessWidget {
  const OwnerAvatar({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: 16,
      backgroundColor: const Color(0xFFEEF1F7),
      child: Text(
        label,
        style: const TextStyle(
          color: plannerInk,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    );
  }
}

class StatusMenu extends StatelessWidget {
  const StatusMenu({super.key, required this.task, required this.onChanged});

  final PlannerTask task;
  final Future<void> Function(PlannerTask task, TaskStatus status) onChanged;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<TaskStatus>(
      tooltip: 'Change status',
      onSelected: (status) => onChanged(task, status),
      itemBuilder: (context) => TaskStatus.values.map((status) {
        return PopupMenuItem(
          value: status,
          child: Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: statusColor(status),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 10),
              Text(status.label),
            ],
          ),
        );
      }).toList(),
      child: Container(
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: statusColor(task.status),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          task.status.label,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 12,
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
    return Container(
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        priority.label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    );
  }
}

class TimelineCell extends StatelessWidget {
  const TimelineCell({super.key, required this.task, this.onProgressChanged});

  final PlannerTask task;
  final ValueChanged<double>? onProgressChanged;

  @override
  Widget build(BuildContext context) {
    final progressPercent = (task.progress * 100).round();
    final progressColor = statusColor(task.status);
    final content = Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(8)),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  task.timeline,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: plannerText,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: progressColor.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$progressPercent%',
                  style: TextStyle(
                    color: progressColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: task.progress,
              minHeight: 7,
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
      builder: (context) => _ProgressDialog(
        currentProgress: task.progress,
        statusColor: statusColor(task.status),
      ),
    );
    if (newProgress != null) {
      onProgressChanged?.call(newProgress);
    }
  }
}

class _ProgressDialog extends StatefulWidget {
  const _ProgressDialog({
    required this.currentProgress,
    required this.statusColor,
  });

  final double currentProgress;
  final Color statusColor;

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
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(18.0)),
      ),
      titlePadding: const EdgeInsets.fromLTRB(24, 22, 24, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 18, 24, 12),
      actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 22),
      title: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: widget.statusColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.trending_up_rounded,
              color: widget.statusColor,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Update progress',
              style: TextStyle(
                color: plannerInk,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Text(
            '$percent%',
            style: TextStyle(
              color: widget.statusColor,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF7F8FC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: plannerBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text(
                        'Progress',
                        style: TextStyle(
                          color: plannerInk,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '$percent% complete',
                        style: const TextStyle(
                          color: plannerMuted,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 8,
                      activeTrackColor: widget.statusColor,
                      inactiveTrackColor: const Color(0xFFDDE2ED),
                      thumbColor: widget.statusColor,
                      overlayColor: widget.statusColor.withValues(alpha: 0.12),
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 10,
                      ),
                      overlayShape: const RoundSliderOverlayShape(
                        overlayRadius: 20,
                      ),
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
                ],
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final value in const [0.0, 0.25, 0.5, 0.75, 1.0])
                  _ProgressPresetChip(
                    value: value,
                    selected: _progress == value,
                    color: widget.statusColor,
                    onSelected: () => setState(() => _progress = value),
                  ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          style: TextButton.styleFrom(foregroundColor: plannerText),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.of(context).pop(_progress),
          icon: const Icon(Icons.check_rounded, size: 18),
          label: const Text('Save'),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ],
    );
  }
}

class _ProgressPresetChip extends StatelessWidget {
  const _ProgressPresetChip({
    required this.value,
    required this.selected,
    required this.color,
    required this.onSelected,
  });

  final double value;
  final bool selected;
  final Color color;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final label = '${(value * 100).round()}%';
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onSelected(),
      showCheckmark: false,
      labelStyle: TextStyle(
        color: selected ? color : plannerText,
        fontWeight: FontWeight.w800,
      ),
      selectedColor: color.withValues(alpha: 0.13),
      backgroundColor: Colors.white,
      side: BorderSide(
        color: selected ? color.withValues(alpha: 0.42) : plannerBorder,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
      offset: const Offset(0, 34),
      color: Colors.white,
      surfaceTintColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
          child: _ActionMenuLabel(icon: Icons.edit_outlined, label: editLabel),
        ),
        PopupMenuItem(
          value: _TableAction.delete,
          child: _ActionMenuLabel(
            icon: Icons.delete_outline_rounded,
            label: deleteLabel,
            danger: true,
          ),
        ),
      ],
      child: Container(
        width: 32,
        height: 32,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xFFF8F9FC),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Icon(
          Icons.more_horiz_rounded,
          color: plannerText,
          size: 20,
        ),
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
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 10),
        Text(
          label,
          style: TextStyle(color: color, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}
