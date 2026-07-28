import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';

import '../../core/drift/app_database.dart' show AppDatabase;
import '../../models/planner_models.dart';
import '../../shared/utils/planner_colors.dart';
import '../planner/widgets/planner_dialogs.dart' show docFromNote;

/// Canvas bounds. Generous enough to spread notes out, bounded so a dragged
/// note can never be lost off-screen.
const double _canvasWidth = 4000;
const double _canvasHeight = 3000;
const double _minNoteWidth = 180;
const double _minNoteHeight = 140;

/// A freeform sticky-note board: notes are dragged anywhere on an infinite-feel
/// canvas and their positions persist across sessions.
class NotesCanvasPage extends StatefulWidget {
  const NotesCanvasPage({
    super.key,
    required this.database,
    this.onOpenTask,
    this.onNotesChanged,
  });

  final AppDatabase database;

  /// Invoked when a task-linked note's chip is tapped.
  final void Function(int taskId)? onOpenTask;

  /// Reports the current note count so the sidebar badge stays in sync.
  final ValueChanged<int>? onNotesChanged;

  @override
  State<NotesCanvasPage> createState() => _NotesCanvasPageState();
}

class _NotesCanvasPageState extends State<NotesCanvasPage> {
  final TransformationController _viewer = TransformationController();
  final TextEditingController _searchController = TextEditingController();

  List<StickyNote> _notes = [];
  String _query = '';
  bool _loading = true;
  String? _error;
  int? _editingId;

  /// Positions being dragged right now, so the card follows the cursor without
  /// waiting on a database round trip.
  final Map<int, Offset> _dragOverrides = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _viewer.dispose();
    _searchController.dispose();
    super.dispose();
  }

  List<StickyNote> get _visibleNotes {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) {
      return _notes;
    }
    return _notes.where((note) {
      if (note.title.toLowerCase().contains(query)) {
        return true;
      }
      return _plainBody(note.body).toLowerCase().contains(query);
    }).toList();
  }

  Future<void> _load() async {
    try {
      final notes = await widget.database.loadStickyNotes();
      if (!mounted) {
        return;
      }
      setState(() {
        _notes = notes;
        _loading = false;
        _error = null;
      });
      widget.onNotesChanged?.call(notes.length);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  /// Mirrors the planner page: surface failures instead of swallowing them.
  Future<bool> _guard(
    Future<void> Function() action, {
    String? failureMessage,
  }) async {
    try {
      await action();
      return true;
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              behavior: SnackBarBehavior.floating,
              backgroundColor: plannerRed,
              content: Text(failureMessage ?? 'Something went wrong: $error'),
            ),
          );
      }
      return false;
    }
  }

  /// Places a new note near the center of what the user is currently looking at,
  /// nudged by the note count so consecutive notes cascade instead of stacking.
  Offset _spawnPoint() {
    final viewport = context.size ?? const Size(1200, 800);
    final matrix = _viewer.value;
    final scale = matrix.getMaxScaleOnAxis();
    final translation = matrix.getTranslation();
    final centerX = (-translation.x + viewport.width / 2) / scale;
    final centerY = (-translation.y + viewport.height / 2) / scale;

    final cascade = (_notes.length % 6) * 28.0;
    return Offset(
      (centerX - 130 + cascade).clamp(0.0, _canvasWidth - 280),
      (centerY - 120 + cascade).clamp(0.0, _canvasHeight - 260),
    );
  }

  Future<void> _createNote({Color? color}) async {
    final spawn = _spawnPoint();
    final paletteColor =
        color ?? notePalette[_notes.length % notePalette.length];

    int? newId;
    final ok = await _guard(() async {
      newId = await widget.database.createStickyNote(
        x: spawn.dx,
        y: spawn.dy,
        color: paletteColor,
      );
      await _load();
    }, failureMessage: 'Could not create the note.');

    if (ok && mounted && newId != null) {
      // Drop straight into editing — a new note is always empty.
      setState(() => _editingId = newId);
    }
  }

  Future<void> _saveNote(StickyNote note, String title, String body) async {
    // Optimistic: keep the typed content on screen while the write lands.
    _replaceLocal(note.copyWith(title: title, body: body));
    await _guard(() async {
      await widget.database.updateStickyContent(
        noteId: note.id,
        title: title,
        body: body,
      );
      await _load();
    }, failureMessage: 'Could not save the note.');
  }

  Future<void> _moveNote(StickyNote note, Offset position) async {
    final x = position.dx.clamp(0.0, _canvasWidth - note.width);
    final y = position.dy.clamp(0.0, _canvasHeight - note.height);
    _replaceLocal(note.copyWith(x: x, y: y));
    setState(() => _dragOverrides.remove(note.id));

    await _guard(() async {
      await widget.database.moveStickyNote(noteId: note.id, x: x, y: y);
    }, failureMessage: 'Could not move the note.');
  }

  Future<void> _resizeNote(StickyNote note, Size size) async {
    final width = size.width.clamp(_minNoteWidth, 720.0);
    final height = size.height.clamp(_minNoteHeight, 720.0);
    _replaceLocal(note.copyWith(width: width, height: height));

    await _guard(() async {
      await widget.database.resizeStickyNote(
        noteId: note.id,
        width: width,
        height: height,
      );
    }, failureMessage: 'Could not resize the note.');
  }

  Future<void> _recolorNote(StickyNote note, Color color) async {
    _replaceLocal(note.copyWith(color: color));
    await _guard(() async {
      await widget.database.updateStickyColor(noteId: note.id, color: color);
      await _load();
    }, failureMessage: 'Could not change the color.');
  }

  Future<void> _togglePin(StickyNote note) async {
    _replaceLocal(note.copyWith(pinned: !note.pinned));
    await _guard(() async {
      await widget.database.setStickyPinned(
        noteId: note.id,
        pinned: !note.pinned,
      );
      await _load();
    }, failureMessage: 'Could not pin the note.');
  }

  Future<void> _bringToFront(StickyNote note) async {
    if (_notes.isNotEmpty && _notes.last.id == note.id) {
      return; // Already on top.
    }
    await _guard(() async {
      await widget.database.bringStickyToFront(note.id);
      await _load();
    });
  }

  Future<void> _deleteNote(StickyNote note) async {
    final label = note.title.trim().isEmpty
        ? _plainBody(note.body).trim()
        : note.title.trim();
    final preview = label.isEmpty
        ? 'this empty note'
        : '"${label.length > 40 ? '${label.substring(0, 40)}…' : label}"';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete note'),
        content: Text('Delete $preview? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: plannerRed),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }

    await _guard(() async {
      await widget.database.deleteStickyNote(note.id);
      await _load();
    }, failureMessage: 'Could not delete the note.');
  }

  void _replaceLocal(StickyNote updated) {
    if (!mounted) {
      return;
    }
    setState(() {
      final index = _notes.indexWhere((note) => note.id == updated.id);
      if (index >= 0) {
        final next = List<StickyNote>.from(_notes);
        next[index] = updated;
        _notes = next;
      }
    });
  }

  void _resetView() {
    _viewer.value = Matrix4.identity();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _NotesHeader(
          noteCount: _notes.length,
          searchController: _searchController,
          query: _query,
          onSearchChanged: (value) => setState(() => _query = value),
          onCreateNote: () => _createNote(),
          onResetView: _resetView,
        ),
        Expanded(child: _buildCanvas()),
      ],
    );
  }

  Widget _buildCanvas() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Text(_error!, style: const TextStyle(color: plannerRed)),
      );
    }

    final visible = _visibleNotes;

    return Stack(
      children: [
        Positioned.fill(
          child: InteractiveViewer(
            transformationController: _viewer,
            minScale: 0.4,
            maxScale: 2.0,
            boundaryMargin: const EdgeInsets.all(200),
            // Notes handle their own drag gestures, so panning is driven by the
            // background only.
            panEnabled: true,
            scaleEnabled: true,
            child: SizedBox(
              width: _canvasWidth,
              height: _canvasHeight,
              child: DecoratedBox(
                decoration: const BoxDecoration(color: plannerSurface),
                child: CustomPaint(
                  painter: _CanvasGridPainter(),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      for (final note in visible)
                        _PositionedNote(
                          key: ValueKey(note.id),
                          note: note,
                          dragOffset: _dragOverrides[note.id],
                          editing: _editingId == note.id,
                          onDragUpdate: (offset) {
                            setState(() => _dragOverrides[note.id] = offset);
                          },
                          onDragEnd: (offset) => _moveNote(note, offset),
                          onResize: (size) => _resizeNote(note, size),
                          onTapDown: () => _bringToFront(note),
                          onStartEditing: () =>
                              setState(() => _editingId = note.id),
                          onStopEditing: (title, body) {
                            setState(() => _editingId = null);
                            _saveNote(note, title, body);
                          },
                          onCancelEditing: () =>
                              setState(() => _editingId = null),
                          onRecolor: (color) => _recolorNote(note, color),
                          onTogglePin: () => _togglePin(note),
                          onDelete: () => _deleteNote(note),
                          onOpenTask: widget.onOpenTask,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        if (_notes.isEmpty)
          Positioned.fill(
            child: IgnorePointer(
              child: _EmptyNotesState(),
            ),
          ),
        if (_notes.isNotEmpty && visible.isEmpty)
          Positioned.fill(
            child: IgnorePointer(
              child: Center(
                child: Text(
                  'No notes match "$_query"',
                  style: const TextStyle(color: plannerMuted, fontSize: 14),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

String _plainBody(String body) {
  try {
    return docFromNote(body).toPlainText().trim();
  } catch (_) {
    return body;
  }
}

/// Subtle dot grid, so dragging has a sense of space without competing with the
/// notes themselves.
class _CanvasGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0xFFDCE0EC);
    const spacing = 32.0;
    for (var x = 0.0; x < size.width; x += spacing) {
      for (var y = 0.0; y < size.height; y += spacing) {
        canvas.drawCircle(Offset(x, y), 1.1, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _CanvasGridPainter oldDelegate) => false;
}

class _NotesHeader extends StatelessWidget {
  const _NotesHeader({
    required this.noteCount,
    required this.searchController,
    required this.query,
    required this.onSearchChanged,
    required this.onCreateNote,
    required this.onResetView,
  });

  final int noteCount;
  final TextEditingController searchController;
  final String query;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onCreateNote;
  final VoidCallback onResetView;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(28, 22, 28, 18),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: plannerBorder)),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: noteYellow,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: noteBorderColor(noteYellow)),
            ),
            child: const Icon(
              Icons.sticky_note_2_rounded,
              size: 18,
              color: Color(0xFF8A6D00),
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Notes',
                style: TextStyle(
                  color: plannerInk,
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                noteCount == 0
                    ? 'Drag notes anywhere on the canvas'
                    : '$noteCount note${noteCount == 1 ? '' : 's'}',
                style: const TextStyle(color: plannerMuted, fontSize: 12),
              ),
            ],
          ),
          const Spacer(),
          SizedBox(
            width: 240,
            height: 36,
            child: TextField(
              controller: searchController,
              onChanged: onSearchChanged,
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Search notes',
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  size: 18,
                  color: plannerMuted,
                ),
                prefixIconConstraints: const BoxConstraints(
                  minWidth: 36,
                  minHeight: 36,
                ),
                suffixIcon: query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close_rounded, size: 16),
                        color: plannerMuted,
                        onPressed: () {
                          searchController.clear();
                          onSearchChanged('');
                        },
                      ),
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Tooltip(
            message: 'Reset view',
            child: OutlinedButton(
              onPressed: onResetView,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(36, 36),
                padding: EdgeInsets.zero,
                fixedSize: const Size(36, 36),
              ),
              child: const Icon(
                Icons.center_focus_strong_rounded,
                size: 17,
                color: plannerMuted,
              ),
            ),
          ),
          const SizedBox(width: 10),
          FilledButton.icon(
            onPressed: onCreateNote,
            icon: const Icon(Icons.add_rounded, size: 16),
            label: const Text('New note'),
          ),
        ],
      ),
    );
  }
}

class _EmptyNotesState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // A small stack of tilted notes, hinting at what the canvas is for.
          SizedBox(
            width: 132,
            height: 108,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Transform.rotate(
                  angle: -0.16,
                  child: _GhostNote(color: noteBlue, offset: const Offset(-26, 6)),
                ),
                Transform.rotate(
                  angle: 0.12,
                  child: _GhostNote(color: notePink, offset: const Offset(26, 2)),
                ),
                _GhostNote(color: noteYellow, offset: Offset.zero),
              ],
            ),
          ),
          const SizedBox(height: 22),
          const Text(
            'Your canvas is empty',
            style: TextStyle(
              color: plannerInk,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          const SizedBox(
            width: 320,
            child: Text(
              'Create a note, then drag it anywhere. Positions are saved '
              'automatically.',
              textAlign: TextAlign.center,
              style: TextStyle(color: plannerMuted, fontSize: 13, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _GhostNote extends StatelessWidget {
  const _GhostNote({required this.color, required this.offset});

  final Color color;
  final Offset offset;

  @override
  Widget build(BuildContext context) {
    return Transform.translate(
      offset: offset,
      child: Container(
        width: 74,
        height: 74,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: noteBorderColor(color)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x1A101828),
              blurRadius: 12,
              offset: Offset(0, 4),
            ),
          ],
        ),
      ),
    );
  }
}

/// A single note card placed on the canvas, handling its own drag, resize and
/// inline editing.
class _PositionedNote extends StatefulWidget {
  const _PositionedNote({
    super.key,
    required this.note,
    required this.dragOffset,
    required this.editing,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.onResize,
    required this.onTapDown,
    required this.onStartEditing,
    required this.onStopEditing,
    required this.onCancelEditing,
    required this.onRecolor,
    required this.onTogglePin,
    required this.onDelete,
    required this.onOpenTask,
  });

  final StickyNote note;
  final Offset? dragOffset;
  final bool editing;
  final ValueChanged<Offset> onDragUpdate;
  final ValueChanged<Offset> onDragEnd;
  final ValueChanged<Size> onResize;
  final VoidCallback onTapDown;
  final VoidCallback onStartEditing;
  final void Function(String title, String body) onStopEditing;
  final VoidCallback onCancelEditing;
  final ValueChanged<Color> onRecolor;
  final VoidCallback onTogglePin;
  final VoidCallback onDelete;
  final void Function(int taskId)? onOpenTask;

  @override
  State<_PositionedNote> createState() => _PositionedNoteState();
}

class _PositionedNoteState extends State<_PositionedNote> {
  late QuillController _quill;
  late TextEditingController _title;
  final FocusNode _bodyFocus = FocusNode();
  bool _hovered = false;
  Size? _resizeDraft;

  @override
  void initState() {
    super.initState();
    _buildControllers();
  }

  @override
  void didUpdateWidget(_PositionedNote oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Rebuild controllers when entering edit mode, so the editor starts from the
    // persisted content rather than stale in-memory state.
    if (widget.editing && !oldWidget.editing) {
      _disposeControllers();
      _buildControllers();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _bodyFocus.requestFocus();
        }
      });
    }
  }

  void _buildControllers() {
    _quill = QuillController(
      document: docFromNote(widget.note.body),
      selection: const TextSelection.collapsed(offset: 0),
    );
    _title = TextEditingController(text: widget.note.title);
  }

  void _disposeControllers() {
    _quill.dispose();
    _title.dispose();
  }

  @override
  void dispose() {
    _disposeControllers();
    _bodyFocus.dispose();
    super.dispose();
  }

  void _commit() {
    final body = jsonEncode(_quill.document.toDelta().toJson());
    widget.onStopEditing(_title.text, body);
  }

  @override
  Widget build(BuildContext context) {
    final note = widget.note;
    final position = widget.dragOffset ?? Offset(note.x, note.y);
    final size = _resizeDraft ?? Size(note.width, note.height);
    final dragging = widget.dragOffset != null;

    return Positioned(
      left: position.dx,
      top: position.dy,
      width: size.width,
      height: size.height,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: AnimatedScale(
          scale: dragging ? 1.03 : 1.0,
          duration: const Duration(milliseconds: 120),
          child: Material(
            color: Colors.transparent,
            child: Container(
              decoration: BoxDecoration(
                color: note.color,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: widget.editing
                      ? plannerBlue
                      : noteBorderColor(note.color),
                  width: widget.editing ? 1.6 : 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Color(dragging ? 0x33101828 : 0x1A101828),
                    blurRadius: dragging ? 22 : 10,
                    offset: Offset(0, dragging ? 10 : 3),
                  ),
                ],
              ),
              child: Column(
                children: [
                  _buildHeader(note),
                  Expanded(child: _buildBody(note)),
                  if (note.isLinkedToTask) _buildTaskChip(note),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(StickyNote note) {
    // The header is the drag handle — same affordance as Sticky Notes.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: (_) => widget.onTapDown(),
      onPanUpdate: (details) {
        final current = widget.dragOffset ?? Offset(note.x, note.y);
        widget.onDragUpdate(current + details.delta);
      },
      onPanEnd: (_) {
        final current = widget.dragOffset;
        if (current != null) {
          widget.onDragEnd(current);
        }
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.move,
        child: Container(
          height: 34,
          padding: const EdgeInsets.only(left: 10, right: 4),
          decoration: BoxDecoration(
            color: noteHeaderColor(note.color),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(7)),
          ),
          child: Row(
            children: [
              Icon(
                Icons.drag_indicator_rounded,
                size: 15,
                color: plannerInk.withValues(alpha: 0.35),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: widget.editing
                    ? TextField(
                        controller: _title,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: plannerInk,
                        ),
                        decoration: const InputDecoration(
                          isDense: true,
                          filled: false,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          contentPadding: EdgeInsets.zero,
                          hintText: 'Title',
                        ),
                      )
                    : Text(
                        note.title.trim().isEmpty ? 'Untitled' : note.title,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: note.title.trim().isEmpty
                              ? plannerInk.withValues(alpha: 0.4)
                              : plannerInk,
                        ),
                      ),
              ),
              if (note.pinned)
                Padding(
                  padding: const EdgeInsets.only(right: 2),
                  child: Icon(
                    Icons.push_pin_rounded,
                    size: 13,
                    color: plannerInk.withValues(alpha: 0.55),
                  ),
                ),
              if (_hovered || widget.editing) _buildHeaderActions(note),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderActions(StickyNote note) {
    if (widget.editing) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _HeaderIconButton(
            icon: Icons.close_rounded,
            tooltip: 'Discard changes',
            onPressed: widget.onCancelEditing,
          ),
          _HeaderIconButton(
            icon: Icons.check_rounded,
            tooltip: 'Save',
            emphasized: true,
            onPressed: _commit,
          ),
        ],
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ColorMenuButton(current: note.color, onSelected: widget.onRecolor),
        _NoteMenuButton(
          pinned: note.pinned,
          onEdit: widget.onStartEditing,
          onTogglePin: widget.onTogglePin,
          onDelete: widget.onDelete,
        ),
      ],
    );
  }

  Widget _buildBody(StickyNote note) {
    if (widget.editing) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 4),
        child: Column(
          children: [
            Expanded(
              child: QuillEditor.basic(
                controller: _quill,
                focusNode: _bodyFocus,
                config: QuillEditorConfig(
                  placeholder: 'Take a note…',
                  padding: EdgeInsets.zero,
                  customStyles: DefaultStyles(
                    paragraph: DefaultTextBlockStyle(
                      const TextStyle(
                        fontSize: 13,
                        height: 1.45,
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
            _CompactQuillToolbar(controller: _quill),
          ],
        ),
      );
    }

    // Read mode: tap anywhere on the body to start editing.
    final preview = _plainBody(note.body);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        widget.onTapDown();
        widget.onStartEditing();
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: SizedBox(
          width: double.infinity,
          child: preview.isEmpty
              ? Text(
                  'Empty note — click to write',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontStyle: FontStyle.italic,
                    color: plannerInk.withValues(alpha: 0.38),
                  ),
                )
              : Text(
                  preview,
                  overflow: TextOverflow.fade,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.45,
                    color: plannerInk,
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildTaskChip(StickyNote note) {
    final taskId = note.taskId;
    if (taskId == null) {
      return const SizedBox.shrink();
    }
    return InkWell(
      onTap: widget.onOpenTask == null
          ? null
          : () => widget.onOpenTask!(taskId),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.4),
          borderRadius: const BorderRadius.vertical(bottom: Radius.circular(7)),
          border: Border(
            top: BorderSide(color: noteBorderColor(note.color)),
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.link_rounded,
              size: 13,
              color: plannerInk.withValues(alpha: 0.5),
            ),
            const SizedBox(width: 6),
            Text(
              'Linked to task',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: plannerInk.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.emphasized = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(5),
        onTap: onPressed,
        child: Container(
          width: 26,
          height: 26,
          alignment: Alignment.center,
          decoration: emphasized
              ? BoxDecoration(
                  color: plannerBlue,
                  borderRadius: BorderRadius.circular(5),
                )
              : null,
          child: Icon(
            icon,
            size: 15,
            color: emphasized
                ? Colors.white
                : plannerInk.withValues(alpha: 0.55),
          ),
        ),
      ),
    );
  }
}

class _ColorMenuButton extends StatelessWidget {
  const _ColorMenuButton({required this.current, required this.onSelected});

  final Color current;
  final ValueChanged<Color> onSelected;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<Color>(
      tooltip: 'Note color',
      offset: const Offset(0, 28),
      onSelected: onSelected,
      itemBuilder: (context) => [
        PopupMenuItem<Color>(
          enabled: false,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: SizedBox(
            width: 156,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final color in notePalette)
                  GestureDetector(
                    onTap: () {
                      Navigator.of(context).pop();
                      onSelected(color);
                    },
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: color.toARGB32() == current.toARGB32()
                              ? plannerBlue
                              : noteBorderColor(color),
                          width: color.toARGB32() == current.toARGB32()
                              ? 2
                              : 1,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
      child: SizedBox(
        width: 26,
        height: 26,
        child: Icon(
          Icons.palette_outlined,
          size: 15,
          color: plannerInk.withValues(alpha: 0.55),
        ),
      ),
    );
  }
}

class _NoteMenuButton extends StatelessWidget {
  const _NoteMenuButton({
    required this.pinned,
    required this.onEdit,
    required this.onTogglePin,
    required this.onDelete,
  });

  final bool pinned;
  final VoidCallback onEdit;
  final VoidCallback onTogglePin;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_NoteAction>(
      tooltip: 'Note actions',
      offset: const Offset(0, 28),
      onSelected: (action) {
        switch (action) {
          case _NoteAction.edit:
            onEdit();
          case _NoteAction.pin:
            onTogglePin();
          case _NoteAction.delete:
            onDelete();
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: _NoteAction.edit,
          child: _MenuLabel(icon: Icons.edit_outlined, label: 'Edit note'),
        ),
        PopupMenuItem(
          value: _NoteAction.pin,
          child: _MenuLabel(
            icon: pinned
                ? Icons.push_pin_rounded
                : Icons.push_pin_outlined,
            label: pinned ? 'Unpin' : 'Pin note',
          ),
        ),
        const PopupMenuItem(
          value: _NoteAction.delete,
          child: _MenuLabel(
            icon: Icons.delete_outline_rounded,
            label: 'Delete note',
            danger: true,
          ),
        ),
      ],
      child: SizedBox(
        width: 26,
        height: 26,
        child: Icon(
          Icons.more_horiz_rounded,
          size: 16,
          color: plannerInk.withValues(alpha: 0.55),
        ),
      ),
    );
  }
}

enum _NoteAction { edit, pin, delete }

class _MenuLabel extends StatelessWidget {
  const _MenuLabel({
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

/// A trimmed formatting bar sized for a note card — the full Quill toolbar is
/// far too wide here.
class _CompactQuillToolbar extends StatelessWidget {
  const _CompactQuillToolbar({required this.controller});

  final QuillController controller;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 32,
      child: QuillSimpleToolbar(
        controller: controller,
        config: const QuillSimpleToolbarConfig(
          toolbarIconAlignment: WrapAlignment.start,
          toolbarSectionSpacing: 0,
          buttonOptions: QuillSimpleToolbarButtonOptions(
            base: QuillToolbarBaseButtonOptions(
              iconSize: 14,
              iconButtonFactor: 1.5,
            ),
          ),
          multiRowsDisplay: false,
          showFontFamily: false,
          showFontSize: false,
          showBoldButton: true,
          showItalicButton: true,
          showUnderLineButton: true,
          showStrikeThrough: true,
          showListBullets: true,
          showListNumbers: true,
          showListCheck: true,
          showDividers: false,
          showInlineCode: false,
          showColorButton: false,
          showBackgroundColorButton: false,
          showClearFormat: false,
          showAlignmentButtons: false,
          showHeaderStyle: false,
          showQuote: false,
          showIndent: false,
          showLink: false,
          showUndo: false,
          showRedo: false,
          showSearchButton: false,
          showSubscript: false,
          showSuperscript: false,
          showCodeBlock: false,
        ),
      ),
    );
  }
}
