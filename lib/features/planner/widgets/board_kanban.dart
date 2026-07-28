import 'package:flutter/material.dart';

import '../../../models/planner_models.dart';
import '../../../shared/utils/planner_colors.dart';
import '../../../shared/widgets/user_avatar.dart';
import 'board_table.dart';
import 'planner_dialogs.dart';

class BoardKanban extends StatelessWidget {
  const BoardKanban({
    super.key,
    required this.groups,
    required this.members,
    required this.onEditTask,
    required this.onDeleteTask,
    required this.onStatusChanged,
    required this.onProgressChanged,
    required this.onOpenNotes,
  });

  final List<TaskGroup> groups;
  final List<WorkspaceMember> members;
  final ValueChanged<PlannerTask> onEditTask;
  final ValueChanged<PlannerTask> onDeleteTask;
  final Future<void> Function(PlannerTask task, TaskStatus status)
  onStatusChanged;
  final Future<void> Function(PlannerTask task, double progress)
  onProgressChanged;
  final ValueChanged<PlannerTask> onOpenNotes;

  @override
  Widget build(BuildContext context) {
    final tasks = [
      for (final group in groups)
        for (final task in group.tasks) _KanbanTask(task: task, group: group),
    ];

    if (groups.isEmpty) {
      return const Center(
        child: Text(
          'No tasks match your search.',
          style: TextStyle(color: plannerMuted, fontSize: 14),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final padding = constraints.maxWidth < 720 ? 14.0 : 24.0;
        final height = constraints.maxHeight - 32;
        final useFluidColumns = constraints.maxWidth >= 1160;

        if (useFluidColumns) {
          return Padding(
            padding: EdgeInsets.fromLTRB(padding, 16, padding, 16),
            child: SizedBox(
              height: height,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final status in _statusOrder) ...[
                    Expanded(
                      child: _KanbanColumn(
                        status: status,
                        tasks: _tasksByStatus(tasks, status),
                        members: members,
                        onEditTask: onEditTask,
                        onDeleteTask: onDeleteTask,
                        onStatusChanged: onStatusChanged,
                        onProgressChanged: onProgressChanged,
                        onOpenNotes: onOpenNotes,
                      ),
                    ),
                    if (status != _statusOrder.last) const SizedBox(width: 12),
                  ],
                ],
              ),
            ),
          );
        }

        if (constraints.maxWidth >= 760) {
          return GridView.count(
            padding: EdgeInsets.fromLTRB(padding, 16, padding, 16),
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.22,
            children: [
              for (final status in _statusOrder)
                _KanbanColumn(
                  status: status,
                  tasks: _tasksByStatus(tasks, status),
                  members: members,
                  onEditTask: onEditTask,
                  onDeleteTask: onDeleteTask,
                  onStatusChanged: onStatusChanged,
                  onProgressChanged: onProgressChanged,
                  onOpenNotes: onOpenNotes,
                ),
            ],
          );
        }

        final columnWidth = (constraints.maxWidth - padding * 2).clamp(
          280.0,
          320.0,
        );

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.fromLTRB(padding, 16, padding, 16),
          child: SizedBox(
            height: height,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final status in _statusOrder) ...[
                  SizedBox(
                    width: columnWidth,
                    child: _KanbanColumn(
                      status: status,
                      tasks: _tasksByStatus(tasks, status),
                      members: members,
                      onEditTask: onEditTask,
                      onDeleteTask: onDeleteTask,
                      onStatusChanged: onStatusChanged,
                      onProgressChanged: onProgressChanged,
                      onOpenNotes: onOpenNotes,
                    ),
                  ),
                  if (status != _statusOrder.last) const SizedBox(width: 12),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

const _statusOrder = [
  TaskStatus.notStarted,
  TaskStatus.working,
  TaskStatus.stuck,
  TaskStatus.done,
];

List<_KanbanTask> _tasksByStatus(List<_KanbanTask> tasks, TaskStatus status) {
  return tasks.where((entry) => entry.task.status == status).toList();
}

class _KanbanColumn extends StatelessWidget {
  const _KanbanColumn({
    required this.status,
    required this.tasks,
    required this.members,
    required this.onEditTask,
    required this.onDeleteTask,
    required this.onStatusChanged,
    required this.onProgressChanged,
    required this.onOpenNotes,
  });

  final TaskStatus status;
  final List<_KanbanTask> tasks;
  final List<WorkspaceMember> members;
  final ValueChanged<PlannerTask> onEditTask;
  final ValueChanged<PlannerTask> onDeleteTask;
  final Future<void> Function(PlannerTask task, TaskStatus status)
  onStatusChanged;
  final Future<void> Function(PlannerTask task, double progress)
  onProgressChanged;
  final ValueChanged<PlannerTask> onOpenNotes;

  @override
  Widget build(BuildContext context) {
    final color = statusColor(status);
    return DragTarget<PlannerTask>(
      onWillAcceptWithDetails: (details) => details.data.status != status,
      onAcceptWithDetails: (details) => onStatusChanged(details.data, status),
      builder: (context, candidateData, rejectedData) {
        final hovering = candidateData.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          decoration: BoxDecoration(
            color: hovering ? plannerHover : plannerSurface,
            borderRadius: BorderRadius.circular(radiusMd),
            border: Border.all(
              color: hovering ? color.withValues(alpha: 0.45) : plannerBorder,
            ),
          ),
          child: Column(
            children: [
              Container(
                height: 42,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        status.label,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: plannerInk,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Text(
                      '${tasks.length}',
                      style: const TextStyle(
                        color: plannerMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: tasks.isEmpty
                    ? _EmptyColumn(hovering: hovering)
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                        itemCount: tasks.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final entry = tasks[index];
                          final card = _KanbanCard(
                            entry: entry,
                            members: members,
                            onEditTask: onEditTask,
                            onDeleteTask: onDeleteTask,
                            onProgressChanged: onProgressChanged,
                            onOpenNotes: onOpenNotes,
                          );
                          return LayoutBuilder(
                            builder: (context, constraints) {
                              return Draggable<PlannerTask>(
                                data: entry.task,
                                dragAnchorStrategy:
                                    childDragAnchorStrategy,
                                feedback: SizedBox(
                                  width: constraints.maxWidth,
                                  child: Material(
                                    color: Colors.transparent,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(radiusSm),
                                        boxShadow: const [
                                          BoxShadow(
                                            color: Color(0x1F101828),
                                            blurRadius: 16,
                                            offset: Offset(0, 8),
                                          ),
                                        ],
                                      ),
                                      child: card,
                                    ),
                                  ),
                                ),
                                childWhenDragging: Opacity(
                                  opacity: 0.4,
                                  child: card,
                                ),
                                child: card,
                              );
                            },
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _KanbanCard extends StatelessWidget {
  const _KanbanCard({
    required this.entry,
    required this.members,
    required this.onEditTask,
    required this.onDeleteTask,
    required this.onProgressChanged,
    required this.onOpenNotes,
  });

  final _KanbanTask entry;
  final List<WorkspaceMember> members;
  final ValueChanged<PlannerTask> onEditTask;
  final ValueChanged<PlannerTask> onDeleteTask;
  final Future<void> Function(PlannerTask task, double progress)
  onProgressChanged;
  final ValueChanged<PlannerTask> onOpenNotes;

  @override
  Widget build(BuildContext context) {
    final task = entry.task;
    return InkWell(
      onTap: () => onEditTask(task),
      borderRadius: BorderRadius.circular(radiusSm),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(radiusSm),
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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      task.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: plannerInk,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                      ),
                    ),
                  ),
                ),
                NoteButton(task: task, onOpenNotes: onOpenNotes, size: 26),
                _TaskMenu(
                  onEdit: () => onEditTask(task),
                  onDelete: () => onDeleteTask(task),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: entry.group.color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    entry.group.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: plannerMuted, fontSize: 12),
                  ),
                ),
                const SizedBox(width: 10),
                Icon(
                  Icons.flag_rounded,
                  size: 11,
                  color: priorityColor(task.priority),
                ),
                const SizedBox(width: 4),
                Text(
                  task.priority.label,
                  style: const TextStyle(color: plannerMuted, fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: _TaskMetaRow(task: task, members: members),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: _CompactProgress(
                task: task,
                onChanged: (progress) => onProgressChanged(task, progress),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TaskMetaRow extends StatelessWidget {
  const _TaskMetaRow({required this.task, required this.members});

  final PlannerTask task;
  final List<WorkspaceMember> members;

  @override
  Widget build(BuildContext context) {
    final assignee = members
        .where((member) => member.profile.id == task.assigneeId)
        .firstOrNull;
    final due = task.dueDate;
    final dueColor = task.isOverdue
        ? plannerRed
        : (due == null ? plannerFaint : plannerText);
    return Row(
      children: [
        if (assignee != null)
          UserAvatar(profile: assignee.profile, size: 26)
        else
          OwnerAvatar(label: task.owner),
        const SizedBox(width: 8),
        Icon(Icons.event_outlined, size: 13, color: dueColor),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            due == null ? 'No date' : formatDate(due),
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: dueColor,
              fontSize: 12,
              fontWeight: task.isOverdue ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ],
    );
  }
}

class _CompactProgress extends StatelessWidget {
  const _CompactProgress({required this.task, required this.onChanged});

  final PlannerTask task;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final color = statusColor(task.status);
    final percent = (task.progress * 100).round();
    return Tooltip(
      message: 'Update progress',
      child: InkWell(
        onTap: () => _showProgressDialog(context),
        borderRadius: BorderRadius.circular(radiusSm),
        child: Row(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(
                  value: task.progress,
                  minHeight: 4,
                  backgroundColor: const Color(0xFFE8EAF1),
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '$percent%',
              style: const TextStyle(
                color: plannerMuted,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showProgressDialog(BuildContext context) async {
    final progress = await showDialog<double>(
      context: context,
      builder: (context) => _KanbanProgressDialog(task: task),
    );
    if (progress != null) {
      onChanged(progress);
    }
  }
}

class _KanbanProgressDialog extends StatefulWidget {
  const _KanbanProgressDialog({required this.task});

  final PlannerTask task;

  @override
  State<_KanbanProgressDialog> createState() => _KanbanProgressDialogState();
}

class _KanbanProgressDialogState extends State<_KanbanProgressDialog> {
  late double _progress;

  @override
  void initState() {
    super.initState();
    _progress = widget.task.progress;
  }

  @override
  Widget build(BuildContext context) {
    final percent = (_progress * 100).round();
    return AlertDialog(
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
                onChanged: (value) => setState(() => _progress = value),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                for (final value in const [0.0, 0.25, 0.5, 0.75, 1.0]) ...[
                  Expanded(
                    child: _KanbanPresetChip(
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

class _KanbanPresetChip extends StatelessWidget {
  const _KanbanPresetChip({
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
      borderRadius: BorderRadius.circular(radiusSm),
      child: Container(
        height: 32,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFEAF1FE) : Colors.white,
          borderRadius: BorderRadius.circular(radiusSm),
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

class _EmptyColumn extends StatelessWidget {
  const _EmptyColumn({required this.hovering});

  final bool hovering;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        hovering ? 'Drop here' : 'No tasks',
        style: TextStyle(
          color: hovering ? plannerText : plannerFaint,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class _TaskMenu extends StatelessWidget {
  const _TaskMenu({required this.onEdit, required this.onDelete});

  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_TaskAction>(
      tooltip: 'Task options',
      onSelected: (action) {
        switch (action) {
          case _TaskAction.edit:
            onEdit();
            break;
          case _TaskAction.delete:
            onDelete();
            break;
        }
      },
      itemBuilder: (context) => const [
        PopupMenuItem(
          value: _TaskAction.edit,
          height: 38,
          child: _TaskMenuLabel(icon: Icons.edit_outlined, label: 'Edit task'),
        ),
        PopupMenuItem(
          value: _TaskAction.delete,
          height: 38,
          child: _TaskMenuLabel(
            icon: Icons.delete_outline_rounded,
            label: 'Delete task',
            danger: true,
          ),
        ),
      ],
      child: const SizedBox(
        width: 26,
        height: 26,
        child: Icon(Icons.more_horiz_rounded, color: plannerMuted, size: 18),
      ),
    );
  }
}

enum _TaskAction { edit, delete }

class _TaskMenuLabel extends StatelessWidget {
  const _TaskMenuLabel({
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

class _KanbanTask {
  const _KanbanTask({required this.task, required this.group});

  final PlannerTask task;
  final TaskGroup group;
}
