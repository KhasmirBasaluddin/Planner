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
    required this.statuses,
    required this.onEditTask,
    required this.onDeleteTask,
    required this.onStatusChanged,
    required this.onProgressChanged,
    required this.onOpenChat,
    required this.onOpenNotes,
    this.highlightedTaskId,
  });

  final List<TaskGroup> groups;
  final List<WorkspaceMember> members;

  /// The task the attention banner just revealed, if any. Its card lights up,
  /// and the column scrolls to bring it into view.
  final String? highlightedTaskId;

  /// One column per status the board defines, in display order.
  final List<StatusLabel> statuses;
  final ValueChanged<PlannerTask> onEditTask;
  final ValueChanged<PlannerTask> onDeleteTask;
  final Future<void> Function(PlannerTask task, StatusLabel status)
  onStatusChanged;
  final Future<void> Function(PlannerTask task, double progress)
  onProgressChanged;
  final ValueChanged<PlannerTask> onOpenChat;

  /// Straight to the task's work log.
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
        // Deliberately tight: the goal is every status on screen at once,
        // even on a small laptop with the sidebar open. Columns share the
        // width equally down to a minimum where a card is still readable;
        // past that they wrap into rows rather than scrolling sideways, so
        // no status is ever hidden off-screen.
        const gap = 10.0;
        const minColumnWidth = 170.0;
        final padding = constraints.maxWidth < 1100 ? 12.0 : 20.0;
        final available = constraints.maxWidth - padding * 2;
        final height = constraints.maxHeight - 32;
        final columns = statuses.isEmpty ? 1 : statuses.length;

        // How many columns fit side by side without dropping below the
        // minimum width.
        final fitCount = ((available + gap) / (minColumnWidth + gap))
            .floor()
            .clamp(1, columns);

        Widget columnFor(StatusLabel status) => _KanbanColumn(
          status: status,
          tasks: _tasksByStatus(tasks, status),
          members: members,
          onEditTask: onEditTask,
          onDeleteTask: onDeleteTask,
          onStatusChanged: onStatusChanged,
          onProgressChanged: onProgressChanged,
          onOpenChat: onOpenChat,
          onOpenNotes: onOpenNotes,
          highlightedTaskId: highlightedTaskId,
        );

        if (fitCount >= columns) {
          return Padding(
            padding: EdgeInsets.fromLTRB(padding, 16, padding, 16),
            child: SizedBox(
              height: height,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final status in statuses) ...[
                    Expanded(child: columnFor(status)),
                    if (status != statuses.last) const SizedBox(width: gap),
                  ],
                ],
              ),
            ),
          );
        }

        // Too narrow for one row: wrap into as many rows as needed, sized so
        // the whole grid fills the viewport without leftover space below.
        final rows = (columns / fitCount).ceil();
        final cellWidth = (available - gap * (fitCount - 1)) / fitCount;
        final cellHeight = ((height - gap * (rows - 1)) / rows).clamp(
          280.0,
          520.0,
        );

        return GridView.count(
          padding: EdgeInsets.fromLTRB(padding, 16, padding, 16),
          crossAxisCount: fitCount,
          crossAxisSpacing: gap,
          mainAxisSpacing: gap,
          childAspectRatio: cellWidth / cellHeight,
          children: [for (final status in statuses) columnFor(status)],
        );
      },
    );
  }
}

List<_KanbanTask> _tasksByStatus(List<_KanbanTask> tasks, StatusLabel status) {
  return tasks.where((entry) => entry.task.statusId == status.id).toList();
}

/// Roughly how tall one card runs: title, meta row, progress and padding.
/// Used only to estimate a scroll offset when revealing a task.
const double _cardExtent = 132;

class _KanbanColumn extends StatefulWidget {
  const _KanbanColumn({
    required this.status,
    required this.tasks,
    required this.members,
    required this.onEditTask,
    required this.onDeleteTask,
    required this.onStatusChanged,
    required this.onProgressChanged,
    required this.onOpenChat,
    required this.onOpenNotes,
    this.highlightedTaskId,
  });

  final StatusLabel status;
  final List<_KanbanTask> tasks;
  final List<WorkspaceMember> members;
  final String? highlightedTaskId;
  final ValueChanged<PlannerTask> onEditTask;
  final ValueChanged<PlannerTask> onDeleteTask;
  final Future<void> Function(PlannerTask task, StatusLabel status)
  onStatusChanged;
  final Future<void> Function(PlannerTask task, double progress)
  onProgressChanged;
  final ValueChanged<PlannerTask> onOpenChat;

  /// Straight to the task's work log.
  final ValueChanged<PlannerTask> onOpenNotes;

  @override
  State<_KanbanColumn> createState() => _KanbanColumnState();
}

class _KanbanColumnState extends State<_KanbanColumn> {
  /// One per column, so a reveal can scroll *this* list to the card.
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollToHighlight();
  }

  @override
  void didUpdateWidget(covariant _KanbanColumn oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.highlightedTaskId != oldWidget.highlightedTaskId) {
      _scrollToHighlight();
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Brings the revealed card into view.
  ///
  /// Scrolls by *index* rather than leaving it to Scrollable.ensureVisible:
  /// a ListView only builds what is on screen, so a card fifteen rows down
  /// has no element for ensureVisible to find and the highlight landed on a
  /// task nobody could see. The card height is uniform enough to estimate,
  /// and the result is clamped to the list's own extent.
  void _scrollToHighlight() {
    final id = widget.highlightedTaskId;
    if (id == null) {
      return;
    }
    final index = widget.tasks.indexWhere((entry) => entry.task.id == id);
    if (index < 0) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) {
        return;
      }
      // Card plus separator. Cards vary a little with title length, so this
      // lands the target near the top of the column rather than exactly at
      // it — close enough that the highlight is unmissable.
      const estimatedExtent = _cardExtent + 8;
      final target = (index * estimatedExtent).clamp(
        0.0,
        _scroll.position.maxScrollExtent,
      );
      _scroll.animateTo(
        target,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.status;
    final tasks = widget.tasks;
    final members = widget.members;
    final highlightedTaskId = widget.highlightedTaskId;
    final onEditTask = widget.onEditTask;
    final onDeleteTask = widget.onDeleteTask;
    final onStatusChanged = widget.onStatusChanged;
    final onProgressChanged = widget.onProgressChanged;
    final onOpenChat = widget.onOpenChat;
    final onOpenNotes = widget.onOpenNotes;
    final color = statusColor(status);
    return DragTarget<PlannerTask>(
      onWillAcceptWithDetails: (details) => details.data.statusId != status.id,
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
                        status.name,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: plannerInk,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Tooltip(
                      message:
                          '${tasks.length} '
                          'task${tasks.length == 1 ? '' : 's'} '
                          'in ${status.name}',
                      child: Text(
                        '${tasks.length}',
                        style: const TextStyle(
                          color: plannerMuted,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: tasks.isEmpty
                    ? _EmptyColumn(hovering: hovering)
                    : ListView.separated(
                        controller: _scroll,
                        padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                        itemCount: tasks.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final entry = tasks[index];
                          final highlighted =
                              entry.task.id == highlightedTaskId;
                          final card = _KanbanCard(
                            entry: entry,
                            status: status,
                            members: members,
                            onEditTask: onEditTask,
                            onDeleteTask: onDeleteTask,
                            onProgressChanged: onProgressChanged,
                            onOpenChat: onOpenChat,
                            onOpenNotes: onOpenNotes,
                            highlighted: highlighted,
                          );
                          // RepaintBoundary per card: without it, one card's
                          // hover or drag repaints the whole column, which is
                          // what made a long list feel heavy under the mouse.
                          return RepaintBoundary(
                            child: _draggableCard(entry, card),
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

  Widget _draggableCard(_KanbanTask entry, Widget card) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Draggable<PlannerTask>(
          data: entry.task,
          dragAnchorStrategy: childDragAnchorStrategy,
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
          childWhenDragging: Opacity(opacity: 0.4, child: card),
          child: card,
        );
      },
    );
  }
}

class _KanbanCard extends StatelessWidget {
  const _KanbanCard({
    required this.entry,
    required this.status,
    required this.members,
    required this.onEditTask,
    required this.onDeleteTask,
    required this.onProgressChanged,
    required this.onOpenChat,
    required this.onOpenNotes,
    this.highlighted = false,
  });

  final _KanbanTask entry;

  /// True while the attention banner is pointing at this card.
  final bool highlighted;

  /// The column's status — a card only ever appears under its own.
  final StatusLabel status;
  final List<WorkspaceMember> members;
  final ValueChanged<PlannerTask> onEditTask;
  final ValueChanged<PlannerTask> onDeleteTask;
  final Future<void> Function(PlannerTask task, double progress)
  onProgressChanged;
  final ValueChanged<PlannerTask> onOpenChat;

  /// Straight to the task's work log.
  final ValueChanged<PlannerTask> onOpenNotes;

  @override
  Widget build(BuildContext context) {
    final task = entry.task;
    // Tinted with the column's own status colour, not the priority: a card
    // already sits under the status heading that gives it this colour, so the
    // two agree at a glance. A light wash rather than a solid fill, because a
    // column of solid cards reads as one block and the titles stop standing
    // out from each other.
    final tone = statusColor(status);
    // Delayed, so it guides someone hovering in doubt without flashing at
    // everyone who is just mousing across the board.
    return Tooltip(
      message: 'Open task — drag to another column to change status',
      waitDuration: const Duration(milliseconds: 700),
      child: InkWell(
        onTap: () => onEditTask(task),
        borderRadius: BorderRadius.circular(radiusSm),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 350),
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 12),
          decoration: BoxDecoration(
            color: Color.alphaBlend(
              highlighted ? tint(plannerBlue, 0.10) : tint(tone, 0.07),
              Colors.white,
            ),
            borderRadius: BorderRadius.circular(radiusSm),
            border: Border.all(
              color: highlighted ? plannerBlue : tint(tone, 0.22),
              width: highlighted ? 1.4 : 1,
            ),
            boxShadow: highlighted
                ? [
                    BoxShadow(
                      color: tint(plannerBlue, 0.35),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : const [
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
                  // Who moved it, on the card that has no status column of
                  // its own to hang it from — the column *is* the status here.
                  if (statusByline(task) != null)
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Tooltip(
                        message: statusByline(task)!,
                        child: UserAvatar(
                          profile: task.statusBy!,
                          size: 18,
                          showTooltip: false,
                        ),
                      ),
                    ),
                  ChatButton(task: task, onOpenChat: onOpenChat, size: 26),
                  const SizedBox(width: 5),
                  NotesButton(task: task, onOpenNotes: onOpenNotes),
                  _TaskMenu(
                    onEdit: () => onEditTask(task),
                    onDelete: () => onDeleteTask(task),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Flexible(
                    child: Tooltip(
                      message: 'Group: ${entry.group.name}',
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
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
                              style: const TextStyle(
                                color: plannerMuted,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Tooltip(
                    message: 'Priority: ${task.priority.label}',
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.flag_rounded,
                          size: 11,
                          color: priorityColor(task.priority),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          task.priority.label,
                          style: const TextStyle(
                            color: plannerMuted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: _TaskMetaRow(
                  task: task,
                  status: status,
                  members: members,
                ),
              ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: _CompactProgress(
                  task: task,
                  status: status,
                  onChanged: (progress) => onProgressChanged(task, progress),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TaskMetaRow extends StatelessWidget {
  const _TaskMetaRow({
    required this.task,
    required this.status,
    required this.members,
  });

  final PlannerTask task;
  final StatusLabel status;
  final List<WorkspaceMember> members;

  @override
  Widget build(BuildContext context) {
    final overdue = task.isOverdue(done: status.isDone);
    final due = task.dueDate;
    final dueColor = overdue
        ? plannerRed
        : (due == null ? plannerFaint : plannerText);
    return Row(
      children: [
        AssigneeAvatars(task: task, members: members),
        const SizedBox(width: 8),
        Expanded(
          child: Tooltip(
            message: due == null
                ? 'No due date set'
                : overdue
                ? 'Overdue — was due ${formatDate(due)}'
                : 'Due ${formatDate(due)}',
            child: Row(
              children: [
                Icon(Icons.event_outlined, size: 13, color: dueColor),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    due == null ? 'No date' : formatDate(due),
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: dueColor,
                      fontSize: 12,
                      fontWeight: overdue ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _CompactProgress extends StatelessWidget {
  const _CompactProgress({
    required this.task,
    required this.status,
    required this.onChanged,
  });

  final PlannerTask task;
  final StatusLabel status;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final color = statusColor(status);
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
                  // Tinted with the same status colour rather than a fixed
                  // grey, which read as a dirty smudge on a tinted card.
                  backgroundColor: tint(color, 0.18),
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
