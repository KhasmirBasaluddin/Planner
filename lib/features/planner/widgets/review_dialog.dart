import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../models/planner_models.dart';
import '../../../shared/utils/planner_colors.dart';
import '../../../shared/widgets/app_dialog.dart';
import '../../../shared/widgets/user_avatar.dart';

/// What came back from [showReviewDialog]: the note to write, the files to
/// attach, and — when sending work back — who should pick it up next.
typedef ReviewDecision = ({
  String body,
  List<NoteUpload> uploads,
  List<String>? reassignTo,
  StatusLabel? target,
});

/// Asked when work is submitted or sent back.
///
/// Both directions of the review loop go through one dialog because they are
/// the same act from opposite sides: someone is saying "here is where this
/// stands, and here is why". The differences — the wording, the tone, whether
/// a status can be chosen, whether reassignment is offered — are all data.
///
/// The note is optional. Forcing text here only harvests "." as the reason,
/// and a submission with a photo attached and no words is perfectly clear.
///
/// Returns null when the whole move was cancelled, so a mis-drag costs
/// nothing.
Future<ReviewDecision?> showReviewDialog({
  required BuildContext context,
  required PlannerTask task,
  required ReviewKind kind,
  required StatusLabel? from,
  required StatusLabel to,

  /// Statuses the reviewer may send the work back to — every non-done label on
  /// the board. Empty when the dialog is not offering a choice.
  List<StatusLabel> targets = const [],

  /// Who could take it on. Empty hides the reassignment row entirely.
  List<WorkspaceMember> members = const [],
  List<String> currentAssignees = const [],
}) {
  return showDialog<ReviewDecision>(
    context: context,
    builder: (context) => _ReviewDialog(
      task: task,
      kind: kind,
      from: from,
      to: to,
      targets: targets,
      members: members,
      currentAssignees: currentAssignees,
    ),
  );
}

/// Which side of the review this dialog is serving.
enum ReviewKind {
  /// The assignee marking their own work finished.
  submit,

  /// A reviewer pulling finished work back for more work.
  sendBack,
}

class _ReviewDialog extends StatefulWidget {
  const _ReviewDialog({
    required this.task,
    required this.kind,
    required this.from,
    required this.to,
    required this.targets,
    required this.members,
    required this.currentAssignees,
  });

  final PlannerTask task;
  final ReviewKind kind;
  final StatusLabel? from;
  final StatusLabel to;
  final List<StatusLabel> targets;
  final List<WorkspaceMember> members;
  final List<String> currentAssignees;

  @override
  State<_ReviewDialog> createState() => _ReviewDialogState();
}

class _ReviewDialogState extends State<_ReviewDialog> {
  final TextEditingController _body = TextEditingController();
  final FocusNode _focus = FocusNode();
  final List<NoteUpload> _uploads = [];

  late StatusLabel _target = widget.to;

  /// Null until the reviewer actually changes it, so "left alone" and
  /// "deliberately set to the same people" stay distinguishable — only a real
  /// change writes an assignment.
  List<String>? _reassignTo;

  String? _warning;

  bool get _isSendBack => widget.kind == ReviewKind.sendBack;

  @override
  void initState() {
    super.initState();
    _focus.requestFocus();
  }

  @override
  void dispose() {
    _body.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _attach() async {
    final result = await FilePicker.pickFiles(
      dialogTitle: 'Attach to this note',
      allowMultiple: true,
      withData: true,
      lockParentWindow: true,
    );
    if (result == null) {
      return;
    }

    const limit = 25 * 1024 * 1024;
    final rejected = <String>[];
    for (final file in result.files) {
      final bytes = file.bytes;
      if (bytes == null) {
        continue;
      }
      if (bytes.length > limit) {
        rejected.add(file.name);
        continue;
      }
      _uploads.add(
        NoteUpload(
          fileName: file.name,
          bytes: bytes,
          contentType: contentTypeForFile(file.name),
        ),
      );
    }

    if (mounted) {
      setState(() {
        _warning = rejected.isEmpty
            ? null
            : '${rejected.join(', ')} — larger than 25 MB, not attached.';
      });
    }
  }

  void _confirm() {
    Navigator.of(context).pop((
      body: _body.text.trim(),
      uploads: List<NoteUpload>.of(_uploads),
      reassignTo: _reassignTo,
      target: _target,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final tone = _isSendBack ? plannerYellow : plannerGreen;

    return AppDialog(
      icon: _isSendBack ? Icons.replay_rounded : Icons.outbox_rounded,
      tone: tone,
      width: 480,
      title: _isSendBack
          ? 'Send "${widget.task.title}" back?'
          : 'Submit "${widget.task.title}"',
      message: _isSendBack
          ? 'Say what still needs work. It is recorded in the task\'s work '
                'log with anything you attach, so whoever picks it up sees '
                'exactly why it came back.'
          : 'Record what you did, and attach photos or files as proof. This '
                'goes in the task\'s work log for whoever reviews it.',
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Any non-done status is a valid destination — sending something
          // back as Stuck says more than sending it back as Working.
          if (_isSendBack && widget.targets.length > 1) ...[
            const DialogFieldLabel('Move it to'),
            const SizedBox(height: 6),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                for (final status in widget.targets)
                  _StatusChip(
                    status: status,
                    selected: status.id == _target.id,
                    onTap: () => setState(() => _target = status),
                  ),
              ],
            ),
            const SizedBox(height: 16),
          ],

          DialogFieldLabel(
            _isSendBack ? 'What needs to change? (optional)' : 'What did you '
                'do? (optional)',
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _body,
            focusNode: _focus,
            minLines: 3,
            maxLines: 6,
            maxLength: 5000,
            textInputAction: TextInputAction.newline,
            decoration: InputDecoration(
              hintText: _isSendBack
                  ? 'The lighting is off in the second shot…'
                  : 'Reshot the outfit against the grey backdrop…',
              counterText: '',
            ),
            style: const TextStyle(fontSize: 13, height: 1.4),
          ),

          if (_uploads.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                for (var i = 0; i < _uploads.length; i++)
                  _UploadChip(
                    upload: _uploads[i],
                    onRemove: () => setState(() => _uploads.removeAt(i)),
                  ),
              ],
            ),
          ],

          if (_warning != null) ...[
            const SizedBox(height: 10),
            Text(
              _warning!,
              style: const TextStyle(color: plannerRed, fontSize: 11.5),
            ),
          ],

          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _attach,
              icon: const Icon(Icons.attach_file_rounded, size: 16),
              label: const Text('Attach photo or file'),
            ),
          ),

          // Most rejections mean "fix this yourself", so the current assignee
          // is kept unless the reviewer says otherwise.
          if (_isSendBack && widget.members.isNotEmpty) ...[
            const SizedBox(height: 18),
            const Divider(height: 1, color: plannerBorder),
            const SizedBox(height: 14),
            _Reassign(
              members: widget.members,
              current: _reassignTo ?? widget.currentAssignees,
              changed: _reassignTo != null,
              onChanged: (ids) => setState(() => _reassignTo = ids),
              onReset: () => setState(() => _reassignTo = null),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _confirm,
          child: Text(_isSendBack ? 'Send back' : 'Submit work'),
        ),
      ],
    );
  }
}

/// Optional reassignment, shown only when sending work back.
class _Reassign extends StatelessWidget {
  const _Reassign({
    required this.members,
    required this.current,
    required this.changed,
    required this.onChanged,
    required this.onReset,
  });

  final List<WorkspaceMember> members;
  final List<String> current;
  final bool changed;
  final ValueChanged<List<String>> onChanged;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            const Expanded(child: DialogFieldLabel('Who picks it up')),
            if (changed)
              TextButton(
                onPressed: onReset,
                child: const Text('Keep as it was'),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          changed
              ? 'The task will be reassigned when it goes back.'
              : 'Staying with whoever has it now. Tap someone to change that.',
          style: const TextStyle(
            color: plannerMuted,
            fontSize: 11.5,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 9),
        Wrap(
          spacing: 7,
          runSpacing: 7,
          children: [
            for (final member in members)
              _MemberChip(
                member: member,
                selected: current.contains(member.profile.id),
                onTap: () {
                  final next = List<String>.of(current);
                  if (next.contains(member.profile.id)) {
                    next.remove(member.profile.id);
                  } else {
                    next.add(member.profile.id);
                  }
                  onChanged(next);
                },
              ),
          ],
        ),
      ],
    );
  }
}

class _MemberChip extends StatelessWidget {
  const _MemberChip({
    required this.member,
    required this.selected,
    required this.onTap,
  });

  final WorkspaceMember member;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? tint(plannerBlue, 0.12) : plannerSurface,
      borderRadius: BorderRadius.circular(99),
      child: InkWell(
        borderRadius: BorderRadius.circular(99),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(4, 4, 11, 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(99),
            border: Border.all(
              color: selected ? tint(plannerBlue, 0.45) : plannerBorder,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              UserAvatar(
                profile: member.profile,
                size: 22,
                showTooltip: false,
              ),
              const SizedBox(width: 7),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 130),
                child: Text(
                  member.profile.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected ? plannerBlue : plannerText,
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
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

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.status,
    required this.selected,
    required this.onTap,
  });

  final StatusLabel status;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? tint(status.color, 0.16) : plannerSurface,
      borderRadius: BorderRadius.circular(99),
      child: InkWell(
        borderRadius: BorderRadius.circular(99),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(99),
            border: Border.all(
              color: selected ? status.color : plannerBorder,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: status.color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 7),
              Text(
                status.name,
                style: TextStyle(
                  color: selected ? plannerInk : plannerText,
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UploadChip extends StatelessWidget {
  const _UploadChip({required this.upload, required this.onRemove});

  final NoteUpload upload;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(9, 6, 4, 6),
      decoration: BoxDecoration(
        color: tint(plannerBlue, 0.07),
        borderRadius: BorderRadius.circular(radiusSm),
        border: Border.all(color: tint(plannerBlue, 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            upload.isImage ? Icons.image_outlined : Icons.description_outlined,
            size: 14,
            color: plannerBlue,
          ),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 150),
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
          IconButton(
            tooltip: 'Remove',
            iconSize: 14,
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
            icon: const Icon(Icons.close_rounded, color: plannerMuted),
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}

/// Guessed from the extension — the picker does not report a MIME type on
/// every platform, and this only decides whether a viewer previews the file
/// inline or hands it to the system.
String contentTypeForFile(String name) {
  final ext = name.toLowerCase().split('.').last;
  return switch (ext) {
    'png' => 'image/png',
    'jpg' || 'jpeg' => 'image/jpeg',
    'gif' => 'image/gif',
    'webp' => 'image/webp',
    'bmp' => 'image/bmp',
    'pdf' => 'application/pdf',
    'txt' => 'text/plain',
    'csv' => 'text/csv',
    'doc' || 'docx' => 'application/msword',
    'xls' || 'xlsx' => 'application/vnd.ms-excel',
    'zip' => 'application/zip',
    _ => 'application/octet-stream',
  };
}
