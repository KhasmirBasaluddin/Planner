import 'package:flutter/material.dart';

import '../../../models/planner_models.dart';
import '../../../shared/utils/planner_colors.dart';

class TaskFormResult {
  const TaskFormResult({
    required this.groupId,
    required this.title,
    required this.owner,
    required this.status,
    required this.priority,
    required this.dueDate,
    required this.timeline,
    required this.progress,
  });

  final int groupId;
  final String title;
  final String owner;
  final TaskStatus status;
  final TaskPriority priority;
  final String dueDate;
  final String timeline;
  final double progress;
}

class NameFormResult {
  const NameFormResult({required this.name, required this.color});

  final String name;
  final Color color;
}

Future<NameFormResult?> showNameDialog({
  required BuildContext context,
  required String title,
  required String label,
  String initialValue = '',
  Color? initialColor,
}) {
  return showDialog<NameFormResult>(
    context: context,
    builder: (context) => _NameDialog(
      title: title,
      label: label,
      initialValue: initialValue,
      initialColor: initialColor,
    ),
  );
}

Future<TaskFormResult?> showTaskDialog({
  required BuildContext context,
  required List<TaskGroup> groups,
  PlannerTask? task,
}) {
  if (groups.isEmpty) {
    return Future<TaskFormResult?>.value();
  }

  return showDialog<TaskFormResult>(
    context: context,
    builder: (context) => _TaskDialog(groups: groups, task: task),
  );
}

Future<bool> showDeleteConfirmDialog({
  required BuildContext context,
  required String title,
  required String message,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      shape: _dialogShape,
      titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
      actionsPadding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
      title: Row(
        children: [
          _DialogIcon(
            icon: Icons.delete_outline_rounded,
            color: plannerRed,
            backgroundColor: plannerRed.withValues(alpha: 0.10),
          ),
          const SizedBox(width: 12),
          Expanded(child: _DialogTitle(title)),
        ],
      ),
      content: Text(
        message,
        style: const TextStyle(color: plannerMuted, height: 1.45),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          style: TextButton.styleFrom(foregroundColor: plannerText),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: FilledButton.styleFrom(backgroundColor: plannerRed),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

class _NameDialog extends StatefulWidget {
  const _NameDialog({
    required this.title,
    required this.label,
    required this.initialValue,
    this.initialColor,
  });

  final String title;
  final String label;
  final String initialValue;
  final Color? initialColor;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _controller;
  late Color _selectedColor;

  static const List<Color> _availableColors = [
    plannerBlue,
    plannerGreen,
    plannerYellow,
    plannerRed,
    plannerPurple,
    plannerTeal,
    plannerOrange,
    plannerMagenta,
    plannerCyan,
    plannerBrown,
  ];

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
    _selectedColor = widget.initialColor ?? _availableColors.first;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      shape: _dialogShape,
      titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 18, 24, 0),
      actionsPadding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
      title: _DialogTitle(widget.title),
      content: SizedBox(
        width: 440,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                controller: _controller,
                autofocus: true,
                validator: _requiredValidator(widget.label),
                decoration: _fieldDecoration(label: widget.label),
                onFieldSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 16),
              const Text(
                'Color',
                style: TextStyle(
                  color: plannerInk,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _availableColors.map((color) {
                  final isSelected = _selectedColor == color;
                  return GestureDetector(
                    onTap: () => setState(() => _selectedColor = color),
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isSelected ? plannerInk : Colors.transparent,
                          width: 2,
                        ),
                      ),
                      child: isSelected
                          ? const Icon(
                              Icons.check,
                              color: Colors.white,
                              size: 18,
                            )
                          : null,
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          style: TextButton.styleFrom(foregroundColor: plannerText),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    Navigator.of(
      context,
    ).pop(NameFormResult(name: _controller.text.trim(), color: _selectedColor));
  }
}

class _TaskDialog extends StatefulWidget {
  const _TaskDialog({required this.groups, this.task});

  final List<TaskGroup> groups;
  final PlannerTask? task;

  @override
  State<_TaskDialog> createState() => _TaskDialogState();
}

class _TaskDialogState extends State<_TaskDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _ownerController;
  late final TextEditingController _dueDateController;
  late final TextEditingController _timelineController;
  late int _groupId;
  late TaskStatus _status;
  late TaskPriority _priority;
  late double _progress;
  DateTime? _dueDate;
  DateTime? _timelineStart;
  DateTime? _timelineEnd;

  @override
  void initState() {
    super.initState();
    final task = widget.task;
    _titleController = TextEditingController(text: task?.title ?? '');
    _ownerController = TextEditingController(text: task?.owner ?? 'ME');
    _dueDateController = TextEditingController(
      text: task?.dueDate == null || task?.dueDate == 'No date'
          ? ''
          : task!.dueDate,
    );
    _timelineController = TextEditingController(
      text: task?.timeline == null || task?.timeline == 'Unscheduled'
          ? ''
          : task!.timeline,
    );
    _groupId = task?.groupId ?? widget.groups.first.id;
    _status = task?.status ?? TaskStatus.notStarted;
    _priority = task?.priority ?? TaskPriority.medium;
    _progress = task?.progress ?? 0;
    _parseDates();
  }

  void _parseDates() {
    final task = widget.task;
    if (task?.dueDate != null && task!.dueDate != 'No date') {
      _dueDate = _parseDate(task.dueDate);
    }
    if (task?.timeline != null && task!.timeline != 'Unscheduled') {
      final parts = task.timeline.split(' - ');
      if (parts.length == 2) {
        _timelineStart = _parseDate(parts[0]);
        _timelineEnd = _parseDate(parts[1]);
      }
    }
  }

  DateTime? _parseDate(String dateStr) {
    try {
      final now = DateTime.now();
      final parts = dateStr.split(' ');
      if (parts.length == 2) {
        final month = _monthToNumber(parts[0]);
        final day = int.parse(parts[1]);
        return DateTime(now.year, month, day);
      }
    } catch (e) {
      return null;
    }
    return null;
  }

  int _monthToNumber(String month) {
    final months = {
      'Jan': 1,
      'Feb': 2,
      'Mar': 3,
      'Apr': 4,
      'May': 5,
      'Jun': 6,
      'Jul': 7,
      'Aug': 8,
      'Sep': 9,
      'Oct': 10,
      'Nov': 11,
      'Dec': 12,
    };
    return months[month] ?? 1;
  }

  String _formatDate(DateTime? date) {
    if (date == null) return '';
    return '${_monthNames[date.month - 1]} ${date.day}';
  }

  static const _monthNames = [
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

  @override
  void dispose() {
    _titleController.dispose();
    _ownerController.dispose();
    _dueDateController.dispose();
    _timelineController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.task != null;

    return AlertDialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      shape: _dialogShape,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      titlePadding: const EdgeInsets.fromLTRB(26, 26, 26, 0),
      contentPadding: const EdgeInsets.fromLTRB(26, 18, 26, 0),
      actionsPadding: const EdgeInsets.fromLTRB(26, 20, 26, 26),
      title: Row(
        children: [
          _DialogIcon(
            icon: isEditing ? Icons.edit_note_rounded : Icons.add_task_rounded,
            color: plannerBlue,
            backgroundColor: plannerBlue.withValues(alpha: 0.10),
          ),
          const SizedBox(width: 12),
          Expanded(child: _DialogTitle(isEditing ? 'Edit task' : 'New task')),
        ],
      ),
      content: SizedBox(
        width: 640,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  controller: _titleController,
                  autofocus: true,
                  validator: _requiredValidator('Task name'),
                  decoration: _fieldDecoration(
                    label: 'Task name',
                    hint: 'Example: Design desktop planner shell',
                    icon: Icons.check_box_outlined,
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: _GroupDropdown(
                        value: _groupId,
                        groups: widget.groups,
                        onChanged: (value) => setState(() => _groupId = value),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _ownerController,
                        textCapitalization: TextCapitalization.characters,
                        validator: _requiredValidator('Owner initials'),
                        decoration: _fieldDecoration(
                          label: 'Owner initials',
                          hint: 'ME',
                          icon: Icons.person_outline_rounded,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: _StatusDropdown(
                        value: _status,
                        onChanged: (value) {
                          setState(() {
                            _status = value;
                            if (value == TaskStatus.done) {
                              _progress = 1;
                            }
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _PriorityDropdown(
                        value: _priority,
                        onChanged: (value) => setState(() => _priority = value),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _dueDateController,
                        readOnly: true,
                        decoration: _fieldDecoration(
                          label: 'Due date',
                          hint: 'Jul 30',
                          icon: Icons.event_outlined,
                        ),
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: _dueDate ?? DateTime.now(),
                            firstDate: DateTime.now(),
                            lastDate: DateTime.now().add(
                              const Duration(days: 365),
                            ),
                            builder: (context, child) {
                              return Theme(
                                data: ThemeData.light().copyWith(
                                  colorScheme: const ColorScheme.light(
                                    primary: plannerBlue,
                                    onPrimary: Colors.white,
                                    surface: Colors.white,
                                    onSurface: plannerInk,
                                  ),
                                  dialogTheme: const DialogThemeData(
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.all(
                                        Radius.circular(16.0),
                                      ),
                                    ),
                                  ),
                                  datePickerTheme: DatePickerThemeData(
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16.0),
                                    ),
                                    todayBackgroundColor:
                                        WidgetStateProperty.all(
                                          plannerBlue.withValues(alpha: 0.12),
                                        ),
                                    todayForegroundColor:
                                        WidgetStateProperty.all(plannerBlue),
                                  ),
                                ),
                                child: child!,
                              );
                            },
                          );
                          if (picked != null) {
                            setState(() {
                              _dueDate = picked;
                              _dueDateController.text = _formatDate(picked);
                            });
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _timelineController,
                        readOnly: true,
                        decoration: _fieldDecoration(
                          label: 'Timeline',
                          hint: 'Jul 26 - Jul 30',
                          icon: Icons.timeline_rounded,
                        ),
                        onTap: () async {
                          DateTime? tempStart = _timelineStart;
                          DateTime? tempEnd = _timelineEnd;

                          final result = await showDialog<bool>(
                            context: context,
                            builder: (context) => _DateRangeDialog(
                              initialStart: tempStart,
                              initialEnd: tempEnd,
                              onRangeSelected: (start, end) {
                                tempStart = start;
                                tempEnd = end;
                              },
                            ),
                          );

                          if (result == true &&
                              tempStart != null &&
                              tempEnd != null) {
                            setState(() {
                              _timelineStart = tempStart;
                              _timelineEnd = tempEnd;
                              _timelineController.text =
                                  '${_formatDate(tempStart)} - ${_formatDate(tempEnd)}';
                            });
                          }
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
                  decoration: BoxDecoration(
                    color: plannerSurface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: plannerBorder),
                  ),
                  child: Row(
                    children: [
                      const Text(
                        'Progress',
                        style: TextStyle(
                          color: plannerInk,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            activeTrackColor: plannerBlue,
                            inactiveTrackColor: const Color(0xFFDDE2ED),
                            thumbColor: plannerBlue,
                            overlayColor: plannerBlue.withValues(alpha: 0.12),
                          ),
                          child: Slider(
                            value: _progress,
                            divisions: 20,
                            label: '${(_progress * 100).round()}%',
                            onChanged: (value) {
                              setState(() => _progress = value);
                            },
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 48,
                        child: Text(
                          '${(_progress * 100).round()}%',
                          textAlign: TextAlign.end,
                          style: const TextStyle(
                            color: plannerText,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          style: TextButton.styleFrom(foregroundColor: plannerText),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(isEditing ? 'Save changes' : 'Create task'),
        ),
      ],
    );
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    final title = _titleController.text.trim();
    final owner = _ownerController.text.trim().toUpperCase();
    final dueDate = _dueDate != null
        ? _formatDate(_dueDate)
        : _dueDateController.text.trim();
    final timeline = _timelineStart != null && _timelineEnd != null
        ? '${_formatDate(_timelineStart)} - ${_formatDate(_timelineEnd)}'
        : _timelineController.text.trim();

    Navigator.of(context).pop(
      TaskFormResult(
        groupId: _groupId,
        title: title,
        owner: owner,
        status: _status,
        priority: _priority,
        dueDate: dueDate,
        timeline: timeline,
        progress: _progress,
      ),
    );
  }
}

class _GroupDropdown extends StatelessWidget {
  const _GroupDropdown({
    required this.value,
    required this.groups,
    required this.onChanged,
  });

  final int value;
  final List<TaskGroup> groups;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<int>(
      initialValue: value,
      isExpanded: true,
      menuMaxHeight: 280,
      dropdownColor: Colors.white,
      borderRadius: BorderRadius.circular(12),
      decoration: _fieldDecoration(
        label: 'Group',
        icon: Icons.view_week_outlined,
      ),
      items: groups.map((group) {
        return DropdownMenuItem(
          value: group.id,
          child: _DropdownLabel(label: group.name, color: group.color),
        );
      }).toList(),
      validator: (value) => value == null ? 'Group is required' : null,
      onChanged: (value) {
        if (value != null) {
          onChanged(value);
        }
      },
    );
  }
}

class _StatusDropdown extends StatelessWidget {
  const _StatusDropdown({required this.value, required this.onChanged});

  final TaskStatus value;
  final ValueChanged<TaskStatus> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<TaskStatus>(
      initialValue: value,
      isExpanded: true,
      menuMaxHeight: 280,
      dropdownColor: Colors.white,
      borderRadius: BorderRadius.circular(12),
      decoration: _fieldDecoration(label: 'Status', icon: Icons.flag_outlined),
      items: TaskStatus.values.map((status) {
        return DropdownMenuItem(
          value: status,
          child: _DropdownLabel(
            label: status.label,
            color: statusColor(status),
          ),
        );
      }).toList(),
      validator: (value) => value == null ? 'Status is required' : null,
      onChanged: (value) {
        if (value != null) {
          onChanged(value);
        }
      },
    );
  }
}

class _PriorityDropdown extends StatelessWidget {
  const _PriorityDropdown({required this.value, required this.onChanged});

  final TaskPriority value;
  final ValueChanged<TaskPriority> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<TaskPriority>(
      initialValue: value,
      isExpanded: true,
      menuMaxHeight: 280,
      dropdownColor: Colors.white,
      borderRadius: BorderRadius.circular(12),
      decoration: _fieldDecoration(
        label: 'Priority',
        icon: Icons.priority_high_rounded,
      ),
      items: TaskPriority.values.map((priority) {
        return DropdownMenuItem(
          value: priority,
          child: _DropdownLabel(
            label: priority.label,
            color: priorityColor(priority),
          ),
        );
      }).toList(),
      validator: (value) => value == null ? 'Priority is required' : null,
      onChanged: (value) {
        if (value != null) {
          onChanged(value);
        }
      },
    );
  }
}

class _DropdownLabel extends StatelessWidget {
  const _DropdownLabel({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: plannerInk,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _DialogIcon extends StatelessWidget {
  const _DialogIcon({
    required this.icon,
    required this.color,
    required this.backgroundColor,
  });

  final IconData icon;
  final Color color;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: color, size: 22),
    );
  }
}

class _DialogTitle extends StatelessWidget {
  const _DialogTitle(this.value);

  final String value;

  @override
  Widget build(BuildContext context) {
    return Text(
      value,
      style: const TextStyle(
        color: plannerInk,
        fontSize: 22,
        fontWeight: FontWeight.w800,
      ),
    );
  }
}

InputDecoration _fieldDecoration({
  required String label,
  String? hint,
  IconData? icon,
}) {
  return InputDecoration(
    labelText: label,
    hintText: hint,
    prefixIcon: icon == null ? null : Icon(icon, size: 20),
    filled: true,
    fillColor: plannerSurface,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: plannerBorder),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: plannerBlue, width: 1.4),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: plannerRed, width: 1.2),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: plannerRed, width: 1.4),
    ),
  );
}

String? Function(String?) _requiredValidator(String label) {
  return (value) {
    if (value == null || value.trim().isEmpty) {
      return '$label is required';
    }
    return null;
  };
}

final RoundedRectangleBorder _dialogShape = RoundedRectangleBorder(
  borderRadius: BorderRadius.circular(22),
);

class _DateRangeDialog extends StatefulWidget {
  const _DateRangeDialog({
    required this.initialStart,
    required this.initialEnd,
    required this.onRangeSelected,
  });

  final DateTime? initialStart;
  final DateTime? initialEnd;
  final Function(DateTime? start, DateTime? end) onRangeSelected;

  @override
  State<_DateRangeDialog> createState() => _DateRangeDialogState();
}

class _DateRangeDialogState extends State<_DateRangeDialog> {
  late DateTime? _startDate;
  late DateTime? _endDate;

  @override
  void initState() {
    super.initState();
    _startDate = widget.initialStart;
    _endDate = widget.initialEnd;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(16.0)),
      ),
      titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
      actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      title: const Text(
        'Select Timeline',
        style: TextStyle(
          color: plannerInk,
          fontSize: 20,
          fontWeight: FontWeight.w800,
        ),
      ),
      content: SizedBox(
        width: 500,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Start Date',
                        style: TextStyle(
                          color: plannerInk,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _DateSelector(
                        initialDate: _startDate,
                        onDateSelected: (date) {
                          setState(() {
                            _startDate = date;
                            widget.onRangeSelected(_startDate, _endDate);
                          });
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'End Date',
                        style: TextStyle(
                          color: plannerInk,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _DateSelector(
                        initialDate: _endDate,
                        onDateSelected: (date) {
                          setState(() {
                            _endDate = date;
                            widget.onRangeSelected(_startDate, _endDate);
                          });
                        },
                      ),
                    ],
                  ),
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
        FilledButton(
          onPressed: _startDate != null && _endDate != null
              ? () => Navigator.of(context).pop(true)
              : null,
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _DateSelector extends StatefulWidget {
  const _DateSelector({
    required this.initialDate,
    required this.onDateSelected,
  });

  final DateTime? initialDate;
  final ValueChanged<DateTime?> onDateSelected;

  @override
  State<_DateSelector> createState() => _DateSelectorState();
}

class _DateSelectorState extends State<_DateSelector> {
  DateTime? _selectedDate;

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.initialDate;
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: _selectedDate ?? DateTime.now(),
          firstDate: DateTime.now(),
          lastDate: DateTime.now().add(const Duration(days: 365)),
          builder: (context, child) {
            return Theme(
              data: ThemeData.light().copyWith(
                colorScheme: const ColorScheme.light(
                  primary: plannerBlue,
                  onPrimary: Colors.white,
                  surface: Colors.white,
                  onSurface: plannerInk,
                ),
                dialogTheme: const DialogThemeData(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.all(Radius.circular(16.0)),
                  ),
                ),
                datePickerTheme: DatePickerThemeData(
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.all(Radius.circular(16.0)),
                  ),
                  todayBackgroundColor: WidgetStateProperty.all(
                    plannerBlue.withValues(alpha: 0.12),
                  ),
                  todayForegroundColor: WidgetStateProperty.all(plannerBlue),
                ),
              ),
              child: child!,
            );
          },
        );
        if (picked != null) {
          setState(() {
            _selectedDate = picked;
            widget.onDateSelected(picked);
          });
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: plannerSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: plannerBorder),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.calendar_today_rounded,
              size: 20,
              color: plannerMuted,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _selectedDate != null
                    ? _formatDate(_selectedDate)
                    : 'Select date',
                style: TextStyle(
                  color: _selectedDate != null ? plannerInk : plannerMuted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime? date) {
    if (date == null) return '';
    return '${_monthNames[date.month - 1]} ${date.day}';
  }

  static const _monthNames = [
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
}
