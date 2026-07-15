import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';

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

/// Opens the multi-note manager. Returns the updated list of notes if the user
/// saved, or null if they cancelled.
Future<List<String>?> showNoteDialog({
  required BuildContext context,
  required PlannerTask task,
}) {
  return showDialog<List<String>>(
    context: context,
    builder: (context) => _NoteDialog(task: task),
  );
}

/// A tappable note icon showing how many notes a task has: filled/accent with a
/// count badge when notes exist, outline when empty. Opens the note manager.
class NoteButton extends StatelessWidget {
  const NoteButton({
    super.key,
    required this.task,
    required this.onNotesChanged,
    this.size = 30,
  });

  final PlannerTask task;
  final Future<void> Function(PlannerTask task, List<String> notes)
  onNotesChanged;
  final double size;

  @override
  Widget build(BuildContext context) {
    final count = task.notes.length;
    final hasNotes = count > 0;
    return Tooltip(
      message: hasNotes ? '$count note${count == 1 ? '' : 's'}' : 'Add note',
      waitDuration: const Duration(milliseconds: 400),
      child: InkWell(
        onTap: () async {
          final result = await showNoteDialog(context: context, task: task);
          if (result != null) {
            await onNotesChanged(task, result);
          }
        },
        borderRadius: BorderRadius.circular(6),
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: hasNotes
                ? plannerBlue.withValues(alpha: 0.10)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Icon(
                hasNotes ? Icons.sticky_note_2 : Icons.sticky_note_2_outlined,
                size: 16,
                color: hasNotes ? plannerBlue : const Color(0xFFB4B9C9),
              ),
              if (count > 1)
                Positioned(
                  right: -5,
                  top: -5,
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 14),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 3,
                      vertical: 1,
                    ),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: plannerBlue,
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(
                      '$count',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        height: 1,
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

Future<bool> showDeleteConfirmDialog({
  required BuildContext context,
  required String title,
  required String message,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 10, 24, 0),
      actionsPadding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
      title: _DialogTitle(title),
      content: SizedBox(
        width: 380,
        child: Text(
          message,
          style: const TextStyle(
            color: plannerText,
            fontSize: 13,
            height: 1.5,
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
          style: FilledButton.styleFrom(backgroundColor: plannerRed),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

// Sticky-note colors.
const Color _stickyBody = Color(0xFFFEF9C3);
const Color _stickyHeader = Color(0xFFFDE047);

/// Builds a Quill document from a stored note (Delta JSON, or legacy plain text).
Document _docFromNote(String note) {
  if (note.trim().isEmpty) {
    return Document();
  }
  try {
    final decoded = jsonDecode(note);
    if (decoded is List) {
      return Document.fromJson(decoded);
    }
  } catch (_) {
    // Not JSON — treat as legacy plain text below.
  }
  return Document()..insert(0, note);
}

/// Plain-text preview of a stored note, for compact displays.
String notePlainText(String note) => _docFromNote(note).toPlainText().trim();

class _NoteDialog extends StatefulWidget {
  const _NoteDialog({required this.task});

  final PlannerTask task;

  @override
  State<_NoteDialog> createState() => _NoteDialogState();
}

class _NoteDialogState extends State<_NoteDialog> {
  late final List<QuillController> _controllers;
  final FocusNode _focusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  int _current = 0;

  @override
  void initState() {
    super.initState();
    _controllers = widget.task.notes.map(_controllerFor).toList();
    if (_controllers.isEmpty) {
      _controllers.add(QuillController.basic());
    }
  }

  QuillController _controllerFor(String note) {
    return QuillController(
      document: _docFromNote(note),
      selection: const TextSelection.collapsed(offset: 0),
    );
  }

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _addNote() {
    setState(() {
      _controllers.add(QuillController.basic());
      _current = _controllers.length - 1;
    });
  }

  void _deleteCurrent() {
    setState(() {
      _controllers[_current].dispose();
      _controllers.removeAt(_current);
      if (_controllers.isEmpty) {
        _controllers.add(QuillController.basic());
      }
      if (_current >= _controllers.length) {
        _current = _controllers.length - 1;
      }
    });
  }

  void _go(int delta) {
    final next = (_current + delta).clamp(0, _controllers.length - 1);
    if (next != _current) {
      setState(() => _current = next);
    }
  }

  void _save() {
    final notes = <String>[];
    for (final controller in _controllers) {
      if (controller.document.toPlainText().trim().isNotEmpty) {
        notes.add(jsonEncode(controller.document.toDelta().toJson()));
      }
    }
    Navigator.of(context).pop(notes);
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controllers[_current];
    final total = _controllers.length;

    return Dialog(
      clipBehavior: Clip.antiAlias,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460, maxHeight: 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Sticky header: task title + new / navigate / delete / close.
            Container(
              color: _stickyHeader,
              padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.task.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF713F12),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (total > 1) ...[
                    _StickyIcon(
                      icon: Icons.chevron_left_rounded,
                      tooltip: 'Previous note',
                      onPressed: _current > 0 ? () => _go(-1) : null,
                    ),
                    Text(
                      '${_current + 1}/$total',
                      style: const TextStyle(
                        color: Color(0xFF713F12),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    _StickyIcon(
                      icon: Icons.chevron_right_rounded,
                      tooltip: 'Next note',
                      onPressed: _current < total - 1 ? () => _go(1) : null,
                    ),
                    const SizedBox(width: 4),
                  ],
                  _StickyIcon(
                    icon: Icons.add_rounded,
                    tooltip: 'New note',
                    onPressed: _addNote,
                  ),
                  _StickyIcon(
                    icon: Icons.delete_outline_rounded,
                    tooltip: 'Delete note',
                    onPressed: _deleteCurrent,
                  ),
                ],
              ),
            ),
            // Note body (rich text on the sticky background).
            Flexible(
              child: Container(
                width: double.infinity,
                color: _stickyBody,
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                child: QuillEditor.basic(
                  controller: controller,
                  focusNode: _focusNode,
                  scrollController: _scrollController,
                  config: const QuillEditorConfig(
                    placeholder: 'Take a note…',
                    padding: EdgeInsets.zero,
                    autoFocus: true,
                  ),
                ),
              ),
            ),
            // Formatting toolbar.
            Container(
              width: double.infinity,
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: plannerBorder)),
              ),
              child: QuillSimpleToolbar(
                controller: controller,
                config: const QuillSimpleToolbarConfig(
                  multiRowsDisplay: false,
                  showDividers: false,
                  showBoldButton: true,
                  showItalicButton: true,
                  showUnderLineButton: true,
                  showStrikeThrough: true,
                  showListBullets: true,
                  showListNumbers: true,
                  // Everything else off for a clean sticky-note toolbar.
                  showFontFamily: false,
                  showFontSize: false,
                  showSmallButton: false,
                  showInlineCode: false,
                  showColorButton: false,
                  showBackgroundColorButton: false,
                  showClearFormat: false,
                  showAlignmentButtons: false,
                  showHeaderStyle: false,
                  showListCheck: false,
                  showCodeBlock: false,
                  showQuote: false,
                  showIndent: false,
                  showLink: false,
                  showUndo: false,
                  showRedo: false,
                  showDirection: false,
                  showSearchButton: false,
                  showSubscript: false,
                  showSuperscript: false,
                  showLineHeightButton: false,
                ),
              ),
            ),
            // Actions.
            Container(
              width: double.infinity,
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(
                children: [
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(onPressed: _save, child: const Text('Save')),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StickyIcon extends StatelessWidget {
  const _StickyIcon({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 32, height: 32),
      icon: Icon(
        icon,
        size: 19,
        color: onPressed == null
            ? const Color(0x55713F12)
            : const Color(0xFF713F12),
      ),
    );
  }
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
      titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      actionsPadding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
      title: _DialogTitle(widget.title),
      content: SizedBox(
        width: 400,
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
                  color: plannerText,
                  fontWeight: FontWeight.w500,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _availableColors.map((color) {
                  final isSelected = _selectedColor == color;
                  return InkWell(
                    onTap: () => setState(() => _selectedColor = color),
                    borderRadius: BorderRadius.circular(99),
                    child: Container(
                      width: 26,
                      height: 26,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isSelected ? color : Colors.transparent,
                          width: 1.6,
                        ),
                      ),
                      child: Container(
                        width: isSelected ? 16 : 20,
                        height: isSelected ? 16 : 20,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                        ),
                      ),
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
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      actionsPadding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
      title: _DialogTitle(isEditing ? 'Edit task' : 'New task'),
      content: SizedBox(
        width: 560,
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
                  decoration: _fieldDecoration(label: 'Task name'),
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
                          suffixIcon: _dueDateController.text.isEmpty
                              ? null
                              : _ClearFieldButton(
                                  onPressed: () => setState(() {
                                    _dueDate = null;
                                    _dueDateController.clear();
                                  }),
                                ),
                        ),
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: _dueDate ?? DateTime.now(),
                            firstDate: DateTime.now(),
                            lastDate: DateTime.now().add(
                              const Duration(days: 365),
                            ),
                            builder: (context, child) =>
                                _pickerTheme(context, child),
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
                          suffixIcon: _timelineController.text.isEmpty
                              ? null
                              : _ClearFieldButton(
                                  onPressed: () => setState(() {
                                    _timelineStart = null;
                                    _timelineEnd = null;
                                    _timelineController.clear();
                                  }),
                                ),
                        ),
                        onTap: () async {
                          final picked = await showDialog<DateTimeRange>(
                            context: context,
                            builder: (context) => _RangeCalendarDialog(
                              initialStart: _timelineStart,
                              initialEnd: _timelineEnd,
                            ),
                          );

                          if (picked != null) {
                            setState(() {
                              _timelineStart = picked.start;
                              _timelineEnd = picked.end;
                              _timelineController.text =
                                  '${_formatDate(picked.start)} - ${_formatDate(picked.end)}';
                            });
                          }
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Text(
                      'Progress',
                      style: TextStyle(
                        color: plannerText,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 4,
                          activeTrackColor: plannerBlue,
                          inactiveTrackColor: const Color(0xFFE4E7EF),
                          thumbColor: Colors.white,
                          overlayColor: plannerBlue.withValues(alpha: 0.10),
                          thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 8,
                            elevation: 2,
                          ),
                          overlayShape: const RoundSliderOverlayShape(
                            overlayRadius: 16,
                          ),
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
                      width: 40,
                      child: Text(
                        '${(_progress * 100).round()}%',
                        textAlign: TextAlign.end,
                        style: const TextStyle(
                          color: plannerInk,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
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
    return _SelectField<int>(
      label: 'Group',
      icon: Icons.view_week_outlined,
      value: value,
      onChanged: onChanged,
      items: [
        for (final group in groups)
          _SelectItem(value: group.id, label: group.name, color: group.color),
      ],
    );
  }
}

class _StatusDropdown extends StatelessWidget {
  const _StatusDropdown({required this.value, required this.onChanged});

  final TaskStatus value;
  final ValueChanged<TaskStatus> onChanged;

  @override
  Widget build(BuildContext context) {
    return _SelectField<TaskStatus>(
      label: 'Status',
      icon: Icons.flag_outlined,
      value: value,
      onChanged: onChanged,
      items: [
        for (final status in TaskStatus.values)
          _SelectItem(
            value: status,
            label: status.label,
            color: statusColor(status),
          ),
      ],
    );
  }
}

class _PriorityDropdown extends StatelessWidget {
  const _PriorityDropdown({required this.value, required this.onChanged});

  final TaskPriority value;
  final ValueChanged<TaskPriority> onChanged;

  @override
  Widget build(BuildContext context) {
    return _SelectField<TaskPriority>(
      label: 'Priority',
      icon: Icons.priority_high_rounded,
      value: value,
      onChanged: onChanged,
      items: [
        for (final priority in TaskPriority.values)
          _SelectItem(
            value: priority,
            label: priority.label,
            color: priorityColor(priority),
          ),
      ],
    );
  }
}

class _SelectItem<T> {
  const _SelectItem({
    required this.value,
    required this.label,
    required this.color,
  });

  final T value;
  final String label;
  final Color color;
}

/// A form-styled select whose menu opens *below* the field (never covering it).
class _SelectField<T> extends StatelessWidget {
  const _SelectField({
    required this.label,
    required this.icon,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final String label;
  final IconData icon;
  final T value;
  final List<_SelectItem<T>> items;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final selected = items.firstWhere(
      (item) => item.value == value,
      orElse: () => items.first,
    );

    return PopupMenuButton<T>(
      tooltip: '',
      position: PopupMenuPosition.under,
      offset: const Offset(0, 6),
      constraints: const BoxConstraints(minWidth: 240, maxHeight: 320),
      onSelected: onChanged,
      itemBuilder: (context) => [
        for (final item in items)
          PopupMenuItem<T>(
            value: item.value,
            height: 40,
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: item.color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    item.label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: item.value == value ? plannerInk : plannerText,
                      fontSize: 13,
                      fontWeight: item.value == value
                          ? FontWeight.w600
                          : FontWeight.w500,
                    ),
                  ),
                ),
                if (item.value == value)
                  const Icon(Icons.check_rounded, size: 16, color: plannerBlue),
              ],
            ),
          ),
      ],
      child: InputDecorator(
        isEmpty: false,
        decoration: _fieldDecoration(label: label, icon: icon),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: selected.color,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                selected.label,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: plannerInk,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 18,
              color: plannerMuted,
            ),
          ],
        ),
      ),
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
        fontSize: 16,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _ClearFieldButton extends StatelessWidget {
  const _ClearFieldButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Clear',
      onPressed: onPressed,
      splashRadius: 18,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 32, height: 32),
      icon: const Icon(Icons.close_rounded, size: 16, color: plannerMuted),
    );
  }
}

InputDecoration _fieldDecoration({
  required String label,
  String? hint,
  IconData? icon,
  Widget? suffixIcon,
}) {
  return InputDecoration(
    labelText: label,
    hintText: hint,
    labelStyle: const TextStyle(
      color: plannerMuted,
      fontSize: 13,
      fontWeight: FontWeight.w400,
    ),
    floatingLabelStyle: const TextStyle(color: plannerBlue, fontSize: 13),
    suffixIcon: suffixIcon,
    suffixIconConstraints: const BoxConstraints(minWidth: 36, minHeight: 36),
    prefixIcon: icon == null
        ? null
        : Icon(icon, size: 18, color: plannerMuted),
    filled: true,
    fillColor: Colors.white,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(6),
      borderSide: const BorderSide(color: plannerBorder),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(6),
      borderSide: const BorderSide(color: plannerBlue, width: 1.4),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(6),
      borderSide: const BorderSide(color: plannerRed),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(6),
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

Widget _pickerTheme(BuildContext context, Widget? child) {
  return Theme(
    data: ThemeData.light().copyWith(
      colorScheme: const ColorScheme.light(
        primary: plannerBlue,
        onPrimary: Colors.white,
        surface: Colors.white,
        onSurface: plannerInk,
      ),
      textTheme: Theme.of(context).textTheme,
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        rangeSelectionBackgroundColor: plannerBlue.withValues(alpha: 0.10),
        todayBackgroundColor: WidgetStateProperty.all(
          plannerBlue.withValues(alpha: 0.12),
        ),
        todayForegroundColor: WidgetStateProperty.all(plannerBlue),
      ),
    ),
    child: child!,
  );
}

const _kMonthNames = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

const _kMonthShort = [
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

/// A compact single-month calendar for picking a date range without the
/// full-screen Material range picker. Tap a start day, then an end day.
class _RangeCalendarDialog extends StatefulWidget {
  const _RangeCalendarDialog({
    required this.initialStart,
    required this.initialEnd,
  });

  final DateTime? initialStart;
  final DateTime? initialEnd;

  @override
  State<_RangeCalendarDialog> createState() => _RangeCalendarDialogState();
}

class _RangeCalendarDialogState extends State<_RangeCalendarDialog> {
  DateTime? _start;
  DateTime? _end;
  late DateTime _visibleMonth;

  @override
  void initState() {
    super.initState();
    _start = widget.initialStart;
    _end = widget.initialEnd;
    final anchor = widget.initialStart ?? DateTime.now();
    _visibleMonth = DateTime(anchor.year, anchor.month);
  }

  void _changeMonth(int delta) {
    setState(() {
      _visibleMonth = DateTime(_visibleMonth.year, _visibleMonth.month + delta);
    });
  }

  void _onTapDay(DateTime day) {
    setState(() {
      if (_start == null || _end != null) {
        _start = day;
        _end = null;
      } else if (day.isBefore(_start!)) {
        _end = _start;
        _start = day;
      } else {
        _end = day;
      }
    });
  }

  bool _isSame(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  bool _inRange(DateTime day) {
    if (_start == null || _end == null) return false;
    final d = DateTime(day.year, day.month, day.day);
    return !d.isBefore(_start!) && !d.isAfter(_end!);
  }

  String get _summary {
    if (_start == null) return 'Select a start date';
    final startLabel = '${_kMonthShort[_start!.month - 1]} ${_start!.day}';
    if (_end == null) return '$startLabel — select end date';
    final endLabel = '${_kMonthShort[_end!.month - 1]} ${_end!.day}';
    return '$startLabel — $endLabel';
  }

  @override
  Widget build(BuildContext context) {
    final firstDay = DateTime(_visibleMonth.year, _visibleMonth.month);
    final firstVisible = firstDay.subtract(Duration(days: firstDay.weekday % 7));
    final days = List.generate(
      42,
      (index) => firstVisible.add(Duration(days: index)),
    );
    final now = DateTime.now();

    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _DialogTitle('Set timeline'),
          const SizedBox(height: 2),
          Text(
            _summary,
            style: const TextStyle(color: plannerMuted, fontSize: 12.5),
          ),
        ],
      ),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                _NavButton(
                  icon: Icons.chevron_left_rounded,
                  onPressed: () => _changeMonth(-1),
                ),
                Expanded(
                  child: Text(
                    '${_kMonthNames[_visibleMonth.month - 1]} ${_visibleMonth.year}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: plannerInk,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                _NavButton(
                  icon: Icons.chevron_right_rounded,
                  onPressed: () => _changeMonth(1),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                for (final d in const ['S', 'M', 'T', 'W', 'T', 'F', 'S'])
                  Expanded(
                    child: Center(
                      child: Text(
                        d,
                        style: const TextStyle(
                          color: plannerMuted,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            for (var row = 0; row < 6; row++)
              Row(
                children: [
                  for (var col = 0; col < 7; col++)
                    Expanded(
                      child: _DayTile(
                        day: days[row * 7 + col],
                        outside:
                            days[row * 7 + col].month != _visibleMonth.month,
                        isStart:
                            _start != null &&
                            _isSame(days[row * 7 + col], _start!),
                        isEnd:
                            _end != null && _isSame(days[row * 7 + col], _end!),
                        inRange: _inRange(days[row * 7 + col]),
                        isToday: _isSame(days[row * 7 + col], now),
                        onTap: () => _onTapDay(days[row * 7 + col]),
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
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _start != null && _end != null
              ? () => Navigator.of(
                  context,
                ).pop(DateTimeRange(start: _start!, end: _end!))
              : null,
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({required this.icon, required this.onPressed});

  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: 30,
        height: 30,
        alignment: Alignment.center,
        child: Icon(icon, size: 20, color: plannerText),
      ),
    );
  }
}

class _DayTile extends StatelessWidget {
  const _DayTile({
    required this.day,
    required this.outside,
    required this.isStart,
    required this.isEnd,
    required this.inRange,
    required this.isToday,
    required this.onTap,
  });

  final DateTime day;
  final bool outside;
  final bool isStart;
  final bool isEnd;
  final bool inRange;
  final bool isToday;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isEndpoint = isStart || isEnd;
    final rangeBg = plannerBlue.withValues(alpha: 0.10);

    BorderRadius? bandRadius;
    if (isStart && isEnd) {
      bandRadius = BorderRadius.circular(8);
    } else if (isStart) {
      bandRadius = const BorderRadius.horizontal(left: Radius.circular(8));
    } else if (isEnd) {
      bandRadius = const BorderRadius.horizontal(right: Radius.circular(8));
    }

    return SizedBox(
      height: 38,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (inRange)
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  color: rangeBg,
                  borderRadius: bandRadius,
                ),
              ),
            ),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isEndpoint ? plannerBlue : Colors.transparent,
                  shape: BoxShape.circle,
                  border: isToday && !isEndpoint
                      ? Border.all(color: plannerBlue.withValues(alpha: 0.4))
                      : null,
                ),
                child: Text(
                  '${day.day}',
                  style: TextStyle(
                    color: isEndpoint
                        ? Colors.white
                        : outside
                        ? plannerMuted.withValues(alpha: 0.5)
                        : plannerInk,
                    fontSize: 12.5,
                    fontWeight: isEndpoint
                        ? FontWeight.w600
                        : FontWeight.w500,
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
