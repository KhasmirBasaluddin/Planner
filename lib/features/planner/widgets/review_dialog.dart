import 'package:flutter/material.dart';

import '../../../models/planner_models.dart';
import '../../../shared/utils/planner_colors.dart';
import '../../../shared/widgets/user_avatar.dart';

/// What came back from [showReviewDialog]: the note to write, the files to
/// attach, and — when sending work back — who should pick it up next.
typedef ReviewDecision = ({
  String body,
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
/// The note is optional. Forcing text here only harvests "." as the reason.
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

  late StatusLabel _target = widget.to;

  /// Null until the reviewer actually changes it, so "left alone" and
  /// "deliberately set to the same people" stay distinguishable — only a real
  /// change writes an assignment.
  List<String>? _reassignTo;

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

  void _confirm() {
    Navigator.of(context).pop((
      body: _body.text.trim(),
      reassignTo: _reassignTo,
      target: _target,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final tone = _isSendBack ? plannerOrange : plannerBlue;
    final viewport = MediaQuery.sizeOf(context);

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      backgroundColor: plannerCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusLg),
      ),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 540,
          maxHeight: viewport.height - 80,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(
              tone: tone,
              isSendBack: _isSendBack,
              task: widget.task,
              from: widget.from,
              to: _target,
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 18, 24, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Any non-done status is a valid destination — sending
                    // something back as Stuck says more than sending it back
                    // as Working.
                    if (_isSendBack && widget.targets.length > 1) ...[
                      const _Label('Move it to'),
                      const SizedBox(height: 8),
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
                      const SizedBox(height: 20),
                    ],

                    _Label(
                      _isSendBack
                          ? 'What still needs work?'
                          : 'What did you do?',
                      optional: true,
                    ),
                    const SizedBox(height: 8),
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
                      style: const TextStyle(fontSize: 13, height: 1.45),
                    ),

                    // Most rejections mean "fix this yourself", so the current
                    // assignee is kept unless the reviewer says otherwise.
                    if (_isSendBack && widget.members.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      const Divider(height: 1, color: plannerBorder),
                      const SizedBox(height: 16),
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
              ),
            ),
            const Divider(height: 1, color: plannerBorder),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
              child: Row(
                children: [
                  // The note is optional in both directions — forcing text
                  // only harvests "." as the reason, and a submission with a
                  // photo and no words is perfectly clear.
                  const Expanded(
                    child: Text(
                      'A note is optional.',
                      style: TextStyle(color: plannerFaint, fontSize: 11.5),
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 6),
                  FilledButton.icon(
                    onPressed: _confirm,
                    style: FilledButton.styleFrom(backgroundColor: tone),
                    icon: Icon(
                      _isSendBack
                          ? Icons.replay_rounded
                          : Icons.check_rounded,
                      size: 17,
                    ),
                    label: Text(_isSendBack ? 'Send back' : 'Submit work'),
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

/// The dialog's head: what is happening, to what, and where it lands.
///
/// The status move is drawn rather than described. "Done → Working on it" is
/// the whole decision, and a sentence buries it in prose.
class _Header extends StatelessWidget {
  const _Header({
    required this.tone,
    required this.isSendBack,
    required this.task,
    required this.from,
    required this.to,
  });

  final Color tone;
  final bool isSendBack;
  final PlannerTask task;
  final StatusLabel? from;
  final StatusLabel to;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 16, 18),
      decoration: BoxDecoration(
        color: tint(tone, 0.06),
        border: const Border(bottom: BorderSide(color: plannerBorder)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: tone,
                  borderRadius: BorderRadius.circular(radiusMd),
                ),
                alignment: Alignment.center,
                child: Icon(
                  isSendBack
                      ? Icons.replay_rounded
                      : Icons.outbox_rounded,
                  size: 19,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      isSendBack ? 'Send work back' : 'Submit work',
                      style: const TextStyle(
                        color: plannerInk,
                        fontSize: 16.5,
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      task.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: plannerMuted,
                        fontSize: 12.5,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Cancel',
                icon: const Icon(
                  Icons.close_rounded,
                  size: 19,
                  color: plannerMuted,
                ),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Wrap, not Row: the status names are the board's own and can be
          // any length, and a narrow window would otherwise overflow rather
          // than move the caption to its own line.
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (from != null) ...[
                _StatusDot(status: from!),
                const Icon(
                  Icons.arrow_forward_rounded,
                  size: 15,
                  color: plannerFaint,
                ),
              ],
              _StatusDot(status: to),
              Text(
                isSendBack
                    ? 'Recorded in the work log'
                    : 'Goes to whoever reviews it',
                style: const TextStyle(color: plannerFaint, fontSize: 11),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A status, as a coloured dot and its own name.
class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.status});

  final StatusLabel status;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: plannerCard,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: plannerBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: status.color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 160),
            child: Text(
              status.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: plannerText,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A field label, with the optional marker where one belongs.
class _Label extends StatelessWidget {
  const _Label(this.text, {this.optional = false});

  final String text;
  final bool optional;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          text,
          style: const TextStyle(
            color: plannerText,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (optional) ...[
          const SizedBox(width: 6),
          const Text(
            'optional',
            style: TextStyle(
              color: plannerFaint,
              fontSize: 11,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
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
            const Expanded(child: _Label('Who picks it up')),
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
