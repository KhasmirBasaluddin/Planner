import 'package:flutter/material.dart';

import '../../../models/planner_models.dart';
import '../../../shared/utils/planner_colors.dart';
import 'planner_dialogs.dart';

const double _minTableWidth = 760;
const double _rowHeight = 54;

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
    required this.onNotesChanged,
    this.onTaskReorder,
    this.onPinTaskToNotes,
  });

  final List<TaskGroup> groups;
  final Set<int> collapsedGroupIds;
  final ValueChanged<TaskGroup> onToggleGroup;
  final ValueChanged<TaskGroup> onRenameGroup;
  final ValueChanged<TaskGroup> onDeleteGroup;
  final ValueChanged<PlannerTask> onEditTask;
  final ValueChanged<PlannerTask> onDeleteTask;
  final ValueChanged<PlannerTask>? onPinTaskToNotes;
  final Future<void> Function(PlannerTask task, TaskStatus status)
  onStatusChanged;
  final Future<void> Function(PlannerTask task, double progress)
  onProgressChanged;
  final Future<void> Function(PlannerTask task, List<String> notes)
  onNotesChanged;
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
          style: TextStyle(color: plannerMuted, fontSize: 14),
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
                        onPinTaskToNotes: widget.onPinTaskToNotes,
                        onStatusChanged: widget.onStatusChanged,
                        onProgressChanged: widget.onProgressChanged,
                        onNotesChanged: widget.onNotesChanged,
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
      height: 36,
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FB),
        borderRadius: BorderRadius.circular(6),
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
    required this.collapsed,
    required this.onToggle,
    required this.onRename,
    required this.onDelete,
    required this.onEditTask,
    required this.onDeleteTask,
    required this.onStatusChanged,
    required this.onProgressChanged,
    required this.onNotesChanged,
    this.onTaskReorder,
    this.onPinTaskToNotes,
  });

  final TaskGroup group;
  final bool collapsed;
  final VoidCallback onToggle;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final ValueChanged<PlannerTask> onEditTask;
  final ValueChanged<PlannerTask> onDeleteTask;
  final ValueChanged<PlannerTask>? onPinTaskToNotes;
  final Future<void> Function(PlannerTask task, TaskStatus status)
  onStatusChanged;
  final Future<void> Function(PlannerTask task, double progress)
  onProgressChanged;
  final Future<void> Function(PlannerTask task, List<String> notes)
  onNotesChanged;
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
                      onPinTaskToNotes: onPinTaskToNotes,
                      onStatusChanged: onStatusChanged,
                      onProgressChanged: onProgressChanged,
                      onNotesChanged: onNotesChanged,
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
    required this.onNotesChanged,
    required this.dragEnabled,
    this.onPinTaskToNotes,
  });

  final PlannerTask task;
  final int rowIndex;
  final Color groupColor;
  final ValueChanged<PlannerTask> onEditTask;
  final ValueChanged<PlannerTask> onDeleteTask;
  final ValueChanged<PlannerTask>? onPinTaskToNotes;
  final Future<void> Function(PlannerTask task, TaskStatus status)
  onStatusChanged;
  final Future<void> Function(PlannerTask task, double progress)
  onProgressChanged;
  final Future<void> Function(PlannerTask task, List<String> notes)
  onNotesChanged;
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
                  const SizedBox(width: 8),
                  NoteButton(task: task, onNotesChanged: onNotesChanged),
                  const SizedBox(width: 4),
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
                style: const TextStyle(color: plannerText, fontSize: 13),
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
                  onSendToNotes: onPinTaskToNotes == null
                      ? null
                      : () => onPinTaskToNotes!(task),
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
    return const MouseRegion(
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
    );
  }
}

class OwnerAvatar extends StatelessWidget {
  const OwnerAvatar({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: 13,
      backgroundColor: const Color(0xFFE9EBF1),
      child: Text(
        label,
        style: const TextStyle(
          color: plannerText,
          fontWeight: FontWeight.w600,
          fontSize: 10.5,
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
    final color = statusColor(task.status);
    return Align(
      alignment: Alignment.centerLeft,
      child: PopupMenuButton<TaskStatus>(
        tooltip: 'Change status',
        onSelected: (status) => onChanged(task, status),
        itemBuilder: (context) => TaskStatus.values.map((status) {
          return PopupMenuItem(
            value: status,
            height: 38,
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: statusColor(status),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  status.label,
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
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                task.status.label,
                style: TextStyle(
                  color: Color.lerp(color, plannerInk, 0.25),
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
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
            Text(
              priority.label,
              style: const TextStyle(
                color: plannerText,
                fontWeight: FontWeight.w500,
                fontSize: 12,
              ),
            ),
          ],
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
                  task.timeline,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: plannerMuted, fontSize: 12),
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
      builder: (context) =>
          _ProgressDialog(currentProgress: task.progress),
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
    this.onSendToNotes,
  });

  final String tooltip;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final String editLabel;
  final String deleteLabel;

  /// Task rows only: pins the task to the Notes canvas as a sticky note.
  final VoidCallback? onSendToNotes;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_TableAction>(
      tooltip: tooltip,
      offset: const Offset(0, 32),
      onSelected: (action) {
        switch (action) {
          case _TableAction.edit:
            onEdit();
            break;
          case _TableAction.sendToNotes:
            onSendToNotes?.call();
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
        if (onSendToNotes != null)
          const PopupMenuItem(
            value: _TableAction.sendToNotes,
            height: 38,
            child: _ActionMenuLabel(
              icon: Icons.push_pin_outlined,
              label: 'Pin to Notes',
            ),
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

enum _TableAction { edit, sendToNotes, delete }

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
