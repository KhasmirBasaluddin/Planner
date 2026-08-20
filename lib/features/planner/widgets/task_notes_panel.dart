import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/supabase/planner_repository.dart';
import '../../../models/planner_models.dart';
import '../../../shared/utils/planner_colors.dart';
import '../../../shared/widgets/user_avatar.dart';
import 'review_dialog.dart' show contentTypeForFile;

/// A task's work log: what was done, and what proves it.
///
/// Separate from the chat on purpose. A conversation is chronological and
/// disposable; a work note is evidence attached to a moment in the task's
/// life, and it carries the status the task moved between. Mixing the two
/// buried the proof of completion between "ok" and "thanks".
class TaskNotesPanel extends StatefulWidget {
  const TaskNotesPanel({
    super.key,
    required this.task,
    required this.workspaceId,
    required this.repository,
    required this.currentUserId,
    required this.canEdit,
    required this.statuses,
    this.onCountChanged,
    this.onApprove,
  });

  final PlannerTask task;
  final String workspaceId;
  final PlannerRepository repository;
  final String currentUserId;

  /// Viewers read the log but cannot add to it.
  final bool canEdit;

  /// The board's own labels, so a note can name the status it moved between
  /// rather than showing a raw id.
  final List<StatusLabel> statuses;

  /// Reports how many notes the task now has, so the tab count and the
  /// board's badge move the moment one lands rather than after a reload.
  final ValueChanged<int>? onCountChanged;

  /// Signs off on the work. Null for anyone who cannot review — a member
  /// approving their own submission is exactly what the split prevents.
  final VoidCallback? onApprove;

  @override
  State<TaskNotesPanel> createState() => _TaskNotesPanelState();
}

class _TaskNotesPanelState extends State<TaskNotesPanel> {
  final TextEditingController _composer = TextEditingController();
  final ScrollController _scroll = ScrollController();

  List<TaskNote> _notes = [];
  final List<NoteUpload> _pending = [];

  bool _loading = true;
  bool _saving = false;
  String? _error;
  RealtimeChannel? _channel;

  @override
  void initState() {
    super.initState();
    _load();
    _channel = widget.repository.subscribeToTaskNotes(
      taskId: widget.task.id,
      onChange: () {
        if (mounted) {
          _load();
        }
      },
    );
    _composer.addListener(_redraw);
  }

  void _redraw() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _composer.dispose();
    _scroll.dispose();
    final channel = _channel;
    if (channel != null) {
      widget.repository.unsubscribe(channel);
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final notes = await widget.repository.loadNotes(widget.task.id);
      if (mounted) {
        setState(() {
          _notes = notes;
          _loading = false;
          _error = null;
        });
        widget.onCountChanged?.call(notes.length);
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = _describe(error);
        });
      }
    }
  }

  Future<void> _pickFiles() async {
    final result = await FilePicker.pickFiles(
      dialogTitle: 'Attach to note',
      allowMultiple: true,
      // Keeps the picker in front of the app on Windows rather than letting
      // it open behind the dialog that asked for it.
      lockParentWindow: true,
      // Bytes rather than a path: the upload wants the contents, and on
      // desktop a path would mean reading the file a second time.
      withData: true,
    );
    if (result == null) {
      return;
    }

    final rejected = <String>[];
    for (final file in result.files) {
      final bytes = file.bytes;
      if (bytes == null) {
        continue;
      }
      if (bytes.length > PlannerRepository.maxAttachmentBytes) {
        rejected.add(file.name);
        continue;
      }
      _pending.add(
        NoteUpload(
          fileName: file.name,
          bytes: bytes,
          contentType: contentTypeForFile(file.name),
        ),
      );
    }

    if (mounted) {
      setState(() {
        _error = rejected.isEmpty
            ? null
            : '${rejected.join(', ')} — larger than 25 MB, not attached.';
      });
    }
  }

  /// True once the newest note is already an approval — nothing left to sign
  /// off, so the bar would only invite a duplicate.
  bool get _awaitingNothing =>
      _notes.isNotEmpty && _notes.last.kind == TaskNoteKind.approval;

  bool get _canPost =>
      _composer.text.trim().isNotEmpty || _pending.isNotEmpty;

  Future<void> _post() async {
    if (!_canPost || _saving) {
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await widget.repository.addNote(
        taskId: widget.task.id,
        workspaceId: widget.workspaceId,
        body: _composer.text,
        uploads: List.of(_pending),
      );
      if (!mounted) {
        return;
      }
      _composer.clear();
      setState(() {
        _pending.clear();
        _saving = false;
      });
      await _load();
      _scrollToEnd();
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = _describe(error);
        });
      }
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  Future<void> _delete(TaskNote note) async {
    try {
      await widget.repository.deleteNote(note.id);
      await _load();
    } catch (error) {
      if (mounted) {
        setState(() => _error = _describe(error));
      }
    }
  }

  String _describe(Object error) {
    final raw = error.toString().replaceFirst(RegExp(r'^\w+Exception: '), '');
    if (raw.contains('row-level security') || raw.contains('violates')) {
      return 'You do not have permission to do that.';
    }
    return raw;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_error != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
            color: tint(plannerRed, 0.08),
            child: Text(
              _error!,
              style: const TextStyle(color: plannerRed, fontSize: 12),
            ),
          ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(strokeWidth: 2.5))
              : _notes.isEmpty
              ? const _NotesEmpty()
              : ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
                  itemCount: _notes.length,
                  itemBuilder: (context, index) => _NoteCard(
                    note: _notes[index],
                    repository: widget.repository,
                    isMine: _notes[index].author?.id == widget.currentUserId,
                    onDelete: () => _delete(_notes[index]),
                  ),
                ),
        ),
        // Offered once there is something to judge, and only to reviewers.
        if (widget.onApprove != null && _notes.isNotEmpty && !_awaitingNothing)
          _ApproveBar(
            onApprove: () {
              widget.onApprove?.call();
              // The note arrives by realtime, but re-reading now means the
              // log updates the instant it is pressed.
              unawaited(Future<void>.delayed(
                const Duration(milliseconds: 350),
                _load,
              ));
            },
          ),
        if (widget.canEdit)
          _Composer(
            controller: _composer,
            pending: _pending,
            saving: _saving,
            canPost: _canPost,
            onAttach: _pickFiles,
            onRemoveAt: (index) => setState(() => _pending.removeAt(index)),
            onPost: _post,
          ),
      ],
    );
  }
}

/// One entry in the log.
/// Sign-off, above the composer.
class _ApproveBar extends StatelessWidget {
  const _ApproveBar({required this.onApprove});

  final VoidCallback onApprove;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        color: tint(plannerGreen, 0.06),
        border: const Border(top: BorderSide(color: plannerBorder)),
      ),
      child: Row(
        children: [
          const Icon(Icons.verified_outlined, size: 16, color: plannerGreen),
          const SizedBox(width: 9),
          const Expanded(
            child: Text(
              'Happy with this work? Sign it off so the log shows it was '
              'accepted.',
              style: TextStyle(
                color: plannerText,
                fontSize: 11.5,
                height: 1.4,
              ),
            ),
          ),
          const SizedBox(width: 10),
          FilledButton.icon(
            onPressed: onApprove,
            style: FilledButton.styleFrom(backgroundColor: plannerGreen),
            icon: const Icon(Icons.check_rounded, size: 16),
            label: const Text('Approve'),
          ),
        ],
      ),
    );
  }
}

class _NoteCard extends StatelessWidget {
  const _NoteCard({
    required this.note,
    required this.repository,
    required this.isMine,
    required this.onDelete,
  });

  final TaskNote note;
  final PlannerRepository repository;
  final bool isMine;
  final VoidCallback onDelete;

  /// Verdicts are colour-coded, because scanning the log for "was this ever
  /// sent back?" is the most common reason to open it.
  Color get _tone => switch (note.kind) {
    TaskNoteKind.submission => plannerBlue,
    TaskNoteKind.rejection => plannerRed,
    TaskNoteKind.approval => plannerGreen,
    TaskNoteKind.update => plannerSlate,
  };

  @override
  Widget build(BuildContext context) {
    final author = note.author;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: plannerCard,
        borderRadius: BorderRadius.circular(radiusMd),
        border: Border.all(color: tint(_tone, 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(12, 9, 8, 9),
            decoration: BoxDecoration(
              color: tint(_tone, 0.07),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(radiusMd),
              ),
            ),
            child: Row(
              children: [
                Icon(note.kind.icon, size: 15, color: _tone),
                const SizedBox(width: 7),
                Text(
                  note.kind.label,
                  style: TextStyle(
                    color: _tone,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (note.movedStatus) ...[
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      note.statusFrom == null
                          ? '→ ${note.statusTo}'
                          : '${note.statusFrom} → ${note.statusTo}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: plannerMuted,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
                const Spacer(),
                if (author != null) ...[
                  UserAvatar(profile: author, size: 20, showTooltip: false),
                  const SizedBox(width: 6),
                ],
                Text(
                  _stamp(note.createdAt),
                  style: const TextStyle(color: plannerFaint, fontSize: 10.5),
                ),
                if (isMine)
                  _TinyAction(
                    icon: Icons.delete_outline_rounded,
                    tooltip: 'Delete note',
                    onPressed: onDelete,
                  ),
              ],
            ),
          ),
          if (note.body.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              child: SelectableText(
                note.body.trim(),
                style: const TextStyle(
                  color: plannerText,
                  fontSize: 12.5,
                  height: 1.45,
                ),
              ),
            ),
          if (note.attachments.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              child: Wrap(
                spacing: 7,
                runSpacing: 7,
                children: [
                  for (final file in note.attachments)
                    _AttachmentChip(
                      attachment: file,
                      repository: repository,
                    ),
                ],
              ),
            ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  static String _stamp(DateTime at) {
    final local = at.toLocal();
    final diff = DateTime.now().difference(local);
    if (diff.inMinutes < 1) {
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
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${local.day} ${months[local.month - 1]}';
  }
}

/// One attached file, opened on tap through a signed URL.
class _AttachmentChip extends StatefulWidget {
  const _AttachmentChip({required this.attachment, required this.repository});

  final NoteAttachment attachment;
  final PlannerRepository repository;

  @override
  State<_AttachmentChip> createState() => _AttachmentChipState();
}

class _AttachmentChipState extends State<_AttachmentChip> {
  bool _opening = false;

  Future<void> _open() async {
    if (_opening) {
      return;
    }
    setState(() => _opening = true);
    try {
      final url = await widget.repository.attachmentUrl(widget.attachment);
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(content: Text('Could not open that file.')),
          );
      }
    } finally {
      if (mounted) {
        setState(() => _opening = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final file = widget.attachment;

    return Tooltip(
      message: '${file.fileName} · ${file.readableSize}',
      child: Material(
        color: plannerSurface,
        borderRadius: BorderRadius.circular(radiusSm),
        child: InkWell(
          borderRadius: BorderRadius.circular(radiusSm),
          onTap: _open,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(radiusSm),
              border: Border.all(color: plannerBorder),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_opening)
                  const SizedBox(
                    width: 13,
                    height: 13,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  Icon(
                    file.isImage
                        ? Icons.image_outlined
                        : Icons.description_outlined,
                    size: 14,
                    color: plannerMuted,
                  ),
                const SizedBox(width: 6),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 150),
                  child: Text(
                    file.fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: plannerText,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  file.readableSize,
                  style: const TextStyle(color: plannerFaint, fontSize: 10.5),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.pending,
    required this.saving,
    required this.canPost,
    required this.onAttach,
    required this.onRemoveAt,
    required this.onPost,
  });

  final TextEditingController controller;
  final List<NoteUpload> pending;
  final bool saving;
  final bool canPost;
  final VoidCallback onAttach;
  final ValueChanged<int> onRemoveAt;
  final VoidCallback onPost;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: const BoxDecoration(
        color: plannerCard,
        border: Border(top: BorderSide(color: plannerBorder)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (pending.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: Wrap(
                spacing: 7,
                runSpacing: 7,
                children: [
                  for (var i = 0; i < pending.length; i++)
                    _PendingChip(
                      upload: pending[i],
                      onRemove: () => onRemoveAt(i),
                    ),
                ],
              ),
            ),
          TextField(
            controller: controller,
            enabled: !saving,
            minLines: 2,
            maxLines: 5,
            maxLength: 5000,
            decoration: const InputDecoration(
              hintText: 'What was done? Attach a photo or file as proof.',
              counterText: '',
            ),
          ),
          const SizedBox(height: 9),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: saving ? null : onAttach,
                icon: const Icon(Icons.attach_file_rounded, size: 16),
                label: const Text('Attach'),
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: canPost && !saving ? onPost : null,
                icon: saving
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.add_rounded, size: 17),
                label: Text(saving ? 'Saving…' : 'Add note'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PendingChip extends StatelessWidget {
  const _PendingChip({required this.upload, required this.onRemove});

  final NoteUpload upload;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(9, 6, 5, 6),
      decoration: BoxDecoration(
        color: tint(plannerBlue, 0.07),
        borderRadius: BorderRadius.circular(radiusSm),
        border: Border.all(color: tint(plannerBlue, 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            upload.isImage
                ? Icons.image_outlined
                : Icons.description_outlined,
            size: 14,
            color: plannerBlue,
          ),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 140),
            child: Text(
              upload.fileName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: plannerInk,
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 5),
          Text(
            upload.readableSize,
            style: const TextStyle(color: plannerMuted, fontSize: 10.5),
          ),
          _TinyAction(
            icon: Icons.close_rounded,
            tooltip: 'Remove',
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}

class _TinyAction extends StatelessWidget {
  const _TinyAction({
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
        onTap: onPressed,
        borderRadius: BorderRadius.circular(radiusSm),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(icon, size: 14, color: plannerMuted),
        ),
      ),
    );
  }
}

class _NotesEmpty extends StatelessWidget {
  const _NotesEmpty();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 40, vertical: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.fact_check_outlined, size: 28, color: plannerFaint),
            SizedBox(height: 12),
            Text(
              'No work notes yet',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: plannerText,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: 5),
            Text(
              'Notes record what was actually done, with photos or files as '
              'proof. Submitting or sending back work adds one automatically.',
              textAlign: TextAlign.center,
              style: TextStyle(color: plannerMuted, fontSize: 12, height: 1.45),
            ),
          ],
        ),
      ),
    );
  }
}
