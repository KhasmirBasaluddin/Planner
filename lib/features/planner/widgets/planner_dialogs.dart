import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show RealtimeChannel;
import 'package:url_launcher/url_launcher.dart';

import '../../../core/supabase/planner_repository.dart';
import '../../../models/planner_models.dart';
import '../../../shared/utils/planner_colors.dart';
import '../../../shared/utils/text_rules.dart';
import '../../../shared/widgets/app_dialog.dart';
import '../../../shared/widgets/user_avatar.dart';

// === Name + color dialog (boards, groups, workspaces) ===

/// Length limits for user-supplied names.
///
/// Enforced in the UI *and* worth knowing about: without a cap, a pasted essay
/// as a board name stretches the sidebar, overflows headers, and makes the
/// board unusable. These are generous enough that a real name never hits them.
/// The longest a chat message may be.
///
/// Mirrors `task_comments_body_length` in 0002_core.sql, which checks
/// `char_length(trim(body)) between 1 and 5000`. The database is the real
/// enforcement — this stops the field before the insert can fail, so a long
/// message is refused while it is being written rather than after Send.
const int commentMaxLength = 5000;

/// Deliberately *stricter* than the database.
///
/// 0002_core.sql allows 60 / 80 / 80 / 200 for these. Holding the client below
/// that means the check constraint can never be the thing that rejects a name:
/// the field stops accepting input first, with a counter, instead of the insert
/// failing and surfacing a raw Postgres error. The looser server values stay as
/// a backstop for anything not written by this app.
class NameLimits {
  const NameLimits._();

  static const int workspace = 40; // db allows 60
  static const int board = 50; // db allows 80
  static const int group = 40; // db allows 80
  static const int task = 120; // db allows 200

  /// Returns an error message, or null when the name is acceptable.
  static String? validate(
    String? value, {
    required int max,
    String what = 'name',
  }) {
    final name = (value ?? '').trim();
    if (name.isEmpty) {
      return 'Enter a $what.';
    }
    if (name.length > max) {
      return 'Keep it under $max characters (currently ${name.length}).';
    }
    // Every board, group, task, and workspace name comes through here, so one
    // check covers all of them. Chat is the exception and does not use this.
    return validateNoEmoji(name, what: what);
  }
}

class NameDialogResult {
  const NameDialogResult({required this.name, required this.color});

  final String name;
  final Color color;
}

/// Prompts for a name and a colour.
///
/// [existingNames] enables the duplicate check. Matching is case-insensitive
/// and ignores surrounding space, so "Design" and " design " collide. The
/// user's current name is excluded automatically when renaming, so re-saving
/// without changing the name does not warn.
Future<NameDialogResult?> showNameDialog({
  required BuildContext context,
  required String title,
  required String label,
  String initialValue = '',
  Color? initialColor,
  int maxLength = NameLimits.board,
  List<String> existingNames = const [],
  String duplicateNoun = 'item',
}) {
  return showDialog<NameDialogResult>(
    context: context,
    builder: (context) => _NameDialog(
      title: title,
      label: label,
      initialValue: initialValue,
      maxLength: maxLength,
      existingNames: existingNames,
      duplicateNoun: duplicateNoun,
      initialColor: initialColor ?? accentPalette.first,
    ),
  );
}

class _NameDialog extends StatefulWidget {
  const _NameDialog({
    required this.title,
    required this.label,
    required this.initialValue,
    required this.initialColor,
    required this.maxLength,
    required this.existingNames,
    required this.duplicateNoun,
  });

  final String title;
  final String label;
  final String initialValue;
  final Color initialColor;
  final int maxLength;
  final List<String> existingNames;
  final String duplicateNoun;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final TextEditingController _controller;
  late Color _color;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
    _controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _controller.text.length,
    );
    _color = widget.initialColor;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final error = NameLimits.validate(
      _controller.text,
      max: widget.maxLength,
      what: widget.label.toLowerCase(),
    );
    if (error != null) {
      setState(() => _error = error);
      return;
    }

    final name = _controller.text.trim();

    // Warn rather than block: two boards can legitimately both have a "Design"
    // group, and refusing outright would be wrong. Renaming to the same name is
    // excluded, so re-saving unchanged never prompts.
    final clashes =
        name.toLowerCase() != widget.initialValue.trim().toLowerCase() &&
        widget.existingNames.any(
          (existing) => existing.trim().toLowerCase() == name.toLowerCase(),
        );

    if (clashes) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (context) => AppDialog(
          icon: Icons.copy_all_rounded,
          tone: plannerYellow,
          title: 'That name is already taken',
          message:
              'Another ${widget.duplicateNoun} is already called "$name". '
              'Two with the same name are hard to tell apart later.',
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Pick another'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Use it anyway'),
            ),
          ],
        ),
      );
      if (proceed != true) {
        return;
      }
    }

    if (!mounted) {
      return;
    }
    Navigator.of(context).pop(NameDialogResult(name: name, color: _color));
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      icon: Icons.drive_file_rename_outline_rounded,
      title: widget.title,
      width: 440,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _FieldLabel(widget.label),
          TextField(
            controller: _controller,
            autofocus: true,
            // NameLimits.validate also rejects emoji on submit; this stops one
            // being typed in the first place, so the error never has to fire.
            inputFormatters: [emojiFreeFormatter],
            // Hard stop at the limit, so the counter is a fact rather than a
            // warning the user can ignore.
            maxLength: widget.maxLength,
            buildCounter:
                (
                  context, {
                  required currentLength,
                  required isFocused,
                  required maxLength,
                }) {
                  // Only show the counter as the limit approaches; a counter
                  // on an empty field is noise.
                  if (currentLength < (maxLength ?? 0) * 0.7) {
                    return null;
                  }
                  return Text(
                    '$currentLength/$maxLength',
                    style: TextStyle(
                      color: currentLength >= (maxLength ?? 0)
                          ? plannerRed
                          : plannerFaint,
                      fontSize: 11,
                    ),
                  );
                },
            decoration: InputDecoration(errorText: _error),
            onChanged: (_) {
              if (_error != null) {
                setState(() => _error = null);
              }
            },
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 18),
          const _FieldLabel('Color'),
          _ColorSwatchRow(
            selected: _color,
            onSelected: (color) => setState(() => _color = color),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }
}

class _ColorSwatchRow extends StatelessWidget {
  const _ColorSwatchRow({required this.selected, required this.onSelected});

  final Color selected;
  final ValueChanged<Color> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final color in accentPalette)
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () => onSelected(color),
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(radiusSm),
                  border: color.toARGB32() == selected.toARGB32()
                      ? Border.all(color: plannerInk, width: 2)
                      : null,
                ),
                child: color.toARGB32() == selected.toARGB32()
                    ? const Icon(
                        Icons.check_rounded,
                        size: 15,
                        color: Colors.white,
                      )
                    : null,
              ),
            ),
          ),
      ],
    );
  }
}

// === Confirmation ===

Future<bool> showDeleteConfirmDialog({
  required BuildContext context,
  required String title,
  required String message,
  String confirmLabel = 'Delete',
  bool danger = true,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AppDialog(
      icon: danger ? Icons.delete_outline_rounded : Icons.help_outline_rounded,
      tone: danger ? plannerRed : plannerBlue,
      title: title,
      message: message,
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: danger
              ? FilledButton.styleFrom(backgroundColor: plannerRed)
              : null,
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

// === Task dialog ===

class TaskDialogResult {
  const TaskDialogResult({
    required this.groupId,
    required this.title,
    required this.priority,
    required this.progress,
    this.statusId,
    this.assigneeIds = const [],
    this.dueDate,
    this.startDate,
    this.endDate,
  });

  final String groupId;
  final String title;

  /// One of the board's statuses. Null lets the database apply the board
  /// default, which is what a new task wants.
  final String? statusId;

  /// Everyone assigned. Replaces the single owner/assignee pair — the name is
  /// read from the profile now rather than copied onto the task.
  final List<String> assigneeIds;
  final TaskPriority priority;
  final double progress;
  final DateTime? dueDate;
  final DateTime? startDate;
  final DateTime? endDate;
}

Future<TaskDialogResult?> showTaskDialog({
  required BuildContext context,
  required List<TaskGroup> groups,
  required List<WorkspaceMember> members,
  required List<StatusLabel> statuses,
  PlannerTask? task,
}) {
  return showDialog<TaskDialogResult>(
    context: context,
    builder: (context) => _TaskDialog(
      groups: groups,
      members: members,
      statuses: statuses,
      task: task,
    ),
  );
}

class _TaskDialog extends StatefulWidget {
  const _TaskDialog({
    required this.groups,
    required this.members,
    required this.statuses,
    this.task,
  });

  final List<TaskGroup> groups;
  final List<WorkspaceMember> members;

  /// The statuses this board defines, in display order.
  final List<StatusLabel> statuses;
  final PlannerTask? task;

  @override
  State<_TaskDialog> createState() => _TaskDialogState();
}

class _TaskDialogState extends State<_TaskDialog> {
  late final TextEditingController _titleController;
  late String _groupId;
  late TaskPriority _priority;
  late double _progress;
  late List<String> _assigneeIds;
  String? _statusId;
  DateTime? _dueDate;
  DateTime? _startDate;
  DateTime? _endDate;
  String? _titleError;

  @override
  void initState() {
    super.initState();
    final task = widget.task;
    _titleController = TextEditingController(text: task?.title ?? '');
    _groupId = task?.groupId ?? widget.groups.first.id;
    _statusId = task?.statusId ?? _defaultStatus?.id;
    _priority = task?.priority ?? TaskPriority.medium;
    _progress = task?.progress ?? 0;
    _assigneeIds = [...?task?.assigneeIds];
    _dueDate = task?.dueDate;
    _startDate = task?.startDate;
    _endDate = task?.endDate;
  }

  /// The first of the board's statuses matching [test], or null if none does.
  StatusLabel? _firstStatus(bool Function(StatusLabel) test) {
    for (final status in widget.statuses) {
      if (test(status)) {
        return status;
      }
    }
    return null;
  }

  /// What a new task starts on. Falls back to the first label for a board whose
  /// default was deleted.
  StatusLabel? get _defaultStatus =>
      _firstStatus((s) => s.isDefault) ?? widget.statuses.firstOrNull;

  StatusLabel? get _status => _firstStatus((s) => s.id == _statusId);

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  void _submit() {
    final error = NameLimits.validate(
      _titleController.text,
      max: NameLimits.task,
      what: 'task name',
    );
    if (error != null) {
      setState(() => _titleError = error);
      return;
    }

    Navigator.of(context).pop(
      TaskDialogResult(
        groupId: _groupId,
        title: _titleController.text.trim(),
        statusId: _statusId,
        assigneeIds: _assigneeIds,
        priority: _priority,
        progress: _progress,
        dueDate: _dueDate,
        startDate: _startDate,
        endDate: _endDate,
      ),
    );
  }

  /// Today at midnight — the earliest date any picker here offers.
  DateTime get _today {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  Future<void> _pickDate({
    required DateTime? current,
    required ValueChanged<DateTime?> onPicked,
    DateTime? notBefore,
  }) async {
    // Scheduling work into the past is a mistake rather than an intention, so
    // the picker will not offer it.
    //
    // `current` widens the floor when it is already earlier: a task that fell
    // overdue still has to be editable, and showDatePicker asserts if the
    // initial date sits outside the range rather than clamping to it.
    var first = notBefore ?? _today;
    if (current != null && current.isBefore(first)) {
      first = DateTime(current.year, current.month, current.day);
    }

    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? first,
      firstDate: first,
      lastDate: DateTime(_today.year + 6),
    );
    if (picked != null) {
      onPicked(picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      icon: widget.task == null ? Icons.add_task_rounded : Icons.edit_outlined,
      title: widget.task == null ? 'New task' : 'Edit task',
      width: 520,
      // No scroll wrapper here: AppDialog already scrolls its body, and nesting
      // two scrollables leaves the inner one unable to size itself.
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _FieldLabel('Task'),
          TextField(
            controller: _titleController,
            autofocus: true,
            inputFormatters: [emojiFreeFormatter],
            maxLength: NameLimits.task,
            buildCounter:
                (
                  context, {
                  required currentLength,
                  required isFocused,
                  required maxLength,
                }) {
                  if (currentLength < (maxLength ?? 0) * 0.7) {
                    return null;
                  }
                  return Text(
                    '$currentLength/$maxLength',
                    style: TextStyle(
                      color: currentLength >= (maxLength ?? 0)
                          ? plannerRed
                          : plannerFaint,
                      fontSize: 11,
                    ),
                  );
                },
            decoration: InputDecoration(
              hintText: 'What needs to be done?',
              errorText: _titleError,
            ),
            onChanged: (_) {
              if (_titleError != null) {
                setState(() => _titleError = null);
              }
            },
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 16),

          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _FieldLabel('Group'),
                    _DropdownField<String>(
                      value: _groupId,
                      options: [
                        for (final group in widget.groups)
                          _Option(
                            value: group.id,
                            label: group.name,
                            color: group.color,
                          ),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => _groupId = value);
                        }
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _FieldLabel(
                      _assigneeIds.length > 1 ? 'Assignees' : 'Assignee',
                    ),
                    _AssigneePicker(
                      members: widget.members,
                      selected: _assigneeIds,
                      onChanged: (ids) => setState(() => _assigneeIds = ids),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _FieldLabel('Status'),
                    _DropdownField<String?>(
                      value: _statusId,
                      placeholder: 'No status',
                      options: [
                        for (final status in widget.statuses)
                          _Option(
                            value: status.id,
                            label: status.name,
                            color: status.color,
                          ),
                      ],
                      onChanged: (value) {
                        if (value == null) {
                          return;
                        }
                        setState(() {
                          _statusId = value;
                          // Keep progress from contradicting the status:
                          // "Working" on a full bar is not a state worth
                          // saving. Which status means finished is the
                          // board's call, so the rule reads the flags.
                          final picked = _status;
                          if (picked != null) {
                            _progress = progressForStatus(picked, _progress);
                          }
                        });
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _FieldLabel('Priority'),
                    _DropdownField<TaskPriority>(
                      value: _priority,
                      options: [
                        for (final priority in TaskPriority.values)
                          _Option(
                            value: priority,
                            label: priority.label,
                            color: priorityColor(priority),
                          ),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => _priority = value);
                        }
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          const _FieldLabel('Due date'),
          _DateField(
            value: _dueDate,
            hint: 'No due date',
            onTap: () => _pickDate(
              current: _dueDate,
              onPicked: (date) => setState(() => _dueDate = date),
            ),
            onClear: () => setState(() => _dueDate = null),
          ),
          const SizedBox(height: 16),

          const _FieldLabel('Timeline'),
          Row(
            children: [
              Expanded(
                child: _DateField(
                  value: _startDate,
                  hint: 'Start',
                  onTap: () => _pickDate(
                    current: _startDate,
                    onPicked: (date) => setState(() {
                      _startDate = date;
                      // Moving the start past the end would leave a
                      // backwards timeline, which the database rejects
                      // outright. Carry the end along instead of saving
                      // something that cannot be stored.
                      final end = _endDate;
                      if (date != null && end != null && end.isBefore(date)) {
                        _endDate = date;
                      }
                    }),
                  ),
                  onClear: () => setState(() => _startDate = null),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Icon(
                  Icons.arrow_forward_rounded,
                  size: 14,
                  color: plannerFaint,
                ),
              ),
              Expanded(
                child: _DateField(
                  value: _endDate,
                  hint: 'End',
                  onTap: () => _pickDate(
                    current: _endDate ?? _startDate,
                    // A timeline cannot end before it starts, so the
                    // picker will not offer those days at all.
                    notBefore: _startDate,
                    onPicked: (date) => setState(() => _endDate = date),
                  ),
                  onClear: () => setState(() => _endDate = null),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),

          // Matches the slider's inset below, so the label and percentage
          // line up with the ends of the track.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                const _FieldLabel('Progress'),
                const Spacer(),
                Text(
                  '${(_progress * 100).round()}%',
                  style: const TextStyle(
                    color: plannerInk,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          // Inset by the thumb radius: at 0% the thumb sits centred on the
          // track start, so without this its left half is clipped by the
          // dialog edge.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 6,
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                // The track already spans the padded width; removing the
                // theme's own inset keeps the ends aligned with the labels.
                trackShape: const RectangularSliderTrackShape(),
              ),
              child: Slider(
                value: _progress,
                onChanged: (value) => setState(() {
                  _progress = value;
                  // Keep status coherent with progress, matching the rule the
                  // repository enforces. Which of the board's labels means
                  // finished or not-started is read from their flags.
                  if (value >= 1) {
                    _statusId = _firstStatus((s) => s.isDone)?.id ?? _statusId;
                  } else if (value <= 0) {
                    _statusId =
                        _firstStatus((s) => s.isDefault)?.id ?? _statusId;
                  } else if (_status?.isDone ?? false) {
                    // Moving off 100% should leave the done column, but any
                    // mid-progress label will do — the board names its own.
                    _statusId =
                        _firstStatus((s) => !s.isDone && !s.isDefault)?.id ??
                        _statusId;
                  }
                }),
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(widget.task == null ? 'Create task' : 'Save changes'),
        ),
      ],
    );
  }
}

/// Picks any number of teammates for a task.
///
/// MenuAnchor rather than PopupMenuButton: the latter closes on every
/// selection — `onSelected` dismisses before the handler runs — so assigning
/// three people meant reopening the menu three times. This stays open until
/// dismissed, and the ticks update in place as you go.
class _AssigneePicker extends StatefulWidget {
  const _AssigneePicker({
    required this.members,
    required this.selected,
    required this.onChanged,
  });

  final List<WorkspaceMember> members;
  final List<String> selected;
  final ValueChanged<List<String>> onChanged;

  @override
  State<_AssigneePicker> createState() => _AssigneePickerState();
}

class _AssigneePickerState extends State<_AssigneePicker> {
  final MenuController _menu = MenuController();

  void _toggle(String id) {
    final next = [...widget.selected];
    if (!next.remove(id)) {
      next.add(id);
    }
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final chosen = widget.members
        .where((member) => widget.selected.contains(member.profile.id))
        .toList();

    return MenuAnchor(
      controller: _menu,
      alignmentOffset: const Offset(0, 4),
      style: MenuStyle(
        backgroundColor: WidgetStateProperty.all(plannerCard),
        surfaceTintColor: WidgetStateProperty.all(Colors.transparent),
        padding: WidgetStateProperty.all(
          const EdgeInsets.symmetric(vertical: 4),
        ),
        shape: WidgetStateProperty.all(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMd),
            side: const BorderSide(color: plannerBorder),
          ),
        ),
        // Matches the field it drops from, so the two read as one control.
        minimumSize: WidgetStateProperty.all(const Size(240, 0)),
        maximumSize: WidgetStateProperty.all(const Size(320, 280)),
      ),
      menuChildren: [
        if (widget.members.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Text(
              'No one else is in this workspace yet.',
              style: TextStyle(color: plannerMuted, fontSize: 12),
            ),
          )
        else
          for (final member in widget.members)
            _AssigneeOption(
              member: member,
              selected: widget.selected.contains(member.profile.id),
              onTap: () => _toggle(member.profile.id),
            ),
      ],
      builder: (context, controller, _) {
        return InkWell(
          onTap: () =>
              controller.isOpen ? controller.close() : controller.open(),
          borderRadius: BorderRadius.circular(radiusSm),
          child: Container(
            height: 42,
            padding: const EdgeInsets.symmetric(horizontal: 11),
            decoration: BoxDecoration(
              color: plannerCard,
              borderRadius: BorderRadius.circular(radiusSm),
              border: Border.all(
                color: controller.isOpen ? plannerBlue : plannerBorder,
              ),
            ),
            child: Row(
              children: [
                if (chosen.isEmpty)
                  const Expanded(
                    child: Text(
                      'Unassigned',
                      style: TextStyle(color: plannerFaint, fontSize: 13),
                    ),
                  )
                else ...[
                  AvatarStack(
                    profiles: [for (final member in chosen) member.profile],
                    size: 22,
                    maxVisible: 3,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      chosen.length == 1
                          ? chosen.first.profile.displayName
                          : '${chosen.length} people',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: plannerText, fontSize: 13),
                    ),
                  ),
                ],
                Icon(
                  controller.isOpen
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  size: 18,
                  color: plannerFaint,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// One person in the assignee menu.
///
/// A checkbox rather than a trailing tick: this is a multi-select, and the box
/// says so before you have picked anything.
class _AssigneeOption extends StatefulWidget {
  const _AssigneeOption({
    required this.member,
    required this.selected,
    required this.onTap,
  });

  final WorkspaceMember member;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_AssigneeOption> createState() => _AssigneeOptionState();
}

class _AssigneeOptionState extends State<_AssigneeOption> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final profile = widget.member.profile;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setHoverSafely(this, () => _hovered = true),
      onExit: (_) => setHoverSafely(this, () => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          color: _hovered ? plannerHover : Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: Checkbox(
                  value: widget.selected,
                  onChanged: (_) => widget.onTap(),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  side: const BorderSide(color: plannerFaint, width: 1.5),
                ),
              ),
              const SizedBox(width: 10),
              UserAvatar(profile: profile, size: 22, showTooltip: false),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      profile.displayName,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: plannerInk,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      widget.member.role.label,
                      style: const TextStyle(
                        color: plannerFaint,
                        fontSize: 10.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One choice in a [_DropdownField]: a colour dot and a label.
class _Option<T> {
  const _Option({required this.value, required this.label, this.color});

  final T value;
  final String label;

  /// Drawn as a dot beside the label. Null for choices with no colour of
  /// their own, where the label carries the whole meaning.
  final Color? color;
}

/// A select that drops *below* its field.
///
/// DropdownButtonFormField positions its menu over the button and lets it
/// spread sideways, so opening Priority covered Status and Due date beside it.
/// MenuAnchor anchors under the field at the field's own width, which is what
/// a select is supposed to look like.
class _DropdownField<T> extends StatefulWidget {
  const _DropdownField({
    required this.value,
    required this.options,
    required this.onChanged,
    this.placeholder = 'Select…',
  });

  final T value;
  final List<_Option<T>> options;
  final ValueChanged<T?> onChanged;
  final String placeholder;

  @override
  State<_DropdownField<T>> createState() => _DropdownFieldState<T>();
}

class _DropdownFieldState<T> extends State<_DropdownField<T>> {
  final MenuController _menu = MenuController();
  final GlobalKey _fieldKey = GlobalKey();

  _Option<T>? get _selected {
    for (final option in widget.options) {
      if (option.value == widget.value) {
        return option;
      }
    }
    return null;
  }

  /// The field's rendered width, so the menu matches it rather than sizing to
  /// its longest label.
  double get _fieldWidth {
    final box = _fieldKey.currentContext?.findRenderObject() as RenderBox?;
    return box?.size.width ?? 200;
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selected;

    return MenuAnchor(
      controller: _menu,
      alignmentOffset: const Offset(0, 4),
      style: MenuStyle(
        backgroundColor: WidgetStateProperty.all(plannerCard),
        surfaceTintColor: WidgetStateProperty.all(Colors.transparent),
        padding: WidgetStateProperty.all(
          const EdgeInsets.symmetric(vertical: 4),
        ),
        shape: WidgetStateProperty.all(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMd),
            side: const BorderSide(color: plannerBorder),
          ),
        ),
        minimumSize: WidgetStateProperty.all(Size(_fieldWidth, 0)),
        maximumSize: WidgetStateProperty.all(Size(_fieldWidth, 260)),
      ),
      menuChildren: [
        for (final option in widget.options)
          _DropdownOption<T>(
            option: option,
            selected: option.value == widget.value,
            onTap: () {
              _menu.close();
              widget.onChanged(option.value);
            },
          ),
      ],
      builder: (context, controller, _) {
        return InkWell(
          key: _fieldKey,
          onTap: () =>
              controller.isOpen ? controller.close() : controller.open(),
          borderRadius: BorderRadius.circular(radiusSm),
          child: Container(
            height: 42,
            padding: const EdgeInsets.symmetric(horizontal: 11),
            decoration: BoxDecoration(
              color: plannerCard,
              borderRadius: BorderRadius.circular(radiusSm),
              border: Border.all(
                color: controller.isOpen ? plannerBlue : plannerBorder,
              ),
            ),
            child: Row(
              children: [
                if (selected?.color != null) ...[
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: selected!.color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(
                    selected?.label ?? widget.placeholder,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: selected == null ? plannerFaint : plannerText,
                      fontSize: 13,
                    ),
                  ),
                ),
                Icon(
                  controller.isOpen
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  size: 18,
                  color: plannerFaint,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _DropdownOption<T> extends StatefulWidget {
  const _DropdownOption({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final _Option<T> option;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_DropdownOption<T>> createState() => _DropdownOptionState<T>();
}

class _DropdownOptionState<T> extends State<_DropdownOption<T>> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final option = widget.option;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setHoverSafely(this, () => _hovered = true),
      onExit: (_) => setHoverSafely(this, () => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          color: _hovered
              ? plannerHover
              : (widget.selected
                    ? tint(plannerBlue, 0.06)
                    : Colors.transparent),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Row(
            children: [
              if (option.color != null) ...[
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: option.color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 9),
              ],
              Expanded(
                child: Text(
                  option.label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: plannerInk,
                    fontSize: 13,
                    fontWeight: widget.selected
                        ? FontWeight.w600
                        : FontWeight.w400,
                  ),
                ),
              ),
              if (widget.selected)
                const Icon(Icons.check_rounded, size: 15, color: plannerBlue),
            ],
          ),
        ),
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.value,
    required this.hint,
    required this.onTap,
    required this.onClear,
  });

  final DateTime? value;
  final String hint;
  final VoidCallback onTap;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final hasValue = value != null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(radiusSm),
      child: Container(
        height: 42,
        padding: const EdgeInsets.symmetric(horizontal: 11),
        decoration: BoxDecoration(
          color: plannerCard,
          borderRadius: BorderRadius.circular(radiusSm),
          border: Border.all(color: plannerBorder),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.calendar_today_rounded,
              size: 14,
              color: plannerFaint,
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                hasValue ? formatDate(value!) : hint,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: hasValue ? plannerText : plannerFaint,
                  fontSize: 13,
                ),
              ),
            ),
            if (hasValue)
              InkWell(
                onTap: onClear,
                borderRadius: BorderRadius.circular(radiusXs),
                child: const Padding(
                  padding: EdgeInsets.all(2),
                  child: Icon(
                    Icons.close_rounded,
                    size: 14,
                    color: plannerFaint,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Text(
        text,
        style: const TextStyle(
          color: plannerInk,
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

// === Dates ===

const List<String> _monthNames = [
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

/// "12 Mar", with the year appended when it is not the current one.
String formatDate(DateTime date) {
  final month = _monthNames[date.month - 1];
  final now = DateTime.now();
  if (date.year == now.year) {
    return '${date.day} $month';
  }
  return '${date.day} $month ${date.year}';
}

/// When a chat message was sent, in words a reader does not have to decode:
/// "2:14 PM" for today, "Yesterday 2:14 PM", then "12 Mar, 2:14 PM" with the
/// year appended once it differs.
String chatTimestamp(DateTime when) {
  final hour = when.hour % 12 == 0 ? 12 : when.hour % 12;
  final minute = when.minute.toString().padLeft(2, '0');
  final time = '$hour:$minute ${when.hour < 12 ? 'AM' : 'PM'}';

  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(when.year, when.month, when.day);
  if (day == today) {
    return time;
  }
  if (day == today.subtract(const Duration(days: 1))) {
    return 'Yesterday $time';
  }
  return '${formatDate(when)}, $time';
}

/// Relative time for note timestamps.
String formatRelative(DateTime time) {
  final diff = DateTime.now().difference(time);
  if (diff.inSeconds < 60) {
    return 'just now';
  }
  if (diff.inMinutes < 60) {
    return '${diff.inMinutes}m ago';
  }
  if (diff.inHours < 24) {
    return '${diff.inHours}h ago';
  }
  if (diff.inDays < 7) {
    return '${diff.inDays}d ago';
  }
  return formatDate(time);
}

// === Notes ===

/// Builds a Quill document from stored note content (Delta JSON, or legacy
/// Opens a task's chat.
///
/// Replaces the sticky-note thread that came before. Notes were coloured cards
/// with positions and pinning; teams used them to write messages to each other,
/// so this is the shape the use already had.
Future<void> showTaskChatDialog({
  required BuildContext context,
  required PlannerTask task,
  required PlannerRepository repository,
  required List<WorkspaceMember> members,
  required String currentUserId,
  required bool canEdit,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => _TaskChatDialog(
      task: task,
      repository: repository,
      members: members,
      currentUserId: currentUserId,
      canEdit: canEdit,
    ),
  );
}

class _TaskChatDialog extends StatefulWidget {
  const _TaskChatDialog({
    required this.task,
    required this.repository,
    required this.members,
    required this.currentUserId,
    required this.canEdit,
  });

  final PlannerTask task;
  final PlannerRepository repository;
  final List<WorkspaceMember> members;
  final String currentUserId;

  /// Viewers read the conversation but cannot add to it.
  final bool canEdit;

  @override
  State<_TaskChatDialog> createState() => _TaskChatDialogState();
}

class _TaskChatDialogState extends State<_TaskChatDialog> {
  final TextEditingController _composer = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final FocusNode _composerFocus = FocusNode();

  List<TaskComment> _comments = [];

  bool _loading = true;
  bool _sending = false;
  String? _error;
  RealtimeChannel? _channel;

  /// When each member last had this chat open, for the "Seen by" line.
  Map<String, DateTime> _reads = {};
  RealtimeChannel? _readsChannel;

  /// Set while replying, so the composer posts into that thread.
  TaskComment? _replyingTo;

  /// Set while editing, so Send saves instead of posting.
  TaskComment? _editing;

  /// Mention autocomplete, driven by what has been typed after an `@`.
  List<WorkspaceMember> _mentionMatches = [];

  /// Whether `@everyone` is among the current suggestions.
  bool _showEveryone = false;

  List<({TaskComment comment, TaskComment? parent})> get _timeline =>
      buildTimeline(_comments);

  @override
  void initState() {
    super.initState();
    _load();
    _channel = widget.repository.subscribeToTaskChat(
      taskId: widget.task.id,
      onChange: () {
        if (mounted) {
          _load();
        }
      },
    );
    _loadReads();
    _readsChannel = widget.repository.subscribeToChatReads(
      taskId: widget.task.id,
      onChange: () {
        if (mounted) {
          _loadReads();
        }
      },
    );
    _composer.addListener(_updateMentionMatches);
  }

  /// Read receipts are decoration on the conversation — any failure here
  /// stays silent rather than getting between people and their messages.
  Future<void> _loadReads() async {
    try {
      final reads = await widget.repository.chatReads(widget.task.id);
      if (mounted) {
        setState(() => _reads = reads);
      }
    } catch (_) {}
  }

  Future<void> _markRead() async {
    try {
      await widget.repository.markChatRead(widget.task.id);
    } catch (_) {}
  }

  /// Teammates (other than the newest message's author) whose last visit is
  /// at or past the newest message — the "everyone has seen this" answer.
  List<String> get _seenByNames {
    if (_comments.isEmpty) {
      return const [];
    }
    var last = _comments.first;
    for (final comment in _comments) {
      if (comment.createdAt.isAfter(last.createdAt)) {
        last = comment;
      }
    }
    final names = <String>[];
    for (final member in widget.members) {
      final id = member.profile.id;
      if (id == widget.currentUserId || id == last.author?.id) {
        continue;
      }
      final at = _reads[id];
      if (at != null && !at.isBefore(last.createdAt)) {
        names.add(member.profile.displayName);
      }
    }
    return names;
  }

  @override
  void dispose() {
    _composer.dispose();
    _scroll.dispose();
    _composerFocus.dispose();
    final channel = _channel;
    if (channel != null) {
      widget.repository.unsubscribe(channel);
    }
    final readsChannel = _readsChannel;
    if (readsChannel != null) {
      widget.repository.unsubscribe(readsChannel);
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final comments = await widget.repository.loadComments(widget.task.id);
      if (!mounted) {
        return;
      }
      final wasAtBottom = _isAtBottom;
      setState(() {
        _comments = comments;
        _loading = false;
        _error = null;
      });
      // Having the chat open means having read it — on arrival and again for
      // every message that lands while it stays open.
      unawaited(_markRead());
      // Only follow the conversation if they were already at the end. Yanking
      // someone away from what they were reading is worse than a missed line.
      if (wasAtBottom) {
        _scrollToBottom();
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = error.toString();
        });
      }
    }
  }

  bool get _isAtBottom {
    if (!_scroll.hasClients) {
      return true;
    }
    return _scroll.position.pixels >= _scroll.position.maxScrollExtent - 60;
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  /// The word being typed after an `@`, or null when not mentioning.
  String? get _mentionQuery {
    final text = _composer.text;
    final caret = _composer.selection.baseOffset;
    if (caret <= 0 || caret > text.length) {
      return null;
    }
    final upToCaret = text.substring(0, caret);
    final at = upToCaret.lastIndexOf('@');
    if (at < 0) {
      return null;
    }
    // An @ mid-word is an email address, not a mention.
    if (at > 0 && !RegExp(r'\s').hasMatch(upToCaret[at - 1])) {
      return null;
    }
    final query = upToCaret.substring(at + 1);
    // A space ends the mention, so "@Ana and" stops offering after "Ana".
    return query.contains('\n') ? null : query;
  }

  void _updateMentionMatches() {
    final query = _mentionQuery;
    if (query == null) {
      if (_mentionMatches.isNotEmpty || _showEveryone) {
        setState(() {
          _mentionMatches = [];
          _showEveryone = false;
        });
      }
      return;
    }
    final needle = query.toLowerCase();
    setState(() {
      _mentionMatches = widget.members
          .where((m) => m.profile.id != widget.currentUserId)
          .where((m) => m.profile.displayName.toLowerCase().contains(needle))
          .take(5)
          .toList();
      // @everyone leads when it matches: asking the whole team is usually
      // what you mean by typing "@e", and it is not a person so it cannot
      // come from the member list.
      _showEveryone = 'everyone'.startsWith(needle);
    });
  }

  /// Completes the half-typed mention with `@everyone`.
  void _insertEveryone() => _insertMentionText('everyone');

  /// Completes the half-typed mention with a real name.
  void _insertMention(WorkspaceMember member) =>
      _insertMentionText(member.profile.displayName);

  /// Replaces the partial `@…` before the caret with [name].
  void _insertMentionText(String name) {
    final text = _composer.text;
    final caret = _composer.selection.baseOffset;
    final at = text.substring(0, caret).lastIndexOf('@');
    if (at < 0) {
      return;
    }
    final next = '${text.substring(0, at)}@$name ${text.substring(caret)}';
    _composer.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: at + name.length + 2),
    );
    setState(() {
      _mentionMatches = [];
      _showEveryone = false;
    });
    _composerFocus.requestFocus();
  }

  Future<void> _send() async {
    final body = _composer.text.trim();
    if (body.isEmpty || _sending) {
      return;
    }
    // Checked here as well as on the field. maxLength stops typing, but the
    // trim above can only shrink the text and a paste arrives all at once —
    // and task_comments_body_length would reject it as a raw constraint error
    // rather than something the user can act on.
    if (body.length > commentMaxLength) {
      setState(() {
        _error =
            'That message is ${body.length} characters. '
            'The limit is $commentMaxLength.';
      });
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });

    try {
      final editing = _editing;
      if (editing != null) {
        await widget.repository.editComment(commentId: editing.id, body: body);
      } else {
        await widget.repository.addComment(
          taskId: widget.task.id,
          body: body,
          parentId: _replyingTo?.id,
        );
      }
      _composer.clear();
      if (mounted) {
        setState(() {
          _replyingTo = null;
          _editing = null;
          _mentionMatches = [];
          _showEveryone = false;
        });
      }
      await _load();
      _scrollToBottom();
    } catch (error) {
      if (mounted) {
        setState(() => _error = _readable(error));
      }
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  void _startEditing(TaskComment comment) {
    setState(() {
      _editing = comment;
      _replyingTo = null;
    });
    _composer.text = comment.body;
    _composer.selection = TextSelection.collapsed(offset: comment.body.length);
    _composerFocus.requestFocus();
  }

  void _startReply(TaskComment comment) {
    setState(() {
      _replyingTo = comment;
      _editing = null;
    });
    _composerFocus.requestFocus();
  }

  void _cancelComposerMode() {
    setState(() {
      _replyingTo = null;
      _editing = null;
    });
    _composer.clear();
  }

  Future<void> _delete(TaskComment comment) async {
    final confirmed = await showDeleteConfirmDialog(
      context: context,
      title: 'Delete message',
      message: 'This removes it for everyone. Replies to it stay.',
    );
    if (!confirmed) {
      return;
    }
    try {
      await widget.repository.deleteComment(comment.id);
      await _load();
    } catch (error) {
      if (mounted) {
        setState(() => _error = _readable(error));
      }
    }
  }

  Future<void> _react(TaskComment comment, String emoji) async {
    final add = !comment.myReactions.contains(emoji);
    // Optimistic: the chip flips the moment it is clicked. The old flow
    // waited for the server and then reloaded the whole conversation, so a
    // reaction landed a beat late and the list visibly churned — which read
    // as "reactions are buggy". The realtime echo still reconciles this
    // against the server's truth moments later.
    _applyReactionLocally(comment.id, emoji, add: add);
    try {
      await widget.repository.toggleCommentReaction(
        commentId: comment.id,
        emoji: emoji,
        add: add,
      );
    } catch (_) {
      // Rolled back rather than surfaced: a reaction failing is not worth
      // interrupting the conversation over, but the chip must not lie.
      _applyReactionLocally(comment.id, emoji, add: !add);
    }
  }

  void _applyReactionLocally(
    String commentId,
    String emoji, {
    required bool add,
  }) {
    TaskComment update(TaskComment comment) {
      if (comment.id != commentId) {
        if (comment.replies.isEmpty) {
          return comment;
        }
        return comment.copyWith(
          replies: [for (final reply in comment.replies) update(reply)],
        );
      }
      final mine = Set<String>.from(comment.myReactions);
      final counts = Map<String, int>.from(comment.reactions);
      final users = {
        for (final entry in comment.reactionUsers.entries)
          entry.key: List<String>.from(entry.value),
      };
      final me = widget.currentUserId;
      if (add && !mine.contains(emoji)) {
        mine.add(emoji);
        counts[emoji] = (counts[emoji] ?? 0) + 1;
        users.putIfAbsent(emoji, () => []).add(me);
      } else if (!add && mine.contains(emoji)) {
        mine.remove(emoji);
        final remaining = (counts[emoji] ?? 1) - 1;
        if (remaining <= 0) {
          counts.remove(emoji);
          users.remove(emoji);
        } else {
          counts[emoji] = remaining;
          users[emoji]?.remove(me);
        }
      }
      return comment.copyWith(
        reactions: counts,
        myReactions: mine,
        reactionUsers: users,
      );
    }

    setState(() {
      _comments = [for (final comment in _comments) update(comment)];
    });
  }

  String _readable(Object error) =>
      error is StateError ? error.message : error.toString();

  int get _messageCount =>
      _comments.length +
      _comments.fold(0, (sum, comment) => sum + comment.replies.length);

  @override
  Widget build(BuildContext context) {
    // Built once per frame: the getter sorts, so reading it inside itemBuilder
    // would re-sort the whole conversation for every visible row.
    final timeline = _timeline;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 32),
      child: Container(
        width: 620,
        constraints: const BoxConstraints(maxHeight: 720),
        decoration: BoxDecoration(
          color: plannerCard,
          borderRadius: BorderRadius.circular(radiusLg),
          boxShadow: shadowLg,
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ChatHeader(
              title: widget.task.title,
              messageCount: _messageCount,
              onClose: () => Navigator.of(context).pop(),
            ),
            if (_error != null) _ChatError(message: _error!),
            Flexible(
              child: _loading
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 60),
                      child: Center(
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      ),
                    )
                  : _comments.isEmpty
                  ? const _ChatEmpty()
                  : Align(
                      // Bottom, so a short conversation grows up out of the
                      // composer instead of hanging from the header.
                      alignment: Alignment.bottomCenter,
                      // SelectionArea rather than per-message SelectableText:
                      // it lets a drag sweep across several messages and copy
                      // them together, and it leaves the link spans inside
                      // free to take taps.
                      child: SelectionArea(
                        child: ListView.builder(
                          controller: _scroll,
                          padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
                          // Messages stack up from the composer, the way every
                          // chat does. Without this a conversation with two
                          // messages in it pinned them to the top of the panel
                          // with a field of empty white beneath, as far from the
                          // box you type in as the layout allowed.
                          //
                          // This only affects the short case: once the messages
                          // are taller than the viewport the alignment has nothing
                          // left to give and the list scrolls normally.
                          //
                          // shrinkWrap lets the viewport size to its content so
                          // there is slack for the alignment to consume; without
                          // it the list always claims the full height and sits at
                          // the top regardless.
                          shrinkWrap: true,
                          itemCount: timeline.length,
                          itemBuilder: (context, index) {
                            final entry = timeline[index];
                            final comment = entry.comment;
                            // A run by one person shows their name once. Three
                            // identical bylines in a column was the list telling
                            // you what you could already see. A reply always
                            // breaks the run, because it carries a quote above it.
                            final previous = index > 0
                                ? timeline[index - 1]
                                : null;
                            // Messenger-style: the date and time stand between
                            // messages as a centred divider whenever the
                            // conversation pauses, rather than cluttering every
                            // byline. A divider also breaks the author run.
                            final timeBreak =
                                previous == null ||
                                comment.createdAt
                                        .difference(previous.comment.createdAt)
                                        .inMinutes >=
                                    20;
                            final bubble = _MessageBubble(
                              comment: comment,
                              replyingTo: entry.parent,
                              grouped:
                                  !timeBreak &&
                                  entry.parent == null &&
                                  previous.comment.author?.id ==
                                      comment.author?.id,
                              members: widget.members,
                              currentUserId: widget.currentUserId,
                              // Replies stay one deep: you answer the message,
                              // not the answer.
                              onReply: entry.parent == null
                                  ? () => _startReply(comment)
                                  : null,
                              onEdit: () => _startEditing(comment),
                              onDelete: () => _delete(comment),
                              onReact: (emoji) => _react(comment, emoji),
                            );
                            if (!timeBreak) {
                              return bubble;
                            }
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _TimeDivider(comment.createdAt),
                                bubble,
                              ],
                            );
                          },
                        ),
                      ),
                    ),
            ),
            // "Seen by" sits under the newest message, where every messenger
            // puts it. Only teammates who are caught up are named; an empty
            // line would just be noise.
            if (_seenByNames.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 5),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    const Icon(
                      Icons.done_all_rounded,
                      size: 12,
                      color: plannerFaint,
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        'Seen by ${_seenByNames.join(', ')}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: plannerFaint,
                          fontSize: 10.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (_mentionMatches.isNotEmpty || _showEveryone)
              _MentionSuggestions(
                matches: _mentionMatches,
                showEveryone: _showEveryone,
                memberCount: widget.members.length,
                onPickEveryone: _insertEveryone,
                onPick: _insertMention,
              ),
            if (!widget.canEdit)
              const _ReadOnlyNotice()
            else
              _Composer(
                controller: _composer,
                focusNode: _composerFocus,
                sending: _sending,
                replyingTo: _replyingTo,
                editing: _editing,
                onSend: _send,
                onCancel: _cancelComposerMode,
              ),
          ],
        ),
      ),
    );
  }
}

/// The centred "Yesterday 2:14 PM" strip between messages, marking where the
/// conversation paused — the way Messenger dates a thread.
class _TimeDivider extends StatelessWidget {
  const _TimeDivider(this.when);

  final DateTime when;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 2),
      child: Center(
        child: Text(
          chatTimestamp(when),
          style: const TextStyle(
            color: plannerFaint,
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
        ),
      ),
    );
  }
}

/// Shown instead of the composer for viewers, who can read the conversation
/// but not add to it. An input that silently refuses would be worse.
class _ReadOnlyNotice extends StatelessWidget {
  const _ReadOnlyNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: const BoxDecoration(
        color: plannerSurface,
        border: Border(top: BorderSide(color: plannerDivider)),
      ),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.visibility_outlined, size: 14, color: plannerMuted),
          SizedBox(width: 7),
          Text(
            'You have view-only access to this workspace.',
            style: TextStyle(color: plannerMuted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

/// The lid on the conversation.
///
/// Dark rather than another white bar: the chat sits inside a white dialog on
/// a white board, and without a ground of its own the panel had no edges.
///
/// It shows no roster. One was built from the message authors, which made it a
/// list of who had *spoken* while presenting as who was *there* — misleading in
/// a chat any workspace member can post in. The subtitle says so instead.
class _ChatHeader extends StatelessWidget {
  const _ChatHeader({
    required this.title,
    required this.messageCount,
    required this.onClose,
  });

  final String title;
  final int messageCount;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 15, 12, 15),
      decoration: const BoxDecoration(color: plannerSidebar),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(radiusSm),
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.forum_rounded,
              size: 16,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  messageCount == 0
                      ? 'Visible to the whole workspace'
                      : '$messageCount '
                            '${messageCount == 1 ? 'message' : 'messages'}'
                            ' · whole workspace',
                  style: const TextStyle(
                    color: Color(0xFF9096B8),
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),
          _HeaderCloseButton(onClose: onClose),
        ],
      ),
    );
  }
}

/// Close, styled for the dark header — the default IconButton hover is a pale
/// wash that disappears against it.
class _HeaderCloseButton extends StatefulWidget {
  const _HeaderCloseButton({required this.onClose});

  final VoidCallback onClose;

  @override
  State<_HeaderCloseButton> createState() => _HeaderCloseButtonState();
}

class _HeaderCloseButtonState extends State<_HeaderCloseButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Close',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setHoverSafely(this, () => _hovered = true),
        onExit: (_) => setHoverSafely(this, () => _hovered = false),
        child: GestureDetector(
          onTap: widget.onClose,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: _hovered
                  ? Colors.white.withValues(alpha: 0.12)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(radiusSm),
            ),
            alignment: Alignment.center,
            child: Icon(
              Icons.close_rounded,
              size: 17,
              color: _hovered ? Colors.white : const Color(0xFF9096B8),
            ),
          ),
        ),
      ),
    );
  }
}

class _ChatError extends StatelessWidget {
  const _ChatError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      color: tint(plannerRed, 0.08),
      child: Text(
        message,
        style: const TextStyle(color: plannerRed, fontSize: 12),
      ),
    );
  }
}

class _ChatEmpty extends StatelessWidget {
  const _ChatEmpty();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 56, horizontal: 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(Icons.forum_outlined, size: 26, color: plannerFaint),
          SizedBox(height: 12),
          Text(
            'No messages yet',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: plannerText,
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: 4),
          Text(
            'Ask a question, flag a blocker, or note a decision. '
            'Type @ to bring someone in.',
            textAlign: TextAlign.center,
            style: TextStyle(color: plannerMuted, fontSize: 12, height: 1.4),
          ),
        ],
      ),
    );
  }
}

/// Flattens a threaded conversation into one strictly chronological list.
///
/// Replies used to render nested under their parent, which meant answering an
/// old message dragged that whole thread down to the bottom — so a brand new
/// message could appear *above* something older, which is not how any chat
/// behaves. Messenger does not nest either: a reply sits at its own place in
/// time and quotes what it answers. The quote carries the threading now, so the
/// list can stay in the one order a conversation actually has.
List<({TaskComment comment, TaskComment? parent})> buildTimeline(
  List<TaskComment> comments,
) {
  final flat = <({TaskComment comment, TaskComment? parent})>[];
  for (final comment in comments) {
    flat.add((comment: comment, parent: null));
    for (final reply in comment.replies) {
      flat.add((comment: reply, parent: comment));
    }
  }
  flat.sort((a, b) => a.comment.createdAt.compareTo(b.comment.createdAt));
  return flat;
}

/// Sets hover state without rebuilding mid-hit-test.
///
/// A MouseRegion callback runs *inside* the mouse tracker's device update, and
/// calling setState there rebuilds the tree it is still walking — Flutter
/// asserts `!_debugDuringDeviceUpdate` and the frame is abandoned, which on a
/// dialog leaves the barrier painted and the content missing.
///
/// It only bites for widgets inside an overlay, where the rebuild can add or
/// remove regions the tracker has not visited yet. Deferring by one frame
/// costs nothing visible and is correct everywhere.
void setHoverSafely(State state, VoidCallback apply) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (state.mounted) {
      // ignore: invalid_use_of_protected_member
      state.setState(apply);
    }
  });
}

/// A count that fits a badge.
///
/// Three digits do not fit a 15px circle, so anything past 99 becomes "99+" —
/// the exact number stops mattering long before that, and the tooltip still
/// carries it for anyone who wants it.
String compactCount(int count) {
  if (count > 999) {
    return '999+';
  }
  if (count > 99) {
    return '99+';
  }
  return '$count';
}

/// The quick reactions offered on hover.
///
/// Deliberately few, and deliberately one row: a long picker turns a one-tap
/// acknowledgement into a decision. Five is the most that fits at a size worth
/// aiming at.
const List<String> quickReactions = ['👍', '❤️', '✅', '🎉', '👀', '🙏'];

class _MessageBubble extends StatefulWidget {
  const _MessageBubble({
    required this.comment,
    required this.members,
    required this.currentUserId,
    required this.onEdit,
    required this.onDelete,
    required this.onReact,
    this.onReply,
    this.grouped = false,
    this.replyingTo,
  });

  final TaskComment comment;
  final List<WorkspaceMember> members;
  final String currentUserId;
  final VoidCallback? onReply;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final ValueChanged<String> onReact;

  /// True when the message above is from the same person. Runs by one author
  /// show their avatar and name once rather than on every line.
  final bool grouped;

  /// The message this one answers, quoted above it. Null for anything that is
  /// not a reply, and for later replies in the same run.
  final TaskComment? replyingTo;

  @override
  State<_MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<_MessageBubble> {
  bool _hovered = false;

  bool get _isMine => widget.comment.author?.id == widget.currentUserId;

  bool get _mentionsMe =>
      widget.comment.mentionedIds.contains(widget.currentUserId);

  /// Copies the message text, with feedback — a silent copy is
  /// indistinguishable from a click that did nothing.
  void _copyBody(BuildContext context) {
    Clipboard.setData(ClipboardData(text: widget.comment.body));
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Message copied'),
          duration: Duration(seconds: 2),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final comment = widget.comment;
    final author = comment.author;

    return MouseRegion(
      onEnter: (_) => setHoverSafely(this, () => _hovered = true),
      onExit: (_) => setHoverSafely(this, () => _hovered = false),
      child: Padding(
        // A tighter gap inside a run than between them, so the grouping reads
        // as one person speaking rather than separate remarks.
        padding: EdgeInsets.only(top: widget.grouped ? 3 : 14),
        child: Column(
          // Your own messages sit right, everyone else left. It is the
          // strongest signal a chat has, and a column of identical rows was
          // making the reader find the name instead.
          crossAxisAlignment: _isMine
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.replyingTo != null)
              Padding(
                padding: EdgeInsets.only(
                  left: _isMine ? 0 : 38,
                  right: _isMine ? 2 : 0,
                  bottom: 3,
                ),
                child: _RepliedTo(
                  parent: widget.replyingTo!,
                  isMine: _isMine,
                  currentUserId: widget.currentUserId,
                ),
              ),
            // The byline carries only the name now — the when lives in the
            // centred time dividers and on each bubble's hover, the way
            // Messenger does it. Your own messages need no byline at all
            // unless they were edited.
            if (!widget.grouped && (!_isMine || comment.wasEdited))
              Padding(
                // Indented past the avatar column so the name sits over the
                // bubble it belongs to.
                padding: EdgeInsets.only(
                  left: _isMine ? 0 : 38,
                  right: _isMine ? 2 : 0,
                  bottom: 4,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!_isMine)
                      Text(
                        author?.displayName ?? 'Someone',
                        style: const TextStyle(
                          color: plannerInk,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    if (comment.wasEdited) ...[
                      if (!_isMine) const SizedBox(width: 5),
                      const Text(
                        'edited',
                        style: TextStyle(
                          color: plannerFaint,
                          fontSize: 10,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            Row(
              mainAxisAlignment: _isMine
                  ? MainAxisAlignment.end
                  : MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // The avatar column keeps its width even when grouped, so the
                // bubbles in a run stay aligned with one another.
                if (!_isMine)
                  SizedBox(
                    width: 38,
                    child: widget.grouped
                        ? null
                        : (author == null
                              ? const _UnknownAvatar()
                              : UserAvatar(
                                  profile: author,
                                  size: 28,
                                  showTooltip: false,
                                )),
                  ),
                // The actions ride the bubble's outer edge rather than
                // competing for room in the byline, which is where they kept
                // ending up mid-row.
                if (_isMine)
                  _HoverActions(
                    visible: _hovered,
                    isMine: true,
                    canReply: widget.onReply != null,
                    onReply: widget.onReply,
                    onCopy: () => _copyBody(context),
                    onEdit: widget.onEdit,
                    onDelete: widget.onDelete,
                    onReact: widget.onReact,
                  ),
                Flexible(
                  // Every bubble answers "when exactly?" on hover — grouped
                  // messages have no byline of their own to say it. And a
                  // right-click copies the text, for anyone who tries it
                  // before finding the hover button.
                  child: GestureDetector(
                    onSecondaryTap: () => _copyBody(context),
                    child: Tooltip(
                      message: chatTimestamp(comment.createdAt),
                      waitDuration: const Duration(milliseconds: 600),
                      child: _Bubble(
                        comment: comment,
                        members: widget.members,
                        currentUserId: widget.currentUserId,
                        isMine: _isMine,
                        mentionsMe: _mentionsMe,
                        onReact: widget.onReact,
                      ),
                    ),
                  ),
                ),
                if (!_isMine)
                  _HoverActions(
                    visible: _hovered,
                    isMine: false,
                    canReply: widget.onReply != null,
                    onReply: widget.onReply,
                    onCopy: () => _copyBody(context),
                    onEdit: widget.onEdit,
                    onDelete: widget.onDelete,
                    onReact: widget.onReact,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Who replied to whom, phrased from the viewer's seat.
///
/// Every case names a person relative to the reader: "You replied to Rin",
/// "Replied to you". An earlier version compared only the parent's author
/// against the viewer, so a reply *to* you from someone else read "Replied to
/// yourself" — naming the wrong person entirely.
String replyLabel({
  required bool replierIsMe,
  required String? targetId,
  required String? targetName,
  required String currentUserId,
}) {
  final targetIsMe = targetId == currentUserId;
  if (replierIsMe && targetIsMe) return 'You replied to yourself';

  // Capped before it lands in the label: a 40-character display name would
  // otherwise consume the line and push the quoted message out entirely.
  final name = targetName ?? 'someone';
  final short = name.length <= 18 ? name : '${name.substring(0, 17)}…';

  if (replierIsMe) return 'You replied to $short';
  if (targetIsMe) return 'Replied to you';
  return 'Replied to $short';
}

/// "You replied to Rin" — the line above a reply, quoting what it answers.
///
/// A reply used to be indicated only by indentation under a rail, which said
/// nothing about *which* message was being answered and broke entirely once
/// replies could sit on either side of the panel.
class _RepliedTo extends StatelessWidget {
  const _RepliedTo({
    required this.parent,
    required this.isMine,
    required this.currentUserId,
  });

  final TaskComment parent;
  final bool isMine;
  final String currentUserId;

  @override
  Widget build(BuildContext context) {
    final label = replyLabel(
      replierIsMe: isMine,
      targetId: parent.author?.id,
      targetName: parent.author?.displayName,
      currentUserId: currentUserId,
    );

    // One Text, not two competing ones. As a Row of two Flexibles a long name
    // and a long quote each clipped the other down to an ellipsis, leaving a
    // line that named nobody and quoted nothing. A single rich span lets the
    // label hold its width and spends whatever is left on the quote.
    return Row(
      mainAxisAlignment: isMine
          ? MainAxisAlignment.end
          : MainAxisAlignment.start,
      children: [
        // Unflipped: reply_rounded already points back at the thing being
        // answered. Mirroring it made it read as "forwarded".
        const Icon(Icons.reply_rounded, size: 12, color: plannerFaint),
        const SizedBox(width: 5),
        Flexible(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: label,
                  style: const TextStyle(
                    color: plannerMuted,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                // A snippet of the parent, so you know which message without
                // scrolling back to find it.
                const TextSpan(text: '  '),
                TextSpan(
                  text: parent.body,
                  style: const TextStyle(color: plannerFaint),
                ),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: isMine ? TextAlign.right : TextAlign.left,
            style: const TextStyle(fontSize: 10.5),
          ),
        ),
      ],
    );
  }
}

/// The message itself: its text, and any reactions beneath.
class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.comment,
    required this.members,
    required this.currentUserId,
    required this.isMine,
    required this.mentionsMe,
    required this.onReact,
  });

  final TaskComment comment;
  final List<WorkspaceMember> members;
  final String currentUserId;
  final bool isMine;
  final bool mentionsMe;
  final ValueChanged<String> onReact;

  @override
  Widget build(BuildContext context) {
    // A message naming you is worth spotting in a long thread, so it keeps its
    // amber ground whoever sent it.
    final background = mentionsMe
        ? tint(plannerYellow, 0.16)
        : (isMine ? plannerBlue : plannerSurface);

    final textColor = mentionsMe
        ? plannerInk
        : (isMine ? Colors.white : plannerText);

    return Column(
      crossAxisAlignment: isMine
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
          decoration: BoxDecoration(
            color: background,
            // The corner nearest the sender is squared off, which is what
            // makes a bubble point back at whoever wrote it.
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(radiusMd),
              topRight: const Radius.circular(radiusMd),
              bottomLeft: Radius.circular(isMine ? radiusMd : 3),
              bottomRight: Radius.circular(isMine ? 3 : radiusMd),
            ),
            border: mentionsMe
                ? Border.all(color: tint(plannerYellow, 0.5))
                : null,
          ),
          child: _MessageBody(
            body: comment.body,
            members: members,
            currentUserId: currentUserId,
            color: textColor,
            // A blue mention vanishes on a blue ground, so it inverts.
            mentionColor: isMine && !mentionsMe ? Colors.white : null,
          ),
        ),
        if (comment.reactions.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 5),
            child: _ReactionChips(
              reactions: comment.reactions,
              mine: comment.myReactions,
              users: comment.reactionUsers,
              members: members,
              currentUserId: currentUserId,
              onToggle: onReact,
            ),
          ),
      ],
    );
  }
}

/// The "..." button, faded until its message is hovered.
class _HoverActions extends StatelessWidget {
  const _HoverActions({
    required this.visible,
    required this.isMine,
    required this.canReply,
    required this.onReply,
    required this.onCopy,
    required this.onEdit,
    required this.onDelete,
    required this.onReact,
  });

  final bool visible;
  final bool isMine;
  final bool canReply;
  final VoidCallback? onReply;
  final VoidCallback onCopy;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final ValueChanged<String> onReact;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: isMine ? 0 : 4, right: isMine ? 4 : 0),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 120),
        opacity: visible ? 1 : 0,
        child: IgnorePointer(
          // Only clickable while visible, so an invisible button cannot
          // swallow taps meant for the message.
          ignoring: !visible,
          child: _MessageActions(
            isMine: isMine,
            canReply: canReply,
            onReply: onReply,
            onCopy: onCopy,
            onEdit: onEdit,
            onDelete: onDelete,
            onReact: onReact,
          ),
        ),
      ),
    );
  }
}

/// Stands in for an account that has since been deleted.
class _UnknownAvatar extends StatelessWidget {
  const _UnknownAvatar();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 28,
      decoration: const BoxDecoration(
        color: plannerSurface,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: const Icon(Icons.person_outline, size: 13, color: plannerFaint),
    );
  }
}

/// The message text, with @names picked out and links made clickable.
///
/// Stateful because link spans carry gesture recognizers, which have to be
/// disposed — and plain [Text.rich] rather than SelectableText, because
/// SelectableText swallows span taps. Selection comes from the
/// [SelectionArea] wrapped around the whole timeline instead, which also
/// lets a copy sweep across messages.
class _MessageBody extends StatefulWidget {
  const _MessageBody({
    required this.body,
    required this.members,
    required this.currentUserId,
    this.color = plannerText,
    this.mentionColor,
  });

  final String body;
  final List<WorkspaceMember> members;
  final String currentUserId;
  final Color color;

  /// Overrides the mention colour where the default would vanish — a blue
  /// mention on the blue ground of your own message.
  final Color? mentionColor;

  @override
  State<_MessageBody> createState() => _MessageBodyState();
}

class _MessageBodyState extends State<_MessageBody> {
  final List<TapGestureRecognizer> _linkTaps = [];

  static final RegExp _linkPattern = RegExp(
    r'(https?://|www\.)[^\s]+',
    caseSensitive: false,
  );

  void _disposeRecognizers() {
    for (final recognizer in _linkTaps) {
      recognizer.dispose();
    }
    _linkTaps.clear();
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _disposeRecognizers();
    return Text.rich(
      TextSpan(
        style: TextStyle(color: widget.color, fontSize: 13, height: 1.45),
        children: _spans(context),
      ),
    );
  }

  /// Links first, then mentions within the text between them.
  List<InlineSpan> _spans(BuildContext context) {
    final body = widget.body;
    final spans = <InlineSpan>[];
    var index = 0;
    for (final match in _linkPattern.allMatches(body)) {
      // Trailing punctuation belongs to the sentence, not the address.
      final url = match.group(0)!.replaceFirst(RegExp(r'[.,;:!?)\]]+$'), '');
      if (url.isEmpty) {
        continue;
      }
      if (match.start > index) {
        spans.addAll(_mentionSpans(body.substring(index, match.start)));
      }
      final recognizer = TapGestureRecognizer()
        ..onTap = () => _confirmOpenLink(context, url);
      _linkTaps.add(recognizer);
      spans.add(
        TextSpan(
          text: url,
          recognizer: recognizer,
          style: TextStyle(
            color: widget.mentionColor ?? plannerBlue,
            fontWeight: FontWeight.w600,
            decoration: TextDecoration.underline,
            decorationColor: widget.mentionColor ?? plannerBlue,
          ),
        ),
      );
      index = match.start + url.length;
    }
    if (index < body.length) {
      spans.addAll(_mentionSpans(body.substring(index)));
    }
    return spans;
  }

  /// Names the destination and waits for a yes before leaving the app — a
  /// pasted link in a chat is exactly where a misleading address would live.
  Future<void> _confirmOpenLink(BuildContext context, String raw) async {
    final normalized = raw.toLowerCase().startsWith('http')
        ? raw
        : 'https://$raw';
    final uri = Uri.tryParse(normalized);
    if (uri == null) {
      return;
    }

    final open = await showDialog<bool>(
      context: context,
      builder: (context) => AppDialog(
        icon: Icons.open_in_new_rounded,
        title: 'Open this link?',
        message: 'It opens outside Planner, in your default browser.',
        content: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: plannerSurface,
            borderRadius: BorderRadius.circular(radiusSm),
            border: Border.all(color: plannerBorder),
          ),
          child: SelectableText(
            normalized,
            style: const TextStyle(
              fontFamily: 'Consolas',
              fontSize: 12,
              height: 1.5,
              color: plannerInk,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Open link'),
          ),
        ],
      ),
    );
    if (open != true || !context.mounted) {
      return;
    }

    // Feedback that the click did something: the handoff to the browser can
    // take a beat, and silence there reads as a dead link.
    final host = uri.host.isEmpty ? normalized : uri.host;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('Opening $host in your browser…')));

    var launched = false;
    try {
      launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            backgroundColor: plannerRed,
            content: Text('Could not open that link.'),
          ),
        );
    }
  }

  /// Splits [text] around @names that match a real teammate, and @everyone.
  ///
  /// Longest name first, so "@Ana" cannot claim the start of "@Ana Maria".
  /// @everyone is not a member, so it has to be added to the pattern by hand —
  /// without it the word rendered as plain text while every other mention was
  /// coloured, which read as the feature not working.
  List<TextSpan> _mentionSpans(String text) {
    final names = widget.members.map((m) => m.profile.displayName).toList()
      ..sort((a, b) => b.length.compareTo(a.length));

    final alternatives = [...names.map(RegExp.escape), 'everyone'];
    final pattern = RegExp(
      '@(${alternatives.join('|')})',
      caseSensitive: false,
    );

    final spans = <TextSpan>[];
    var index = 0;
    for (final match in pattern.allMatches(text)) {
      if (match.start > index) {
        spans.add(TextSpan(text: text.substring(index, match.start)));
      }
      final name = match.group(1) ?? '';
      final isEveryone = name.toLowerCase() == 'everyone';
      final isMe =
          isEveryone ||
          widget.members.any(
            (m) =>
                m.profile.id == widget.currentUserId &&
                m.profile.displayName.toLowerCase() == name.toLowerCase(),
          );
      spans.add(
        TextSpan(
          text: match.group(0),
          style: TextStyle(
            // @everyone includes you, so it gets the same colour as being
            // named directly.
            color: widget.mentionColor ?? (isMe ? plannerOrange : plannerBlue),
            fontWeight: FontWeight.w600,
          ),
        ),
      );
      index = match.end;
    }
    if (index < text.length) {
      spans.add(TextSpan(text: text.substring(index)));
    }
    return spans;
  }
}

class _ReactionChips extends StatelessWidget {
  const _ReactionChips({
    required this.reactions,
    required this.mine,
    required this.users,
    required this.members,
    required this.currentUserId,
    required this.onToggle,
  });

  final Map<String, int> reactions;
  final Set<String> mine;
  final Map<String, List<String>> users;
  final List<WorkspaceMember> members;
  final String currentUserId;
  final ValueChanged<String> onToggle;

  /// "You and Ana reacted 👍" — the names behind a count, since a bare "2"
  /// answers how many but never who.
  String _whoReacted(String emoji) {
    final ids = users[emoji] ?? const [];
    final names = <String>[
      for (final id in ids)
        if (id == currentUserId)
          'You'
        else
          members
                  .where((m) => m.profile.id == id)
                  .map((m) => m.profile.displayName)
                  .firstOrNull ??
              'Someone',
    ];
    // You first, the way every messenger words it.
    names.sort((a, b) => (a == 'You' ? 0 : 1).compareTo(b == 'You' ? 0 : 1));
    if (names.isEmpty) {
      return 'React with $emoji';
    }
    final list = names.length <= 2
        ? names.join(' and ')
        : '${names.take(2).join(', ')} and ${names.length - 2} more';
    return '$list reacted $emoji';
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 5,
      runSpacing: 5,
      children: [
        for (final entry in reactions.entries)
          Tooltip(
            message: _whoReacted(entry.key),
            waitDuration: const Duration(milliseconds: 400),
            child: _ReactionChip(
              emoji: entry.key,
              count: entry.value,
              isMine: mine.contains(entry.key),
              onTap: () => onToggle(entry.key),
            ),
          ),
      ],
    );
  }
}

class _ReactionChip extends StatelessWidget {
  const _ReactionChip({
    required this.emoji,
    required this.count,
    required this.isMine,
    required this.onTap,
  });

  final String emoji;
  final int count;
  final bool isMine;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      // Animated, because the optimistic toggle makes the flip instant and a
      // hard cut at that speed reads as flicker rather than response.
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isMine ? tint(plannerBlue, 0.12) : plannerSurface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isMine ? tint(plannerBlue, 0.4) : plannerBorder,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Large enough to read the emoji, which at 11.5 was a smudge.
            Text(
              emoji,
              style: const TextStyle(
                fontSize: 14,
                fontFamily: emojiFontFamily,
                fontFamilyFallback: emojiFontFallback,
              ),
            ),
            const SizedBox(width: 5),
            Text(
              '$count',
              style: TextStyle(
                color: isMine ? plannerBlue : plannerMuted,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The per-message actions.
///
/// React and Reply sit out in the open, because they are what people reach for
/// and a menu makes a one-tap acknowledgement into three. Edit and Delete hide
/// behind "..." — rarer, and destructive enough to be worth the extra step.
///
/// They used to all live in the menu, which meant hovering a message told you
/// nothing about what you could do with it.
class _MessageActions extends StatelessWidget {
  const _MessageActions({
    required this.isMine,
    required this.canReply,
    required this.onReply,
    required this.onCopy,
    required this.onEdit,
    required this.onDelete,
    required this.onReact,
  });

  final bool isMine;
  final bool canReply;
  final VoidCallback? onReply;
  final VoidCallback onCopy;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final ValueChanged<String> onReact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
      decoration: BoxDecoration(
        color: plannerCard,
        borderRadius: BorderRadius.circular(radiusXl),
        border: Border.all(color: plannerBorder),
        boxShadow: shadowSm,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ReactAction(onReact: onReact),
          if (canReply)
            _InlineAction(
              icon: Icons.reply_rounded,
              tooltip: 'Reply',
              onTap: onReply,
            ),
          // A button, because drag-to-select and right-click both exist and
          // neither is discoverable — nothing on screen said copying was
          // possible at all.
          _InlineAction(
            icon: Icons.copy_rounded,
            tooltip: 'Copy text',
            onTap: onCopy,
          ),
          // Only your own messages have anything left to hide.
          if (isMine) _OverflowAction(onEdit: onEdit, onDelete: onDelete),
        ],
      ),
    );
  }
}

/// The emoji picker, opened from a face rather than a menu row.
class _ReactAction extends StatefulWidget {
  const _ReactAction({required this.onReact});

  final ValueChanged<String> onReact;

  @override
  State<_ReactAction> createState() => _ReactActionState();
}

class _ReactActionState extends State<_ReactAction> {
  // Held in state, not built fresh each time: a controller created in build()
  // is a new object on every rebuild and loses track of the open menu.
  final MenuController _controller = MenuController();

  @override
  Widget build(BuildContext context) {
    // A MenuAnchor, not a PopupMenuButton.
    //
    // PopupMenuItem wraps its child in an InkWell whose hover overlay spans the
    // whole item, so pointing at one emoji tinted all six. That overlay is read
    // from PopupMenuThemeData, above the item — a Theme *inside* the child
    // cannot reach it. The item also carries its own vertical padding and a
    // minimum width, which is the spacing around the strip.
    //
    // MenuAnchor hands back a plain overlay: the row is the menu, and the only
    // highlight is the one each button paints for itself.
    return MenuAnchor(
      controller: _controller,
      alignmentOffset: const Offset(0, 4),
      style: MenuStyle(
        padding: WidgetStateProperty.all(EdgeInsets.zero),
        backgroundColor: WidgetStateProperty.all(plannerCard),
        elevation: WidgetStateProperty.all(6),
        shape: WidgetStateProperty.all(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusXl),
            side: const BorderSide(color: plannerBorder),
          ),
        ),
      ),
      menuChildren: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final emoji in quickReactions)
                _ReactionPickerButton(
                  emoji: emoji,
                  // Closes on pick: unlike the assignee picker, reacting is a
                  // single choice, so staying open would just be in the way.
                  onTap: () {
                    _controller.close();
                    widget.onReact(emoji);
                  },
                ),
            ],
          ),
        ),
      ],
      builder: (context, anchor, child) {
        return MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: () => anchor.isOpen ? anchor.close() : anchor.open(),
            child: const _ActionIcon(
              icon: Icons.add_reaction_outlined,
              tooltip: 'React',
            ),
          ),
        );
      },
    );
  }
}

/// Edit and Delete, behind "...".
class _OverflowAction extends StatelessWidget {
  const _OverflowAction({required this.onEdit, required this.onDelete});

  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_MessageAction>(
      tooltip: 'More',
      offset: const Offset(0, 26),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 168, maxWidth: 200),
      onSelected: (action) {
        switch (action) {
          case _MessageAction.edit:
            onEdit();
          case _MessageAction.delete:
            onDelete();
          case _MessageAction.reply:
            break;
        }
      },
      itemBuilder: (context) => const [
        PopupMenuItem(
          value: _MessageAction.edit,
          height: 38,
          child: _MenuLine(icon: Icons.edit_outlined, label: 'Edit'),
        ),
        PopupMenuItem(
          value: _MessageAction.delete,
          height: 38,
          child: _MenuLine(
            icon: Icons.delete_outline_rounded,
            label: 'Delete',
            danger: true,
          ),
        ),
      ],
      child: const _ActionIcon(icon: Icons.more_horiz_rounded, tooltip: 'More'),
    );
  }
}

/// A single icon button in the action strip.
class _InlineAction extends StatefulWidget {
  const _InlineAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  State<_InlineAction> createState() => _InlineActionState();
}

class _InlineActionState extends State<_InlineAction> {
  @override
  Widget build(BuildContext context) {
    // Same reasoning as the emoji picker: InkWell's synchronous hover cannot
    // highlight the wrong button, and it carries the pointer cursor.
    return Tooltip(
      message: widget.tooltip,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(radiusXs),
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(radiusXs),
          hoverColor: plannerHover,
          child: SizedBox(
            width: 26,
            height: 22,
            child: Icon(widget.icon, size: 14, color: plannerMuted),
          ),
        ),
      ),
    );
  }
}

enum _MessageAction { reply, edit, delete }

/// One labelled row in the message menu.
class _MenuLine extends StatelessWidget {
  const _MenuLine({
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
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 10),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 12.5,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

/// One emoji in the reaction strip.
///
/// Its own widget so it can carry a hover state — a bare Text in a disabled
/// menu item gives no feedback at all, and the picker read as decoration
/// rather than something to tap.
class _ReactionPickerButton extends StatefulWidget {
  const _ReactionPickerButton({required this.emoji, required this.onTap});

  final String emoji;
  final VoidCallback onTap;

  @override
  State<_ReactionPickerButton> createState() => _ReactionPickerButtonState();
}

class _ReactionPickerButtonState extends State<_ReactionPickerButton> {
  @override
  Widget build(BuildContext context) {
    // InkWell rather than a hand-rolled MouseRegion: Material tracks hover
    // synchronously, so the tinted disc can never land on a neighbouring
    // emoji the way the deferred-setState version did — and the pointer
    // cursor comes with it.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 1),
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          onTap: widget.onTap,
          customBorder: const CircleBorder(),
          // A tinted disc rather than a grey square: plannerHover is close
          // enough to the menu's own white that the highlight barely read.
          hoverColor: tint(plannerBlue, 0.12),
          child: SizedBox(
            width: 34,
            height: 34,
            child: Center(
              child: Text(
                widget.emoji,
                style: const TextStyle(
                  fontSize: 19,
                  // Named explicitly. The default face has no glyphs for the
                  // variation-selector sequences (❤️) or the newer
                  // codepoints, so they came out as broken boxes.
                  fontFamily: emojiFontFamily,
                  fontFamilyFallback: emojiFontFallback,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionIcon extends StatelessWidget {
  const _ActionIcon({required this.icon, required this.tooltip});

  final IconData icon;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: 26,
        height: 22,
        child: Icon(icon, size: 14, color: plannerMuted),
      ),
    );
  }
}

class _MentionSuggestions extends StatelessWidget {
  const _MentionSuggestions({
    required this.matches,
    required this.showEveryone,
    required this.memberCount,
    required this.onPick,
    required this.onPickEveryone,
  });

  final List<WorkspaceMember> matches;
  final bool showEveryone;
  final int memberCount;
  final ValueChanged<WorkspaceMember> onPick;
  final VoidCallback onPickEveryone;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxHeight: 210),
      decoration: const BoxDecoration(
        color: plannerCard,
        border: Border(top: BorderSide(color: plannerDivider)),
      ),
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: 4),
        children: [
          // @everyone leads: asking the whole team is usually what you mean by
          // reaching for a mention in the first place.
          if (showEveryone)
            _EveryoneOption(memberCount: memberCount, onTap: onPickEveryone),
          for (final member in matches)
            _MentionOption(member: member, onTap: () => onPick(member)),
        ],
      ),
    );
  }
}

/// The @everyone row, set apart from the people below it.
class _EveryoneOption extends StatefulWidget {
  const _EveryoneOption({required this.memberCount, required this.onTap});

  final int memberCount;
  final VoidCallback onTap;

  @override
  State<_EveryoneOption> createState() => _EveryoneOptionState();
}

class _EveryoneOptionState extends State<_EveryoneOption> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setHoverSafely(this, () => _hovered = true),
      onExit: (_) => setHoverSafely(this, () => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          color: _hovered ? plannerHover : Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
          child: Row(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: tint(plannerOrange, 0.14),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.campaign_outlined,
                  size: 14,
                  color: plannerOrange,
                ),
              ),
              const SizedBox(width: 9),
              const Expanded(
                child: Text(
                  'everyone',
                  style: TextStyle(
                    color: plannerInk,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                'Notify all ${widget.memberCount}',
                style: const TextStyle(color: plannerFaint, fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One teammate in the mention list.
class _MentionOption extends StatefulWidget {
  const _MentionOption({required this.member, required this.onTap});

  final WorkspaceMember member;
  final VoidCallback onTap;

  @override
  State<_MentionOption> createState() => _MentionOptionState();
}

class _MentionOptionState extends State<_MentionOption> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final member = widget.member;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setHoverSafely(this, () => _hovered = true),
      onExit: (_) => setHoverSafely(this, () => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          color: _hovered ? plannerHover : Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 7),
          child: Row(
            children: [
              UserAvatar(profile: member.profile, size: 24, showTooltip: false),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  member.profile.displayName,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: plannerInk,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Text(
                member.role.label,
                style: const TextStyle(color: plannerFaint, fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Where you write.
///
/// The field and the send button share one rounded shell rather than sitting
/// side by side as a text input and a rectangle — the second reads as a form,
/// which is not what writing a message feels like. Send is a circle inside the
/// field, and only lights up when there is something to send.
class _Composer extends StatefulWidget {
  const _Composer({
    required this.controller,
    required this.focusNode,
    required this.sending,
    required this.replyingTo,
    required this.editing,
    required this.onSend,
    required this.onCancel,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool sending;
  final TaskComment? replyingTo;
  final TaskComment? editing;
  final VoidCallback onSend;
  final VoidCallback onCancel;

  @override
  State<_Composer> createState() => _ComposerState();
}

class _ComposerState extends State<_Composer> {
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
    widget.focusNode.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    widget.focusNode.removeListener(_onFocusChanged);
    super.dispose();
  }

  // Rebuilds so Send can enable itself the moment there is text.
  void _onTextChanged() => setState(() {});

  void _onFocusChanged() {
    if (mounted) {
      setState(() => _focused = widget.focusNode.hasFocus);
    }
  }

  bool get _canSend =>
      widget.controller.text.trim().isNotEmpty && !widget.sending;

  @override
  Widget build(BuildContext context) {
    final replying = widget.replyingTo;
    final isEditing = widget.editing != null;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 13),
      decoration: const BoxDecoration(
        color: plannerCard,
        border: Border(top: BorderSide(color: plannerDivider)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (replying != null || isEditing)
            _ComposerContext(
              label: isEditing
                  ? 'Editing your message'
                  : 'Replying to '
                        '${replying?.author?.displayName ?? 'a message'}',
              onCancel: widget.onCancel,
            ),
          AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            padding: const EdgeInsets.fromLTRB(14, 4, 4, 4),
            decoration: BoxDecoration(
              // One fill, always. It used to swap between plannerSurface and
              // plannerCard on focus, so the field changed shade every time you
              // clicked into it or a menu stole focus back.
              //
              // plannerCard, not plannerSurface: the bar behind it is already
              // white, and surface is four points off white, so the field read
              // as a faint smudge on it rather than a defined input. The border
              // is what separates the two now.
              color: plannerCard,
              borderRadius: BorderRadius.circular(radiusXl),
              border: Border.all(
                color: _focused ? plannerBlue : plannerBorder,
                // Held at 1: growing the border on focus reflows the text
                // inside by half a pixel, which reads as a twitch.
                width: 1,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 116),
                    // Enter sends; Shift+Enter breaks the line.
                    //
                    // This has to be a key handler. `TextInputAction.send` fires
                    // onSubmitted for a bare Enter *and* a shifted one — the
                    // action carries no modifier state — so Shift+Enter sent the
                    // message instead of breaking the line, and the hint below
                    // the field was advertising something that did not work.
                    child: Focus(
                      // Not focusable itself — it only listens on the way
                      // through. Without this the wrapper takes focus as an
                      // ancestor of the field and paints its own highlight,
                      // which is the doubled ring around the composer.
                      canRequestFocus: false,
                      skipTraversal: true,
                      onKeyEvent: (node, event) {
                        if (event is! KeyDownEvent ||
                            event.logicalKey != LogicalKeyboardKey.enter) {
                          return KeyEventResult.ignored;
                        }
                        final shift = HardwareKeyboard.instance.isShiftPressed;
                        if (shift) {
                          // Fall through to the field, which inserts a newline.
                          return KeyEventResult.ignored;
                        }
                        if (_canSend) widget.onSend();
                        // Handled either way, so a blank Enter cannot leak a
                        // newline into an otherwise empty composer.
                        return KeyEventResult.handled;
                      },
                      child: TextField(
                        controller: widget.controller,
                        focusNode: widget.focusNode,
                        autofocus: true,
                        minLines: 1,
                        maxLines: null,
                        maxLength: commentMaxLength,
                        textInputAction: TextInputAction.newline,
                        buildCounter:
                            (
                              context, {
                              required currentLength,
                              required isFocused,
                              required maxLength,
                            }) => null,
                        decoration: InputDecoration(
                          isDense: true,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          // Painted explicitly rather than left to the theme.
                          // With `filled` unset, Material still washes the
                          // decoration area with ThemeData.focusColor once the
                          // field has focus — a pale blue-grey that covered the
                          // whole box and was the grey block in the composer.
                          // It only ever showed while focused, which is what
                          // made the colour look inconsistent.
                          filled: true,
                          fillColor: plannerCard,
                          hoverColor: Colors.transparent,
                          focusColor: Colors.transparent,
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 11,
                          ),
                          hintText: isEditing
                              ? 'Update your message…'
                              : 'Write a message…',
                          hintStyle: const TextStyle(
                            color: plannerFaint,
                            fontSize: 13,
                          ),
                        ),
                        style: const TextStyle(fontSize: 13, height: 1.4),
                      ),
                    ),
                  ),
                ),
                _SendButton(
                  enabled: _canSend,
                  sending: widget.sending,
                  isEditing: isEditing,
                  onSend: widget.onSend,
                ),
              ],
            ),
          ),
          const SizedBox(height: 7),
          // .length, not .characters.length: maxLength counts UTF-16 units, so
          // counting graphemes here would disagree with the field's own cutoff
          // on any message containing emoji.
          _ComposerHint(length: widget.controller.text.length),
        ],
      ),
    );
  }
}

/// A circle inside the field, lit only when there is something to send.
class _SendButton extends StatelessWidget {
  const _SendButton({
    required this.enabled,
    required this.sending,
    required this.isEditing,
    required this.onSend,
  });

  final bool enabled;
  final bool sending;
  final bool isEditing;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: isEditing ? 'Save changes' : 'Send · Enter',
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        width: 34,
        height: 34,
        margin: const EdgeInsets.only(bottom: 2),
        decoration: BoxDecoration(
          color: enabled ? plannerBlue : plannerBorder,
          shape: BoxShape.circle,
        ),
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: enabled ? onSend : null,
            child: Center(
              child: sending
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Icon(
                      isEditing
                          ? Icons.check_rounded
                          : Icons.arrow_upward_rounded,
                      size: 17,
                      color: enabled ? Colors.white : plannerFaint,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The shortcuts, stated once beneath the field.
///
/// They used to live in the placeholder, which vanished the moment anyone
/// started typing — exactly when a reminder is worth having.
class _ComposerHint extends StatelessWidget {
  const _ComposerHint({required this.length});

  /// Characters typed so far, so the limit can announce itself before it bites.
  final int length;

  @override
  Widget build(BuildContext context) {
    // Quiet until the last 500 characters. The field stops accepting input at
    // the limit and the database rejects anything longer, so without a counter
    // a long message simply stopped typing with no explanation.
    final remaining = commentMaxLength - length;
    final showCount = remaining <= 500;

    return Row(
      children: [
        const _HintKey(label: '@'),
        const SizedBox(width: 5),
        const Text(
          'to mention',
          style: TextStyle(color: plannerFaint, fontSize: 10.5),
        ),
        const SizedBox(width: 12),
        const _HintKey(label: 'Shift'),
        const SizedBox(width: 3),
        const Text('+', style: TextStyle(color: plannerFaint, fontSize: 10.5)),
        const SizedBox(width: 3),
        const _HintKey(label: 'Enter'),
        const SizedBox(width: 5),
        const Text(
          'for a new line',
          style: TextStyle(color: plannerFaint, fontSize: 10.5),
        ),
        if (showCount) ...[
          const Spacer(),
          Text(
            remaining <= 0 ? 'Limit reached' : '$remaining left',
            style: TextStyle(
              color: remaining <= 0 ? plannerRed : plannerFaint,
              fontSize: 10.5,
              fontWeight: remaining <= 0 ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ],
      ],
    );
  }
}

/// A keycap, so a shortcut reads as something you press.
class _HintKey extends StatelessWidget {
  const _HintKey({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: plannerSurface,
        borderRadius: BorderRadius.circular(radiusXs),
        border: Border.all(color: plannerBorder),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: plannerMuted,
          fontSize: 9.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _ComposerContext extends StatelessWidget {
  const _ComposerContext({required this.label, required this.onCancel});

  final String label;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(width: 2, height: 14, color: plannerBlue),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: plannerMuted, fontSize: 11.5),
            ),
          ),
          InkWell(
            onTap: onCancel,
            borderRadius: BorderRadius.circular(radiusXs),
            child: const Padding(
              padding: EdgeInsets.all(3),
              child: Icon(Icons.close_rounded, size: 13, color: plannerMuted),
            ),
          ),
        ],
      ),
    );
  }
}

/// The chat button on a task row, with an unread-style count.
class ChatButton extends StatelessWidget {
  const ChatButton({
    super.key,
    required this.task,
    required this.onOpenChat,
    this.size = 30,
  });

  final PlannerTask task;
  final ValueChanged<PlannerTask> onOpenChat;
  final double size;

  @override
  Widget build(BuildContext context) {
    final count = task.commentCount;
    final hasMessages = count > 0;

    // A bordered pill rather than a bare grey glyph: on a card full of text
    // the old icon disappeared, and a chat nobody can find is a chat nobody
    // uses. With messages it turns blue and carries the count — the "someone
    // said something here" signal readable from across the board.
    return Tooltip(
      message: hasMessages
          ? '$count ${count == 1 ? 'message' : 'messages'} — open chat'
          : 'Open chat',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => onOpenChat(task),
          borderRadius: BorderRadius.circular(99),
          child: Container(
            height: 22,
            padding: const EdgeInsets.symmetric(horizontal: 7),
            decoration: BoxDecoration(
              color: hasMessages ? tint(plannerBlue, 0.10) : Colors.transparent,
              borderRadius: BorderRadius.circular(99),
              border: Border.all(
                color: hasMessages ? tint(plannerBlue, 0.40) : plannerBorder,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  hasMessages
                      ? Icons.forum_rounded
                      : Icons.chat_bubble_outline_rounded,
                  size: 13,
                  color: hasMessages ? plannerBlue : plannerMuted,
                ),
                // Shown from the first message, not the second: one message is
                // still a conversation, and a lone icon said nothing about
                // whether anyone had spoken.
                if (hasMessages) ...[
                  const SizedBox(width: 4),
                  Text(
                    compactCount(count),
                    style: const TextStyle(
                      color: plannerBlue,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      height: 1,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
