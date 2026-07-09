import 'package:flutter/material.dart';

import '../../../models/planner_models.dart';
import '../../../shared/utils/planner_colors.dart';

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
        final tableWidth = constraints.maxWidth < 980
            ? 980.0
            : constraints.maxWidth - 56;

        return Scrollbar(
          controller: _verticalController,
          thumbVisibility: true,
          child: SingleChildScrollView(
            controller: _verticalController,
            padding: const EdgeInsets.fromLTRB(28, 14, 28, 36),
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
          _HeaderCell(flex: 42, label: 'Task'),
          _HeaderCell(flex: 10, label: 'Owner'),
          _HeaderCell(flex: 14, label: 'Status'),
          _HeaderCell(flex: 13, label: 'Priority'),
          _HeaderCell(flex: 10, label: 'Due'),
          _HeaderCell(flex: 17, label: 'Timeline'),
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

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: plannerBorder),
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
                  Flexible(
                    child: Text(
                      group.name,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: group.color,
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
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
                    editLabel: 'Rename group',
                    deleteLabel: 'Delete group',
                  ),
                ],
              ),
            ),
            if (!collapsed)
              for (final entry in group.tasks.indexed)
                TaskRow(
                  task: entry.$2,
                  rowIndex: entry.$1,
                  groupColor: group.color,
                  onEditTask: onEditTask,
                  onDeleteTask: onDeleteTask,
                  onStatusChanged: onStatusChanged,
                ),
          ],
        ),
      ),
    );
  }
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
  });

  final PlannerTask task;
  final int rowIndex;
  final Color groupColor;
  final ValueChanged<PlannerTask> onEditTask;
  final ValueChanged<PlannerTask> onDeleteTask;
  final Future<void> Function(PlannerTask task, TaskStatus status)
  onStatusChanged;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      duration: Duration(milliseconds: 220 + rowIndex * 45),
      curve: Curves.easeOutCubic,
      tween: Tween<double>(begin: 0, end: 1),
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 12 * (1 - value)),
            child: child,
          ),
        );
      },
      child: Container(
        height: 58,
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Color(0xFFEDEFF5))),
        ),
        child: Row(
          children: [
            Container(width: 5, color: groupColor),
            Expanded(
              flex: 42,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  children: [
                    const Icon(
                      Icons.drag_indicator_rounded,
                      color: Color(0xFFB6BBCD),
                      size: 18,
                    ),
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
              flex: 10,
              child: Center(child: OwnerAvatar(label: task.owner)),
            ),
            Expanded(
              flex: 14,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: StatusMenu(task: task, onChanged: onStatusChanged),
              ),
            ),
            Expanded(
              flex: 13,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: PriorityPill(priority: task.priority),
              ),
            ),
            Expanded(
              flex: 10,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Text(
                  task.dueDate,
                  style: const TextStyle(color: plannerText),
                ),
              ),
            ),
            Expanded(
              flex: 17,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: TimelineCell(task: task),
              ),
            ),
            Expanded(
              flex: 5,
              child: Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.only(right: 14),
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
  const TimelineCell({super.key, required this.task});

  final PlannerTask task;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          task.timeline,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: plannerText, fontSize: 12),
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: TweenAnimationBuilder<double>(
            duration: const Duration(milliseconds: 360),
            curve: Curves.easeOutCubic,
            tween: Tween<double>(begin: 0, end: task.progress),
            builder: (context, value, child) {
              return LinearProgressIndicator(
                value: value,
                minHeight: 6,
                backgroundColor: const Color(0xFFE8EAF1),
                valueColor: AlwaysStoppedAnimation<Color>(
                  statusColor(task.status),
                ),
              );
            },
          ),
        ),
      ],
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
