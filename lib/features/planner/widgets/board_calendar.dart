import 'package:flutter/material.dart';

import '../../../models/planner_models.dart';
import '../../../shared/utils/planner_colors.dart';
import '../../../shared/widgets/user_avatar.dart';
import 'board_table.dart';
import 'planner_dialogs.dart';

class BoardCalendar extends StatefulWidget {
  const BoardCalendar({
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
  State<BoardCalendar> createState() => _BoardCalendarState();
}

class _BoardCalendarState extends State<BoardCalendar> {
  late DateTime _visibleMonth;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _visibleMonth = DateTime(now.year, now.month);
  }

  @override
  Widget build(BuildContext context) {
    final tasks = _calendarTasks(widget.groups);

    if (widget.groups.isEmpty) {
      return const Center(
        child: Text(
          'No tasks match your search.',
          style: TextStyle(color: plannerMuted, fontSize: 14),
        ),
      );
    }

    final monthTasks = tasks.where((entry) {
      return entry.date.year == _visibleMonth.year &&
          entry.date.month == _visibleMonth.month;
    }).toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 840;
        final padding = constraints.maxWidth < 720 ? 14.0 : 24.0;
        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(padding, 16, padding, 28),
          child: compact
              ? _AgendaCalendar(
                  month: _visibleMonth,
                  tasks: monthTasks,
                  members: widget.members,
                  onPrevious: () => _changeMonth(-1),
                  onNext: () => _changeMonth(1),
                  onToday: _goToToday,
                  onOpenTask: _openTask,
                )
              : _MonthCalendar(
                  month: _visibleMonth,
                  tasks: monthTasks,
                  onPrevious: () => _changeMonth(-1),
                  onNext: () => _changeMonth(1),
                  onToday: _goToToday,
                  onOpenTask: _openTask,
                ),
        );
      },
    );
  }

  void _changeMonth(int delta) {
    setState(() {
      _visibleMonth = DateTime(_visibleMonth.year, _visibleMonth.month + delta);
    });
  }

  void _goToToday() {
    final now = DateTime.now();
    setState(() => _visibleMonth = DateTime(now.year, now.month));
  }

  void _openTask(_CalendarTask entry) {
    showDialog<void>(
      context: context,
      builder: (context) => _TaskDetailsDialog(
        entry: entry,
        members: widget.members,
        onEditTask: widget.onEditTask,
        onDeleteTask: widget.onDeleteTask,
        onOpenNotes: widget.onOpenNotes,
      ),
    );
  }
}

class _MonthCalendar extends StatelessWidget {
  const _MonthCalendar({
    required this.month,
    required this.tasks,
    required this.onPrevious,
    required this.onNext,
    required this.onToday,
    required this.onOpenTask,
  });

  final DateTime month;
  final List<_CalendarTask> tasks;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onToday;
  final ValueChanged<_CalendarTask> onOpenTask;

  @override
  Widget build(BuildContext context) {
    final days = _visibleDays(month);
    return Container(
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
          _CalendarHeader(
            month: month,
            taskCount: tasks.length,
            onPrevious: onPrevious,
            onNext: onNext,
            onToday: onToday,
          ),
          const _WeekdayHeader(),
          for (var row = 0; row < 6; row++)
            SizedBox(
              height: 132,
              child: Row(
                children: [
                  for (var column = 0; column < 7; column++)
                    Expanded(
                      child: _DayCell(
                        date: days[row * 7 + column],
                        currentMonth: month.month,
                        tasks: _tasksForDay(tasks, days[row * 7 + column]),
                        onOpenTask: onOpenTask,
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

class _AgendaCalendar extends StatelessWidget {
  const _AgendaCalendar({
    required this.month,
    required this.tasks,
    required this.members,
    required this.onPrevious,
    required this.onNext,
    required this.onToday,
    required this.onOpenTask,
  });

  final DateTime month;
  final List<_CalendarTask> tasks;
  final List<WorkspaceMember> members;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onToday;
  final ValueChanged<_CalendarTask> onOpenTask;

  @override
  Widget build(BuildContext context) {
    final days = List.generate(
      DateUtils.getDaysInMonth(month.year, month.month),
      (index) => DateTime(month.year, month.month, index + 1),
    ).where((day) => _tasksForDay(tasks, day).isNotEmpty).toList();

    return Column(
      children: [
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: plannerBorder),
          ),
          child: _CalendarHeader(
            month: month,
            taskCount: tasks.length,
            onPrevious: onPrevious,
            onNext: onNext,
            onToday: onToday,
          ),
        ),
        const SizedBox(height: 12),
        if (days.isEmpty)
          const _EmptyAgenda()
        else
          for (final day in days) ...[
            _AgendaDay(
              date: day,
              tasks: _tasksForDay(tasks, day),
              members: members,
              onOpenTask: onOpenTask,
            ),
            const SizedBox(height: 10),
          ],
      ],
    );
  }
}

class _CalendarHeader extends StatelessWidget {
  const _CalendarHeader({
    required this.month,
    required this.taskCount,
    required this.onPrevious,
    required this.onNext,
    required this.onToday,
  });

  final DateTime month;
  final int taskCount;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onToday;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Row(
        children: [
          _IconButton(
            tooltip: 'Previous month',
            icon: Icons.chevron_left_rounded,
            onPressed: onPrevious,
          ),
          const SizedBox(width: 8),
          _IconButton(
            tooltip: 'Next month',
            icon: Icons.chevron_right_rounded,
            onPressed: onNext,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_monthNames[month.month - 1]} ${month.year}',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: plannerInk,
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$taskCount ${taskCount == 1 ? 'task' : 'tasks'} scheduled',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: plannerMuted, fontSize: 12),
                ),
              ],
            ),
          ),
          OutlinedButton(
            onPressed: onToday,
            child: const Text('Today'),
          ),
        ],
      ),
    );
  }
}

class _WeekdayHeader extends StatelessWidget {
  const _WeekdayHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      decoration: const BoxDecoration(
        color: Color(0xFFF7F8FC),
        border: Border(
          top: BorderSide(color: plannerBorder),
          bottom: BorderSide(color: plannerBorder),
        ),
      ),
      child: Row(
        children: [
          for (final day in const [
            'Sun',
            'Mon',
            'Tue',
            'Wed',
            'Thu',
            'Fri',
            'Sat',
          ])
            Expanded(
              child: Center(
                child: Text(
                  day.toUpperCase(),
                  style: const TextStyle(
                    color: plannerMuted,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.date,
    required this.currentMonth,
    required this.tasks,
    required this.onOpenTask,
  });

  final DateTime date;
  final int currentMonth;
  final List<_CalendarTask> tasks;
  final ValueChanged<_CalendarTask> onOpenTask;

  @override
  Widget build(BuildContext context) {
    final isOutside = date.month != currentMonth;
    final isToday = _sameDate(date, DateTime.now());
    final visibleTasks = tasks.take(3).toList();
    final hiddenCount = tasks.length - visibleTasks.length;

    return Container(
      decoration: BoxDecoration(
        color: isOutside ? const Color(0xFFFAFBFE) : Colors.white,
        border: const Border(
          right: BorderSide(color: plannerBorder),
          bottom: BorderSide(color: plannerBorder),
        ),
      ),
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isToday ? plannerBlue : Colors.transparent,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '${date.day}',
                  style: TextStyle(
                    color: isToday
                        ? Colors.white
                        : isOutside
                        ? plannerMuted.withValues(alpha: 0.55)
                        : plannerText,
                    fontWeight: isToday ? FontWeight.w600 : FontWeight.w500,
                    fontSize: 12,
                  ),
                ),
              ),
              const Spacer(),
            ],
          ),
          const SizedBox(height: 7),
          for (final entry in visibleTasks) ...[
            _CalendarTaskChip(entry: entry, onOpenTask: onOpenTask),
            const SizedBox(height: 5),
          ],
          if (hiddenCount > 0)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Text(
                '$hiddenCount more',
                style: const TextStyle(color: plannerMuted, fontSize: 11),
              ),
            ),
        ],
      ),
    );
  }
}

class _AgendaDay extends StatelessWidget {
  const _AgendaDay({
    required this.date,
    required this.tasks,
    required this.members,
    required this.onOpenTask,
  });

  final DateTime date;
  final List<_CalendarTask> tasks;
  final List<WorkspaceMember> members;
  final ValueChanged<_CalendarTask> onOpenTask;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(radiusMd),
        border: Border.all(color: plannerBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${_weekdayNames[date.weekday % 7]}, ${_monthNames[date.month - 1]} ${date.day}',
            style: const TextStyle(
              color: plannerInk,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          for (final entry in tasks) ...[
            _AgendaTaskCard(
              entry: entry,
              members: members,
              onOpenTask: onOpenTask,
            ),
            if (entry != tasks.last) const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

class _CalendarTaskChip extends StatelessWidget {
  const _CalendarTaskChip({required this.entry, required this.onOpenTask});

  final _CalendarTask entry;
  final ValueChanged<_CalendarTask> onOpenTask;

  @override
  Widget build(BuildContext context) {
    final task = entry.task;
    final color = statusColor(task.status);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => onOpenTask(entry),
        borderRadius: BorderRadius.circular(6),
        child: Container(
          height: 24,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: plannerBorder),
          ),
          child: Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  task.title,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: plannerInk,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
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

class _AgendaTaskCard extends StatelessWidget {
  const _AgendaTaskCard({
    required this.entry,
    required this.members,
    required this.onOpenTask,
  });

  final _CalendarTask entry;
  final List<WorkspaceMember> members;
  final ValueChanged<_CalendarTask> onOpenTask;

  @override
  Widget build(BuildContext context) {
    final task = entry.task;
    final color = statusColor(task.status);
    final assignee = members
        .where((member) => member.profile.id == task.assigneeId)
        .firstOrNull;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => onOpenTask(entry),
        borderRadius: BorderRadius.circular(radiusMd),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(radiusSm),
            border: Border.all(color: plannerBorder),
          ),
          child: Row(
            children: [
              Container(
                width: 3,
                height: 34,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: plannerInk,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${entry.group.name} · ${task.status.label}',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: plannerMuted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              if (assignee != null)
                UserAvatar(profile: assignee.profile, size: 26)
              else
                OwnerAvatar(label: task.owner),
            ],
          ),
        ),
      ),
    );
  }
}

class _TaskDetailsDialog extends StatelessWidget {
  const _TaskDetailsDialog({
    required this.entry,
    required this.members,
    required this.onEditTask,
    required this.onDeleteTask,
    required this.onOpenNotes,
  });

  final _CalendarTask entry;
  final List<WorkspaceMember> members;
  final ValueChanged<PlannerTask> onEditTask;
  final ValueChanged<PlannerTask> onDeleteTask;
  final ValueChanged<PlannerTask> onOpenNotes;

  @override
  Widget build(BuildContext context) {
    final task = entry.task;
    final statusTone = statusColor(task.status);
    final progressPercent = (task.progress * 100).round();
    final assignee = members
        .where((member) => member.profile.id == task.assigneeId)
        .firstOrNull;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 16, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          task.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: plannerInk,
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                            height: 1.3,
                          ),
                        ),
                        const SizedBox(height: 4),
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
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: plannerMuted,
                                  fontSize: 12.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  NoteButton(task: task, onOpenNotes: onOpenNotes),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(
                      Icons.close_rounded,
                      color: plannerMuted,
                      size: 20,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
              child: Column(
                children: [
                  _DetailRow(
                    label: 'Status',
                    child: Row(
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: statusTone,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(task.status.label, style: _detailValueStyle),
                      ],
                    ),
                  ),
                  _DetailRow(
                    label: 'Priority',
                    child: Row(
                      children: [
                        Icon(
                          Icons.flag_rounded,
                          size: 12,
                          color: priorityColor(task.priority),
                        ),
                        const SizedBox(width: 6),
                        Text(task.priority.label, style: _detailValueStyle),
                      ],
                    ),
                  ),
                  _DetailRow(
                    label: 'Owner',
                    child: assignee == null
                        ? Text(task.owner, style: _detailValueStyle)
                        : Row(
                            children: [
                              UserAvatar(profile: assignee.profile, size: 20),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  assignee.profile.displayName,
                                  overflow: TextOverflow.ellipsis,
                                  style: _detailValueStyle,
                                ),
                              ),
                            ],
                          ),
                  ),
                  _DetailRow(
                    label: 'Due date',
                    child: _DateText(date: task.dueDate),
                  ),
                  _DetailRow(
                    label: 'Timeline',
                    child: _TimelineText(
                      start: task.startDate,
                      end: task.endDate,
                    ),
                  ),
                  _DetailRow(
                    label: 'Progress',
                    child: Row(
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(99),
                            child: LinearProgressIndicator(
                              value: task.progress,
                              minHeight: 4,
                              backgroundColor: const Color(0xFFE8EAF1),
                              valueColor: AlwaysStoppedAnimation<Color>(
                                statusTone,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text('$progressPercent%', style: _detailValueStyle),
                      ],
                    ),
                  ),
                  _DetailRow(
                    label: 'Notes',
                    child: Text(
                      task.noteCount == 0
                          ? 'No notes'
                          : '${task.noteCount} '
                                '${task.noteCount == 1 ? 'note' : 'notes'}',
                      style: task.noteCount == 0
                          ? _detailPlaceholderStyle
                          : _detailValueStyle,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: plannerBorder)),
              ),
              child: Row(
                children: [
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                      onDeleteTask(task);
                    },
                    style: TextButton.styleFrom(foregroundColor: plannerRed),
                    child: const Text('Delete'),
                  ),
                  const Spacer(),
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Close'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                      onEditTask(task);
                    },
                    child: const Text('Edit task'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

const TextStyle _detailValueStyle = TextStyle(
  color: plannerInk,
  fontSize: 13,
  fontWeight: FontWeight.w500,
);

const TextStyle _detailPlaceholderStyle = TextStyle(
  color: plannerFaint,
  fontSize: 13,
  fontWeight: FontWeight.w500,
);

/// A single date, or a muted placeholder when it is unset.
class _DateText extends StatelessWidget {
  const _DateText({required this.date});

  final DateTime? date;

  @override
  Widget build(BuildContext context) {
    final value = date;
    return Text(
      value == null ? 'No date' : formatDate(value),
      style: value == null ? _detailPlaceholderStyle : _detailValueStyle,
    );
  }
}

/// "12 Mar – 20 Mar", falling back to whichever end is set.
class _TimelineText extends StatelessWidget {
  const _TimelineText({required this.start, required this.end});

  final DateTime? start;
  final DateTime? end;

  @override
  Widget build(BuildContext context) {
    final from = start;
    final to = end;
    final String label;
    if (from == null && to == null) {
      label = 'No timeline';
    } else if (from != null && to != null) {
      label = '${formatDate(from)} – ${formatDate(to)}';
    } else if (from != null) {
      label = 'From ${formatDate(from)}';
    } else {
      label = 'Until ${formatDate(to!)}';
    }
    return Text(
      label,
      overflow: TextOverflow.ellipsis,
      style: from == null && to == null
          ? _detailPlaceholderStyle
          : _detailValueStyle,
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: const TextStyle(color: plannerMuted, fontSize: 12.5),
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _EmptyAgenda extends StatelessWidget {
  const _EmptyAgenda();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(26),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: plannerBorder),
      ),
      child: const Text(
        'No scheduled tasks this month.',
        textAlign: TextAlign.center,
        style: TextStyle(color: plannerMuted, fontSize: 13),
      ),
    );
  }
}

class _IconButton extends StatelessWidget {
  const _IconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: plannerBorder),
          ),
          child: Icon(icon, color: plannerText, size: 18),
        ),
      ),
    );
  }
}

class _CalendarTask {
  const _CalendarTask({
    required this.task,
    required this.group,
    required this.date,
  });

  final PlannerTask task;
  final TaskGroup group;
  final DateTime date;
}

List<_CalendarTask> _calendarTasks(List<TaskGroup> groups) {
  final entries = <_CalendarTask>[];
  for (final group in groups) {
    for (final task in group.tasks) {
      final date = task.dueDate;
      if (date != null) {
        entries.add(_CalendarTask(task: task, group: group, date: date));
      }
    }
  }
  entries.sort((a, b) {
    final dateCompare = a.date.compareTo(b.date);
    if (dateCompare != 0) {
      return dateCompare;
    }
    return a.task.title.toLowerCase().compareTo(b.task.title.toLowerCase());
  });
  return entries;
}

List<_CalendarTask> _tasksForDay(List<_CalendarTask> tasks, DateTime day) {
  return tasks.where((entry) => _sameDate(entry.date, day)).toList();
}

List<DateTime> _visibleDays(DateTime month) {
  final firstDay = DateTime(month.year, month.month);
  final firstVisible = firstDay.subtract(Duration(days: firstDay.weekday % 7));
  return List.generate(42, (index) => firstVisible.add(Duration(days: index)));
}

bool _sameDate(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

const _monthNames = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

const _weekdayNames = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];



