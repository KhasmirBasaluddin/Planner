import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show RealtimeChannel;

import '../../../core/supabase/planner_repository.dart';
import '../../../models/planner_models.dart';
import '../../../shared/utils/planner_colors.dart';
import '../../../shared/widgets/app_dialog.dart';
import '../../../shared/widgets/user_avatar.dart';

// === Name + color dialog (boards, groups, workspaces) ===

/// Length limits for user-supplied names.
///
/// Enforced in the UI *and* worth knowing about: without a cap, a pasted essay
/// as a board name stretches the sidebar, overflows headers, and makes the
/// board unusable. These are generous enough that a real name never hits them.
class NameLimits {
  const NameLimits._();

  static const int workspace = 40;
  static const int board = 50;
  static const int group = 40;
  static const int task = 120;

  /// Returns an error message, or null when the name is acceptable.
  static String? validate(String? value, {required int max, String what = 'name'}) {
    final name = (value ?? '').trim();
    if (name.isEmpty) {
      return 'Enter a $what.';
    }
    if (name.length > max) {
      return 'Keep it under $max characters (currently ${name.length}).';
    }
    return null;
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
          GestureDetector(
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
                  ? const Icon(Icons.check_rounded, size: 15, color: Colors.white)
                  : null,
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
      icon: danger
          ? Icons.delete_outline_rounded
          : Icons.help_outline_rounded,
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
    required this.owner,
    required this.status,
    required this.priority,
    required this.progress,
    this.assigneeId,
    this.dueDate,
    this.startDate,
    this.endDate,
  });

  final String groupId;
  final String title;
  final String owner;
  final String? assigneeId;
  final TaskStatus status;
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
  PlannerTask? task,
}) {
  return showDialog<TaskDialogResult>(
    context: context,
    builder: (context) =>
        _TaskDialog(groups: groups, members: members, task: task),
  );
}

class _TaskDialog extends StatefulWidget {
  const _TaskDialog({
    required this.groups,
    required this.members,
    this.task,
  });

  final List<TaskGroup> groups;
  final List<WorkspaceMember> members;
  final PlannerTask? task;

  @override
  State<_TaskDialog> createState() => _TaskDialogState();
}

class _TaskDialogState extends State<_TaskDialog> {
  late final TextEditingController _titleController;
  late String _groupId;
  late TaskStatus _status;
  late TaskPriority _priority;
  late double _progress;
  String? _assigneeId;
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
    _status = task?.status ?? TaskStatus.notStarted;
    _priority = task?.priority ?? TaskPriority.medium;
    _progress = task?.progress ?? 0;
    _assigneeId = task?.assigneeId;
    _dueDate = task?.dueDate;
    _startDate = task?.startDate;
    _endDate = task?.endDate;
  }

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
    final title = _titleController.text.trim();
    final assignee = widget.members
        .where((m) => m.profile.id == _assigneeId)
        .firstOrNull;

    Navigator.of(context).pop(
      TaskDialogResult(
        groupId: _groupId,
        title: title,
        // Keep a readable owner label alongside the account link.
        owner: assignee?.profile.displayName ?? '',
        assigneeId: _assigneeId,
        status: _status,
        priority: _priority,
        progress: _progress,
        dueDate: _dueDate,
        startDate: _startDate,
        endDate: _endDate,
      ),
    );
  }

  Future<void> _pickDate({
    required DateTime? current,
    required ValueChanged<DateTime?> onPicked,
  }) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? now,
      firstDate: DateTime(now.year - 3),
      lastDate: DateTime(now.year + 6),
    );
    if (picked != null) {
      onPicked(picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      icon: widget.task == null
          ? Icons.add_task_rounded
          : Icons.edit_outlined,
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
                          items: [
                            for (final group in widget.groups)
                              DropdownMenuItem(
                                value: group.id,
                                child: Row(
                                  children: [
                                    Container(
                                      width: 8,
                                      height: 8,
                                      decoration: BoxDecoration(
                                        color: group.color,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Flexible(
                                      child: Text(
                                        group.name,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
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
                        const _FieldLabel('Assignee'),
                        _DropdownField<String?>(
                          value: _assigneeId,
                          items: [
                            const DropdownMenuItem(
                              value: null,
                              child: Text(
                                'Unassigned',
                                style: TextStyle(color: plannerMuted),
                              ),
                            ),
                            for (final member in widget.members)
                              DropdownMenuItem(
                                value: member.profile.id,
                                child: Row(
                                  children: [
                                    UserAvatar(
                                      profile: member.profile,
                                      size: 20,
                                      showTooltip: false,
                                    ),
                                    const SizedBox(width: 8),
                                    Flexible(
                                      child: Text(
                                        member.profile.displayName,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                          onChanged: (value) =>
                              setState(() => _assigneeId = value),
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
                        _DropdownField<TaskStatus>(
                          value: _status,
                          items: [
                            for (final status in TaskStatus.values)
                              DropdownMenuItem(
                                value: status,
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
                                    const SizedBox(width: 8),
                                    Text(status.label),
                                  ],
                                ),
                              ),
                          ],
                          onChanged: (value) {
                            if (value != null) {
                              setState(() {
                                _status = value;
                                if (value == TaskStatus.done) {
                                  _progress = 1;
                                } else if (value == TaskStatus.notStarted) {
                                  _progress = 0;
                                }
                              });
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
                        const _FieldLabel('Priority'),
                        _DropdownField<TaskPriority>(
                          value: _priority,
                          items: [
                            for (final priority in TaskPriority.values)
                              DropdownMenuItem(
                                value: priority,
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.flag_rounded,
                                      size: 13,
                                      color: priorityColor(priority),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(priority.label),
                                  ],
                                ),
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
                        onPicked: (date) => setState(() => _startDate = date),
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
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 8,
                  ),
                  // The track already spans the padded width; removing the
                  // theme's own inset keeps the ends aligned with the labels.
                  trackShape: const RectangularSliderTrackShape(),
                ),
                child: Slider(
                  value: _progress,
                  onChanged: (value) => setState(() {
                    _progress = value;
                    // Keep status coherent with progress, matching the rule the
                    // repository enforces.
                    if (value <= 0) {
                      _status = TaskStatus.notStarted;
                    } else if (value >= 1) {
                      _status = TaskStatus.done;
                    } else if (_status == TaskStatus.done ||
                        _status == TaskStatus.notStarted) {
                      _status = TaskStatus.working;
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

class _DropdownField<T> extends StatelessWidget {
  const _DropdownField({
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<T>(
      initialValue: value,
      items: items,
      onChanged: onChanged,
      isExpanded: true,
      icon: const Icon(
        Icons.keyboard_arrow_down_rounded,
        size: 18,
        color: plannerFaint,
      ),
      style: const TextStyle(color: plannerText, fontSize: 13),
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
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
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
/// plain text).
Document docFromNote(String note) {
  if (note.trim().isEmpty) {
    return Document();
  }
  try {
    final decoded = jsonDecode(note);
    if (decoded is List) {
      return Document.fromJson(decoded);
    }
  } catch (_) {
    // Not JSON — treat as plain text below.
  }
  return Document()..insert(0, note);
}

String notePlainText(String note) => docFromNote(note).toPlainText().trim();

/// Opens the collaborative notes thread for a task.
Future<void> showTaskNotesDialog({
  required BuildContext context,
  required PlannerTask task,
  required PlannerRepository repository,
  required List<WorkspaceMember> members,
  required String currentUserId,
  required bool canEdit,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => _TaskNotesDialog(
      task: task,
      repository: repository,
      currentUserId: currentUserId,
      canEdit: canEdit,
    ),
  );
}

class _TaskNotesDialog extends StatefulWidget {
  const _TaskNotesDialog({
    required this.task,
    required this.repository,
    required this.currentUserId,
    required this.canEdit,
  });

  final PlannerTask task;
  final PlannerRepository repository;
  final String currentUserId;
  final bool canEdit;

  @override
  State<_TaskNotesDialog> createState() => _TaskNotesDialogState();
}

class _TaskNotesDialogState extends State<_TaskNotesDialog> {
  final QuillController _composer = QuillController.basic();
  final FocusNode _composerFocus = FocusNode();

  List<TaskNote> _notes = [];
  bool _loading = true;
  bool _posting = false;
  String? _error;
  String? _editingId;
  Color _composerColor = noteYellow;

  RealtimeChannel? _channel;

  @override
  void initState() {
    super.initState();
    _load();

    // Keep an open thread live, so a teammate's note appears while you are
    // reading rather than only on reopen.
    _channel = widget.repository.subscribeToTaskNotes(
      taskId: widget.task.id,
      onChange: () {
        // Skip the refresh mid-edit; reloading would discard what is being
        // typed. The save path reloads anyway once the edit lands.
        if (mounted && _editingId == null && !_posting) {
          _load();
        }
      },
    );
  }

  @override
  void dispose() {
    final channel = _channel;
    if (channel != null) {
      widget.repository.unsubscribe(channel);
    }
    _composer.dispose();
    _composerFocus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final notes = await widget.repository.loadNotes(widget.task.id);
      if (!mounted) {
        return;
      }
      setState(() {
        _notes = notes;
        _loading = false;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = error.toString();
        });
      }
    }
  }

  Future<void> _post() async {
    if (_composer.document.isEmpty()) {
      return;
    }
    setState(() {
      _posting = true;
      _error = null;
    });

    final body = jsonEncode(_composer.document.toDelta().toJson());
    try {
      if (_editingId != null) {
        await widget.repository.updateNote(noteId: _editingId!, body: body);
      } else {
        await widget.repository.addNote(
          taskId: widget.task.id,
          body: body,
          color: _composerColor,
        );
      }
      _composer.clear();
      setState(() => _editingId = null);
      await _load();
    } catch (error) {
      if (mounted) {
        setState(() => _error = error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _posting = false);
      }
    }
  }

  void _startEditing(TaskNote note) {
    setState(() {
      _editingId = note.id;
      _composerColor = note.color;
      _composer.document = docFromNote(note.body);
    });
    _composerFocus.requestFocus();
  }

  void _cancelEditing() {
    setState(() {
      _editingId = null;
      _composer.clear();
    });
  }

  Future<void> _delete(TaskNote note) async {
    final confirmed = await showDeleteConfirmDialog(
      context: context,
      title: 'Delete note',
      message: 'Delete this note? Everyone in the workspace will lose it.',
    );
    if (!confirmed) {
      return;
    }
    try {
      await widget.repository.deleteNote(note.id);
      await _load();
    } catch (error) {
      if (mounted) {
        setState(() => _error = error.toString());
      }
    }
  }

  Future<void> _togglePin(TaskNote note) async {
    try {
      await widget.repository.setNotePinned(
        noteId: note.id,
        pinned: !note.pinned,
      );
      await _load();
    } catch (error) {
      if (mounted) {
        setState(() => _error = error.toString());
      }
    }
  }

  Future<void> _react(TaskNote note, String emoji) async {
    final adding = !note.myReactions.contains(emoji);
    try {
      await widget.repository.toggleReaction(
        noteId: note.id,
        emoji: emoji,
        add: adding,
      );
      await _load();
    } catch (_) {
      // Reactions are incidental; a failure should not interrupt reading.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620, maxHeight: 700),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            const Divider(height: 1),
            Flexible(
              child: _loading
                  ? const Padding(
                      padding: EdgeInsets.all(48),
                      child: Center(
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      ),
                    )
                  : _notes.isEmpty
                  ? _buildEmpty()
                  : _buildList(),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                child: Text(
                  _error!,
                  style: const TextStyle(color: plannerRed, fontSize: 12),
                ),
              ),
            if (widget.canEdit) ...[
              const Divider(height: 1),
              _buildComposer(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 12, 14),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: tint(plannerBlue, 0.10),
              borderRadius: BorderRadius.circular(radiusMd),
            ),
            child: const Icon(
              Icons.forum_outlined,
              size: 17,
              color: plannerBlue,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.task.title,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: plannerInk,
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                ),
                Text(
                  _notes.isEmpty
                      ? 'Shared notes — everyone in the workspace can see these'
                      : '${_notes.length} note${_notes.length == 1 ? '' : 's'} '
                            '· visible to the whole workspace',
                  style: const TextStyle(color: plannerMuted, fontSize: 11.5),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 18),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 52, horizontal: 32),
      child: Column(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: noteYellow,
              borderRadius: BorderRadius.circular(radiusMd),
              border: Border.all(color: noteBorderColor(noteYellow)),
            ),
            child: const Icon(
              Icons.edit_note_rounded,
              size: 21,
              color: Color(0xFF8A6D00),
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'No notes yet',
            style: TextStyle(
              color: plannerInk,
              fontSize: 14.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            widget.canEdit
                ? 'Add context, decisions or blockers. Your teammates will see '
                      'them here.'
                : 'Nobody has added a note to this task yet.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: plannerMuted,
              fontSize: 12.5,
              height: 1.55,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildList() {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      itemCount: _notes.length,
      separatorBuilder: (context, index) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final note = _notes[index];
        final isMine = note.author?.id == widget.currentUserId;
        return _NoteCard(
          note: note,
          canEdit: widget.canEdit,
          canDelete: widget.canEdit && isMine,
          isEditing: _editingId == note.id,
          onEdit: () => _startEditing(note),
          onDelete: () => _delete(note),
          onTogglePin: () => _togglePin(note),
          onReact: (emoji) => _react(note, emoji),
        );
      },
    );
  }

  Widget _buildComposer() {
    final editing = _editingId != null;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
      color: plannerSurface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            constraints: const BoxConstraints(minHeight: 74, maxHeight: 160),
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            decoration: BoxDecoration(
              color: _composerColor,
              borderRadius: BorderRadius.circular(radiusMd),
              border: Border.all(color: noteBorderColor(_composerColor)),
            ),
            child: Column(
              children: [
                Expanded(
                  child: QuillEditor.basic(
                    controller: _composer,
                    focusNode: _composerFocus,
                    config: QuillEditorConfig(
                      placeholder: editing
                          ? 'Edit this note…'
                          : 'Write a note for your team…',
                      padding: EdgeInsets.zero,
                      customStyles: DefaultStyles(
                        paragraph: DefaultTextBlockStyle(
                          const TextStyle(
                            fontSize: 13,
                            height: 1.5,
                            color: plannerInk,
                          ),
                          const HorizontalSpacing(0, 0),
                          const VerticalSpacing(0, 0),
                          const VerticalSpacing(0, 0),
                          null,
                        ),
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  height: 30,
                  child: QuillSimpleToolbar(
                    controller: _composer,
                    config: const QuillSimpleToolbarConfig(
                      toolbarIconAlignment: WrapAlignment.start,
                      toolbarSectionSpacing: 0,
                      multiRowsDisplay: false,
                      buttonOptions: QuillSimpleToolbarButtonOptions(
                        base: QuillToolbarBaseButtonOptions(
                          iconSize: 13,
                          iconButtonFactor: 1.5,
                        ),
                      ),
                      showFontFamily: false,
                      showFontSize: false,
                      showBoldButton: true,
                      showItalicButton: true,
                      showUnderLineButton: true,
                      showStrikeThrough: true,
                      showListBullets: true,
                      showListNumbers: true,
                      showListCheck: true,
                      showLink: true,
                      showDividers: false,
                      showInlineCode: false,
                      showColorButton: false,
                      showBackgroundColorButton: false,
                      showClearFormat: false,
                      showAlignmentButtons: false,
                      showHeaderStyle: false,
                      showQuote: false,
                      showIndent: false,
                      showUndo: false,
                      showRedo: false,
                      showSearchButton: false,
                      showSubscript: false,
                      showSuperscript: false,
                      showCodeBlock: false,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              for (final color in notePalette.take(6)) ...[
                GestureDetector(
                  onTap: () => setState(() => _composerColor = color),
                  child: Container(
                    width: 20,
                    height: 20,
                    margin: const EdgeInsets.only(right: 6),
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(radiusXs),
                      border: Border.all(
                        color: color.toARGB32() == _composerColor.toARGB32()
                            ? plannerInk
                            : noteBorderColor(color),
                        width: color.toARGB32() == _composerColor.toARGB32()
                            ? 1.8
                            : 1,
                      ),
                    ),
                  ),
                ),
              ],
              const Spacer(),
              if (editing) ...[
                TextButton(
                  onPressed: _cancelEditing,
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 6),
              ],
              FilledButton(
                onPressed: _posting ? null : _post,
                child: _posting
                    ? const SizedBox(
                        width: 15,
                        height: 15,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(editing ? 'Save note' : 'Add note'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One note in the thread, attributed and reactable.
class _NoteCard extends StatefulWidget {
  const _NoteCard({
    required this.note,
    required this.canEdit,
    required this.canDelete,
    required this.isEditing,
    required this.onEdit,
    required this.onDelete,
    required this.onTogglePin,
    required this.onReact,
  });

  final TaskNote note;
  final bool canEdit;
  final bool canDelete;
  final bool isEditing;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onTogglePin;
  final ValueChanged<String> onReact;

  @override
  State<_NoteCard> createState() => _NoteCardState();
}

class _NoteCardState extends State<_NoteCard> {
  static const _quickReactions = ['👍', '🎉', '👀', '❤️'];

  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final note = widget.note;
    final author = note.author;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Container(
        decoration: BoxDecoration(
          color: note.color,
          borderRadius: BorderRadius.circular(radiusMd),
          border: Border.all(
            color: widget.isEditing
                ? plannerBlue
                : noteBorderColor(note.color),
            width: widget.isEditing ? 1.6 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 8, 6),
              child: Row(
                children: [
                  if (author != null)
                    UserAvatar(profile: author, size: 22)
                  else
                    Container(
                      width: 22,
                      height: 22,
                      decoration: const BoxDecoration(
                        color: plannerSlate,
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: const Text(
                        '?',
                        style: TextStyle(color: Colors.white, fontSize: 10),
                      ),
                    ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      author?.displayName ?? 'Unknown',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: plannerInk,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 7),
                  Text(
                    formatRelative(note.createdAt),
                    style: TextStyle(
                      color: plannerInk.withValues(alpha: 0.45),
                      fontSize: 11,
                    ),
                  ),
                  if (note.wasEdited) ...[
                    const SizedBox(width: 5),
                    Tooltip(
                      message: note.editedBy == null
                          ? 'Edited'
                          : 'Edited by ${note.editedBy!.displayName}',
                      child: Text(
                        '· edited',
                        style: TextStyle(
                          color: plannerInk.withValues(alpha: 0.38),
                          fontSize: 11,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  ],
                  const Spacer(),
                  if (note.pinned)
                    Padding(
                      padding: const EdgeInsets.only(right: 2),
                      child: Icon(
                        Icons.push_pin_rounded,
                        size: 13,
                        color: plannerInk.withValues(alpha: 0.5),
                      ),
                    ),
                  if (_hovered && widget.canEdit)
                    _NoteActions(
                      pinned: note.pinned,
                      canDelete: widget.canDelete,
                      onEdit: widget.onEdit,
                      onDelete: widget.onDelete,
                      onTogglePin: widget.onTogglePin,
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: SizedBox(
                width: double.infinity,
                child: QuillEditor.basic(
                  controller: QuillController(
                    document: docFromNote(note.body),
                    selection: const TextSelection.collapsed(offset: 0),
                    readOnly: true,
                  ),
                  config: QuillEditorConfig(
                    showCursor: false,
                    padding: EdgeInsets.zero,
                    customStyles: DefaultStyles(
                      paragraph: DefaultTextBlockStyle(
                        const TextStyle(
                          fontSize: 13,
                          height: 1.5,
                          color: plannerInk,
                        ),
                        const HorizontalSpacing(0, 0),
                        const VerticalSpacing(0, 0),
                        const VerticalSpacing(0, 0),
                        null,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            _buildReactionBar(note),
          ],
        ),
      ),
    );
  }

  Widget _buildReactionBar(TaskNote note) {
    final hasReactions = note.reactions.isNotEmpty;
    if (!hasReactions && !_hovered) {
      return const SizedBox(height: 4);
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 9),
      child: Row(
        children: [
          for (final entry in note.reactions.entries)
            Padding(
              padding: const EdgeInsets.only(right: 5),
              child: _ReactionChip(
                emoji: entry.key,
                count: entry.value,
                active: note.myReactions.contains(entry.key),
                onTap: () => widget.onReact(entry.key),
              ),
            ),
          if (_hovered)
            for (final emoji in _quickReactions)
              if (!note.reactions.containsKey(emoji))
                Padding(
                  padding: const EdgeInsets.only(right: 3),
                  child: InkWell(
                    onTap: () => widget.onReact(emoji),
                    borderRadius: BorderRadius.circular(radiusXs),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 2,
                      ),
                      child: Opacity(
                        opacity: 0.45,
                        child: Text(
                          emoji,
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                    ),
                  ),
                ),
        ],
      ),
    );
  }
}

class _ReactionChip extends StatelessWidget {
  const _ReactionChip({
    required this.emoji,
    required this.count,
    required this.active,
    required this.onTap,
  });

  final String emoji;
  final int count;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(radiusXl),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: active
              ? Colors.white.withValues(alpha: 0.85)
              : Colors.white.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(radiusXl),
          border: Border.all(
            color: active
                ? plannerBlue
                : plannerInk.withValues(alpha: 0.12),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 12)),
            const SizedBox(width: 4),
            Text(
              '$count',
              style: TextStyle(
                color: active ? plannerBlue : plannerText,
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

class _NoteActions extends StatelessWidget {
  const _NoteActions({
    required this.pinned,
    required this.canDelete,
    required this.onEdit,
    required this.onDelete,
    required this.onTogglePin,
  });

  final bool pinned;
  final bool canDelete;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onTogglePin;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _IconAction(
          icon: pinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
          tooltip: pinned ? 'Unpin' : 'Pin to top',
          onPressed: onTogglePin,
        ),
        _IconAction(
          icon: Icons.edit_outlined,
          tooltip: 'Edit note',
          onPressed: onEdit,
        ),
        if (canDelete)
          _IconAction(
            icon: Icons.delete_outline_rounded,
            tooltip: 'Delete note',
            onPressed: onDelete,
          ),
      ],
    );
  }
}

class _IconAction extends StatelessWidget {
  const _IconAction({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(radiusXs),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(
            icon,
            size: 14,
            color: plannerInk.withValues(alpha: 0.5),
          ),
        ),
      ),
    );
  }
}

/// The note button on a task row: shows how many notes exist and opens the
/// thread.
class NoteButton extends StatelessWidget {
  const NoteButton({
    super.key,
    required this.task,
    required this.onOpenNotes,
    this.size = 30,
  });

  final PlannerTask task;
  final ValueChanged<PlannerTask> onOpenNotes;
  final double size;

  @override
  Widget build(BuildContext context) {
    final count = task.noteCount;
    final hasNotes = count > 0;
    return Tooltip(
      message: hasNotes
          ? '$count note${count == 1 ? '' : 's'}'
          : 'Add a note',
      child: InkWell(
        onTap: () => onOpenNotes(task),
        borderRadius: BorderRadius.circular(radiusSm),
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: hasNotes ? tint(plannerBlue, 0.09) : Colors.transparent,
            borderRadius: BorderRadius.circular(radiusSm),
          ),
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Icon(
                hasNotes
                    ? Icons.mode_comment_rounded
                    : Icons.mode_comment_outlined,
                size: 15,
                color: hasNotes ? plannerBlue : plannerFaint,
              ),
              if (count > 1)
                Positioned(
                  right: -6,
                  top: -5,
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 14),
                    height: 14,
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(
                      color: plannerBlue,
                      borderRadius: BorderRadius.circular(7),
                      border: Border.all(color: Colors.white, width: 1.5),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '$count',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 8.5,
                        fontWeight: FontWeight.w700,
                      ),
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
