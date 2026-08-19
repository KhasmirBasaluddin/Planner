import 'package:flutter/material.dart';

import '../../../models/planner_models.dart';
import '../../../shared/utils/planner_colors.dart';
import '../../../shared/widgets/app_dialog.dart';
import '../../../shared/widgets/user_avatar.dart';
import 'board_table.dart';
import 'planner_dialogs.dart';

class BoardCalendar extends StatefulWidget {
  const BoardCalendar({
    super.key,
    required this.groups,
    required this.members,
    required this.statuses,
    required this.onEditTask,
    required this.onDeleteTask,
    required this.onStatusChanged,
    required this.onProgressChanged,
    required this.onOpenChat,
    this.highlightedTaskId,
    this.highlightKey,
  });

  final List<TaskGroup> groups;
  final List<WorkspaceMember> members;

  /// The task the attention banner just revealed, if any. The calendar jumps
  /// to its due month and lights its chip up.
  final String? highlightedTaskId;
  final GlobalKey? highlightKey;

  /// The board's statuses, used to resolve the label behind each task.
  final List<StatusLabel> statuses;
  final ValueChanged<PlannerTask> onEditTask;
  final ValueChanged<PlannerTask> onDeleteTask;
  final Future<void> Function(PlannerTask task, StatusLabel status)
  onStatusChanged;
  final Future<void> Function(PlannerTask task, double progress)
  onProgressChanged;
  final ValueChanged<PlannerTask> onOpenChat;

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
    final due = _highlightedDueDate();
    if (due != null) {
      _visibleMonth = DateTime(due.year, due.month);
    }
  }

  @override
  void didUpdateWidget(covariant BoardCalendar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A reveal can point at a task in another month; follow it there.
    if (widget.highlightedTaskId != oldWidget.highlightedTaskId) {
      final due = _highlightedDueDate();
      if (due != null) {
        setState(() => _visibleMonth = DateTime(due.year, due.month));
      }
    }
  }

  DateTime? _highlightedDueDate() {
    final id = widget.highlightedTaskId;
    if (id == null) {
      return null;
    }
    for (final group in widget.groups) {
      for (final task in group.tasks) {
        if (task.id == id) {
          return task.dueDate;
        }
      }
    }
    return null;
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
                  statuses: widget.statuses,
                  onPrevious: () => _changeMonth(-1),
                  onNext: () => _changeMonth(1),
                  onToday: _goToToday,
                  onOpenTask: _openTask,
                  highlightedTaskId: widget.highlightedTaskId,
                  highlightKey: widget.highlightKey,
                )
              : _MonthCalendar(
                  month: _visibleMonth,
                  tasks: monthTasks,
                  members: widget.members,
                  statuses: widget.statuses,
                  onPrevious: () => _changeMonth(-1),
                  onNext: () => _changeMonth(1),
                  onToday: _goToToday,
                  onOpenTask: _openTask,
                  highlightedTaskId: widget.highlightedTaskId,
                  highlightKey: widget.highlightKey,
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
        status: statusById(widget.statuses, entry.task.statusId),
        onEditTask: widget.onEditTask,
        onDeleteTask: widget.onDeleteTask,
        onOpenChat: widget.onOpenChat,
      ),
    );
  }
}

class _MonthCalendar extends StatelessWidget {
  const _MonthCalendar({
    required this.month,
    required this.tasks,
    required this.members,
    required this.statuses,
    required this.onPrevious,
    required this.onNext,
    required this.onToday,
    required this.onOpenTask,
    this.highlightedTaskId,
    this.highlightKey,
  });

  final DateTime month;
  final List<_CalendarTask> tasks;
  final List<WorkspaceMember> members;
  final List<StatusLabel> statuses;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onToday;
  final ValueChanged<_CalendarTask> onOpenTask;
  final String? highlightedTaskId;
  final GlobalKey? highlightKey;

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
                        members: members,
                        statuses: statuses,
                        onOpenTask: onOpenTask,
                        highlightedTaskId: highlightedTaskId,
                        highlightKey: highlightKey,
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
    required this.statuses,
    required this.onPrevious,
    required this.onNext,
    required this.onToday,
    required this.onOpenTask,
    this.highlightedTaskId,
    this.highlightKey,
  });

  final DateTime month;
  final List<_CalendarTask> tasks;
  final List<WorkspaceMember> members;
  final List<StatusLabel> statuses;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onToday;
  final ValueChanged<_CalendarTask> onOpenTask;
  final String? highlightedTaskId;
  final GlobalKey? highlightKey;

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
              statuses: statuses,
              onOpenTask: onOpenTask,
              highlightedTaskId: highlightedTaskId,
              highlightKey: highlightKey,
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
          OutlinedButton(onPressed: onToday, child: const Text('Today')),
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
    required this.members,
    required this.statuses,
    required this.onOpenTask,
    this.highlightedTaskId,
    this.highlightKey,
  });

  final DateTime date;
  final int currentMonth;
  final List<_CalendarTask> tasks;
  final List<WorkspaceMember> members;
  final List<StatusLabel> statuses;
  final ValueChanged<_CalendarTask> onOpenTask;
  final String? highlightedTaskId;
  final GlobalKey? highlightKey;

  /// The chips shown in the cell itself. Three fit; a busier day shows two
  /// plus a "+N more" opener, and a revealed task is always among them.
  List<_CalendarTask> get _visibleTasks {
    final shown = tasks.length <= 3 ? tasks.length : 2;
    var visible = tasks.take(shown).toList();
    final id = highlightedTaskId;
    if (id != null &&
        tasks.any((t) => t.task.id == id) &&
        !visible.any((t) => t.task.id == id)) {
      final entry = tasks.firstWhere((t) => t.task.id == id);
      visible = [entry, ...tasks.where((t) => t.task.id != id).take(shown - 1)];
    }
    return visible;
  }

  @override
  Widget build(BuildContext context) {
    final isOutside = date.month != currentMonth;
    final isToday = _sameDate(date, DateTime.now());
    final visibleTasks = _visibleTasks;
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
              if (tasks.isNotEmpty)
                Text(
                  '${tasks.length}',
                  style: const TextStyle(
                    color: plannerFaint,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          for (final entry in visibleTasks) ...[
            _CalendarTaskChip(
              entry: entry,
              status: statusById(statuses, entry.task.statusId),
              onOpenTask: onOpenTask,
              highlighted: entry.task.id == highlightedTaskId,
              highlightKey: entry.task.id == highlightedTaskId
                  ? highlightKey
                  : null,
            ),
            const SizedBox(height: 4),
          ],
          if (hiddenCount > 0)
            _MoreChip(
              count: hiddenCount,
              date: date,
              tasks: tasks,
              members: members,
              statuses: statuses,
              onOpenTask: onOpenTask,
            ),
        ],
      ),
    );
  }
}

/// The "+N more" opener for a day too busy for its cell. The full list opens
/// in a dialog, so a crowded day never overflows the grid.
class _MoreChip extends StatelessWidget {
  const _MoreChip({
    required this.count,
    required this.date,
    required this.tasks,
    required this.members,
    required this.statuses,
    required this.onOpenTask,
  });

  final int count;
  final DateTime date;
  final List<_CalendarTask> tasks;
  final List<WorkspaceMember> members;
  final List<StatusLabel> statuses;
  final ValueChanged<_CalendarTask> onOpenTask;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Show all ${tasks.length} tasks due this day',
      child: InkWell(
        onTap: () => _showDayTasks(context),
        borderRadius: BorderRadius.circular(4),
        child: Container(
          height: 22,
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            color: plannerSurface,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: plannerBorder),
          ),
          alignment: Alignment.centerLeft,
          child: Text(
            '+$count more',
            style: const TextStyle(
              color: plannerMuted,
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  void _showDayTasks(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AppDialog(
        icon: Icons.event_outlined,
        title:
            '${_weekdayNames[date.weekday % 7]}, '
            '${_monthNames[date.month - 1]} ${date.day}',
        message: '${tasks.length} tasks due this day. Click one to open it.',
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final entry in tasks) ...[
              _AgendaTaskCard(
                entry: entry,
                members: members,
                status: statusById(statuses, entry.task.statusId),
                onOpenTask: (task) {
                  Navigator.of(dialogContext).pop();
                  onOpenTask(task);
                },
              ),
              if (entry != tasks.last) const SizedBox(height: 8),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
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
    required this.statuses,
    required this.onOpenTask,
    this.highlightedTaskId,
    this.highlightKey,
  });

  final DateTime date;
  final List<_CalendarTask> tasks;
  final List<WorkspaceMember> members;
  final List<StatusLabel> statuses;
  final ValueChanged<_CalendarTask> onOpenTask;
  final String? highlightedTaskId;
  final GlobalKey? highlightKey;

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
              status: statusById(statuses, entry.task.statusId),
              onOpenTask: onOpenTask,
              highlighted: entry.task.id == highlightedTaskId,
              highlightKey: entry.task.id == highlightedTaskId
                  ? highlightKey
                  : null,
            ),
            if (entry != tasks.last) const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

class _CalendarTaskChip extends StatelessWidget {
  const _CalendarTaskChip({
    required this.entry,
    required this.status,
    required this.onOpenTask,
    this.highlighted = false,
    this.highlightKey,
  });

  final _CalendarTask entry;
  final StatusLabel? status;
  final ValueChanged<_CalendarTask> onOpenTask;
  final bool highlighted;
  final GlobalKey? highlightKey;

  @override
  Widget build(BuildContext context) {
    final task = entry.task;
    final color = statusColor(status);
    final done = status?.isDone ?? false;
    final overdue = task.isOverdue(done: done);
    final pressing =
        task.priority == TaskPriority.urgent ||
        task.priority == TaskPriority.high;

    // Washed with the status colour like a kanban card, so a glance at the
    // month says how the work stands, not just that work exists. Overdue and
    // urgent get their marks; the details dialog holds the rest.
    final chip = Material(
      color: Colors.transparent,
      child: Tooltip(
        message:
            '${task.title}\n'
            '${status?.name ?? 'No status'} · ${task.priority.label} priority'
            '${overdue ? ' · Overdue' : ''}',
        waitDuration: const Duration(milliseconds: 500),
        child: InkWell(
          onTap: () => onOpenTask(entry),
          borderRadius: BorderRadius.circular(4),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 350),
            height: 24,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
              color: Color.alphaBlend(
                highlighted ? tint(plannerBlue, 0.12) : tint(color, 0.08),
                Colors.white,
              ),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: highlighted ? plannerBlue : tint(color, 0.30),
                width: highlighted ? 1.4 : 1,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    task.title,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: overdue ? plannerRed : plannerInk,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (overdue) ...[
                  const SizedBox(width: 4),
                  const Icon(
                    Icons.error_outline_rounded,
                    size: 11,
                    color: plannerRed,
                  ),
                ] else if (pressing) ...[
                  const SizedBox(width: 4),
                  Icon(
                    Icons.flag_rounded,
                    size: 10,
                    color: priorityColor(task.priority),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );

    final key = highlightKey;
    return key == null ? chip : KeyedSubtree(key: key, child: chip);
  }
}

class _AgendaTaskCard extends StatelessWidget {
  const _AgendaTaskCard({
    required this.entry,
    required this.members,
    required this.status,
    required this.onOpenTask,
    this.highlighted = false,
    this.highlightKey,
  });

  final _CalendarTask entry;
  final List<WorkspaceMember> members;
  final StatusLabel? status;
  final ValueChanged<_CalendarTask> onOpenTask;
  final bool highlighted;
  final GlobalKey? highlightKey;

  @override
  Widget build(BuildContext context) {
    final task = entry.task;
    final color = statusColor(status);
    final card = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => onOpenTask(entry),
        borderRadius: BorderRadius.circular(radiusMd),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 350),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: highlighted
                ? Color.alphaBlend(tint(plannerBlue, 0.10), Colors.white)
                : Colors.white,
            borderRadius: BorderRadius.circular(radiusSm),
            border: Border.all(
              color: highlighted ? plannerBlue : plannerBorder,
              width: highlighted ? 1.4 : 1,
            ),
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
                      '${entry.group.name} · ${status?.name ?? 'No status'}',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: plannerMuted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              AssigneeAvatars(task: task, members: members),
            ],
          ),
        ),
      ),
    );

    final key = highlightKey;
    return key == null ? card : KeyedSubtree(key: key, child: card);
  }
}

/// What a task looks like when you click it in the calendar.
///
/// The previous version was a uniform label/value grid — status, priority,
/// assignee, due date, timeline, progress, all the same weight — so nothing
/// read first and the eye had to walk every row. Here the two facts that
/// actually drive a decision get promoted:
///
///   * the due date, framed as time remaining rather than a bare date, because
///     "in 2 days" is the thing you want and "29 Jul" makes you do the sum
///   * progress, as a bar you can read at a glance
///
/// Everything else is supporting detail, set as chips rather than rows so it
/// occupies a band instead of a column.
class _TaskDetailsDialog extends StatelessWidget {
  const _TaskDetailsDialog({
    required this.entry,
    required this.members,
    required this.status,
    required this.onEditTask,
    required this.onDeleteTask,
    required this.onOpenChat,
  });

  final _CalendarTask entry;
  final List<WorkspaceMember> members;
  final StatusLabel? status;
  final ValueChanged<PlannerTask> onEditTask;
  final ValueChanged<PlannerTask> onDeleteTask;
  final ValueChanged<PlannerTask> onOpenChat;

  @override
  Widget build(BuildContext context) {
    final task = entry.task;
    final tone = statusColor(status);
    final assignees = assigneeProfiles(task, members);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Container(
          decoration: BoxDecoration(
            color: plannerCard,
            borderRadius: BorderRadius.circular(radiusLg),
            boxShadow: shadowLg,
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _DetailsHeader(
                task: task,
                group: entry.group,
                status: status,
                tone: tone,
                onOpenChat: onOpenChat,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // The two facts worth leading with, side by side.
                    //
                    // IntrinsicHeight so the two cards match: `stretch` alone
                    // needs a bounded height, and inside a min-size Column it
                    // gets infinity — which crashes layout and, downstream,
                    // fills the console with mouse-tracker assertions from the
                    // frame that never completed.
                    IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: _DueCard(
                              due: task.dueDate,
                              done: status?.isDone ?? false,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _ProgressCard(
                              progress: task.progress,
                              tone: tone,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    _DetailChips(
                      task: task,
                      status: status,
                      assignees: assignees,
                      tone: tone,
                    ),
                    if (task.startDate != null || task.endDate != null) ...[
                      const SizedBox(height: 12),
                      _TimelineStrip(
                        start: task.startDate,
                        end: task.endDate,
                        tone: tone,
                      ),
                    ],
                    const SizedBox(height: 12),
                    // The discussion gets a card of its own rather than an
                    // icon in the corner: on a shared task the conversation
                    // is half the point, and a hidden entrance reads as
                    // "there is no chat".
                    _DiscussionCard(task: task, onOpenChat: onOpenChat),
                  ],
                ),
              ),
              _DetailsActions(
                task: task,
                onEditTask: onEditTask,
                onDeleteTask: onDeleteTask,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Title, group and status, on a wash of the status colour.
///
/// The tint does the work a "Status: Not started" row used to: you know where
/// the task stands before reading a word.
class _DetailsHeader extends StatelessWidget {
  const _DetailsHeader({
    required this.task,
    required this.group,
    required this.status,
    required this.tone,
    required this.onOpenChat,
  });

  final PlannerTask task;
  final TaskGroup group;
  final StatusLabel? status;
  final Color tone;
  final ValueChanged<PlannerTask> onOpenChat;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 12, 16),
      decoration: BoxDecoration(
        color: Color.alphaBlend(tint(tone, 0.09), plannerCard),
        border: const Border(bottom: BorderSide(color: plannerDivider)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: tone,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        status?.name ?? 'No status',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: tone,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      '·',
                      style: TextStyle(color: plannerFaint, fontSize: 11),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        group.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: plannerMuted,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  task.title,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: plannerInk,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                    letterSpacing: -0.3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 18),
            color: plannerMuted,
            tooltip: 'Close',
            visualDensity: VisualDensity.compact,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}

/// The task's discussion, promoted to a full-width card.
///
/// Tinted with the brand blue and given a real button, because "is anyone
/// talking about this?" is the question a shared task answers here — and the
/// message count answers it before the card is even clicked.
class _DiscussionCard extends StatelessWidget {
  const _DiscussionCard({required this.task, required this.onOpenChat});

  final PlannerTask task;
  final ValueChanged<PlannerTask> onOpenChat;

  void _open(BuildContext context) {
    Navigator.of(context).pop();
    onOpenChat(task);
  }

  @override
  Widget build(BuildContext context) {
    final count = task.commentCount;
    final hasMessages = count > 0;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _open(context),
        borderRadius: BorderRadius.circular(radiusMd),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
          decoration: BoxDecoration(
            color: tint(plannerBlue, hasMessages ? 0.06 : 0.03),
            borderRadius: BorderRadius.circular(radiusMd),
            border: Border.all(
              color: tint(plannerBlue, hasMessages ? 0.28 : 0.16),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: tint(plannerBlue, 0.12),
                  borderRadius: BorderRadius.circular(radiusSm),
                ),
                alignment: Alignment.center,
                child: Icon(
                  hasMessages
                      ? Icons.forum_rounded
                      : Icons.chat_bubble_outline_rounded,
                  size: 16,
                  color: plannerBlue,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Task chat',
                      style: TextStyle(
                        color: plannerInk,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      hasMessages
                          ? '$count ${count == 1 ? 'message' : 'messages'} — '
                                'open to read and reply'
                          : 'No messages yet — start the discussion',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: plannerMuted,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () => _open(context),
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  textStyle: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                child: const Text('Open chat'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The due date, framed as time remaining.
///
/// "in 2 days" is the fact; "29 Jul" is the raw material for working it out.
/// Overdue turns red, because that is the one state worth interrupting for.
class _DueCard extends StatelessWidget {
  const _DueCard({required this.due, required this.done});

  final DateTime? due;
  final bool done;

  @override
  Widget build(BuildContext context) {
    final date = due;
    if (date == null) {
      return const _StatCard(
        label: 'DUE',
        value: 'No date',
        muted: true,
        icon: Icons.event_busy_outlined,
      );
    }

    final today = DateTime.now();
    final days = DateTime(
      date.year,
      date.month,
      date.day,
    ).difference(DateTime(today.year, today.month, today.day)).inDays;

    // A finished task is never late, however far past its date it sits.
    final overdue = days < 0 && !done;
    final tone = overdue
        ? plannerRed
        : (days <= 2 && !done ? plannerOrange : plannerInk);

    final relative = switch (days) {
      < -1 => '${-days} days overdue',
      -1 => 'Yesterday',
      0 => 'Today',
      1 => 'Tomorrow',
      < 7 => 'In $days days',
      _ => formatDate(date),
    };

    return _StatCard(
      label: 'DUE',
      value: relative,
      // The exact date still shows underneath, so the framing costs nothing.
      caption: days.abs() < 7 ? formatDate(date) : null,
      tone: tone,
      icon: overdue ? Icons.warning_amber_rounded : Icons.event_outlined,
    );
  }
}

class _ProgressCard extends StatelessWidget {
  const _ProgressCard({required this.progress, required this.tone});

  final double progress;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    final percent = (progress * 100).round();

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 11),
      decoration: BoxDecoration(
        color: plannerSurface,
        borderRadius: BorderRadius.circular(radiusMd),
        border: Border.all(color: plannerBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'PROGRESS',
            style: TextStyle(
              color: plannerFaint,
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.7,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '$percent%',
            style: const TextStyle(
              color: plannerInk,
              fontSize: 16,
              fontWeight: FontWeight.w700,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 7),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 5,
              backgroundColor: tint(tone, 0.18),
              valueColor: AlwaysStoppedAnimation<Color>(tone),
            ),
          ),
        ],
      ),
    );
  }
}

/// A labelled figure, sized to sit beside the progress card.
class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    this.caption,
    this.tone = plannerInk,
    this.muted = false,
  });

  final String label;
  final String value;
  final String? caption;
  final IconData icon;
  final Color tone;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 11),
      decoration: BoxDecoration(
        color: plannerSurface,
        borderRadius: BorderRadius.circular(radiusMd),
        border: Border.all(color: plannerBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: plannerFaint,
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.7,
                ),
              ),
              const Spacer(),
              Icon(icon, size: 12, color: muted ? plannerFaint : tone),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: muted ? plannerFaint : tone,
              fontSize: 16,
              fontWeight: FontWeight.w700,
              height: 1.1,
            ),
          ),
          SizedBox(height: caption == null ? 7 : 3),
          if (caption != null)
            Text(
              caption!,
              style: const TextStyle(color: plannerMuted, fontSize: 10.5),
            )
          else
            const SizedBox(height: 5),
        ],
      ),
    );
  }
}

/// Priority and assignees as chips.
///
/// A band rather than two more label/value rows: these are attributes you scan
/// for, not figures you read.
class _DetailChips extends StatelessWidget {
  const _DetailChips({
    required this.task,
    required this.status,
    required this.assignees,
    required this.tone,
  });

  final PlannerTask task;
  final StatusLabel? status;
  final List<UserProfile> assignees;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    final priorityTone = priorityColor(task.priority);

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _Chip(
          icon: Icons.flag_rounded,
          label: task.priority.label,
          tone: priorityTone,
        ),
        if (assignees.isEmpty)
          const _Chip(
            icon: Icons.person_outline_rounded,
            label: 'Unassigned',
            tone: plannerMuted,
            subdued: true,
          )
        else
          _AssigneeChip(assignees: assignees),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.icon,
    required this.label,
    required this.tone,
    this.subdued = false,
  });

  final IconData icon;
  final String label;
  final Color tone;
  final bool subdued;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: subdued ? plannerSurface : tint(tone, 0.10),
        borderRadius: BorderRadius.circular(radiusSm),
        border: Border.all(color: subdued ? plannerBorder : tint(tone, 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: tone),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: subdued ? plannerMuted : tone,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Faces plus names, so a task with two assignees says both.
class _AssigneeChip extends StatelessWidget {
  const _AssigneeChip({required this.assignees});

  final List<UserProfile> assignees;

  @override
  Widget build(BuildContext context) {
    final names = assignees.length == 1
        ? assignees.single.displayName
        : '${assignees.length} people';

    return Container(
      padding: const EdgeInsets.fromLTRB(5, 4, 10, 4),
      decoration: BoxDecoration(
        color: plannerSurface,
        borderRadius: BorderRadius.circular(radiusSm),
        border: Border.all(color: plannerBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AvatarStack(profiles: assignees, size: 20, maxVisible: 3),
          const SizedBox(width: 8),
          Text(
            names,
            style: const TextStyle(
              color: plannerText,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Start and end as a span, rather than two dates the reader has to relate.
class _TimelineStrip extends StatelessWidget {
  const _TimelineStrip({
    required this.start,
    required this.end,
    required this.tone,
  });

  final DateTime? start;
  final DateTime? end;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: plannerSurface,
        borderRadius: BorderRadius.circular(radiusMd),
        border: Border.all(color: plannerBorder),
      ),
      child: Row(
        children: [
          const Icon(Icons.timeline_rounded, size: 13, color: plannerFaint),
          const SizedBox(width: 9),
          _TimelineEnd(date: start, fallback: 'No start'),
          Expanded(
            child: Container(
              height: 2,
              margin: const EdgeInsets.symmetric(horizontal: 9),
              decoration: BoxDecoration(
                color: tint(tone, 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          _TimelineEnd(date: end, fallback: 'No end'),
        ],
      ),
    );
  }
}

class _TimelineEnd extends StatelessWidget {
  const _TimelineEnd({required this.date, required this.fallback});

  final DateTime? date;
  final String fallback;

  @override
  Widget build(BuildContext context) {
    final value = date;
    return Text(
      value == null ? fallback : formatDate(value),
      style: TextStyle(
        color: value == null ? plannerFaint : plannerText,
        fontSize: 11.5,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _DetailsActions extends StatelessWidget {
  const _DetailsActions({
    required this.task,
    required this.onEditTask,
    required this.onDeleteTask,
  });

  final PlannerTask task;
  final ValueChanged<PlannerTask> onEditTask;
  final ValueChanged<PlannerTask> onDeleteTask;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 14, 12),
      decoration: const BoxDecoration(
        color: plannerSurface,
        border: Border(top: BorderSide(color: plannerDivider)),
      ),
      child: Row(
        children: [
          TextButton.icon(
            onPressed: () {
              Navigator.of(context).pop();
              onDeleteTask(task);
            },
            icon: const Icon(Icons.delete_outline_rounded, size: 15),
            label: const Text('Delete'),
            style: TextButton.styleFrom(
              foregroundColor: plannerRed,
              textStyle: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const Spacer(),
          FilledButton.icon(
            onPressed: () {
              Navigator.of(context).pop();
              onEditTask(task);
            },
            icon: const Icon(Icons.edit_outlined, size: 15),
            label: const Text('Edit task'),
            style: FilledButton.styleFrom(
              textStyle: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
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
