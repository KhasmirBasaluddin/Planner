import 'package:flutter/material.dart';

import '../../../models/planner_models.dart';
import '../../../shared/utils/planner_colors.dart';
import '../../../shared/widgets/app_dialog.dart';

/// The answer from [showSendBackDialog]: go ahead with the status change, and
/// the comment to post alongside it — empty when none was given.
typedef SendBackDecision = ({String comment});

/// Asked when a task leaves a done status for a working one.
///
/// Reopening finished work is a decision teammates will ask about later —
/// "why is this back in Working on it?" — so the mover gets a place to answer
/// before the question exists. The comment lands in the task's chat, where
/// the discussion already lives, marked with the status it was sent back to.
/// It stays optional: forcing text here would only harvest "." as the reason.
///
/// Returns null when the whole move was cancelled.
Future<SendBackDecision?> showSendBackDialog({
  required BuildContext context,
  required PlannerTask task,
  required StatusLabel from,
  required StatusLabel to,
}) {
  return showDialog<SendBackDecision>(
    context: context,
    builder: (context) => _SendBackDialog(task: task, from: from, to: to),
  );
}

class _SendBackDialog extends StatefulWidget {
  const _SendBackDialog({
    required this.task,
    required this.from,
    required this.to,
  });

  final PlannerTask task;
  final StatusLabel from;
  final StatusLabel to;

  @override
  State<_SendBackDialog> createState() => _SendBackDialogState();
}

class _SendBackDialogState extends State<_SendBackDialog> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.requestFocus();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _submit() {
    Navigator.of(context).pop((comment: _controller.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      icon: Icons.replay_rounded,
      tone: plannerYellow,
      title: 'Send back to ${widget.to.name}?',
      message:
          '"${widget.task.title}" is marked ${widget.from.name}. Tell the '
          'team what still needs work — the note is posted to the task\'s '
          'chat so whoever picks it up sees why it came back.',
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const DialogFieldLabel('Comment (optional)'),
          TextField(
            controller: _controller,
            focusNode: _focus,
            minLines: 2,
            maxLines: 4,
            maxLength: 500,
            textInputAction: TextInputAction.newline,
            decoration: const InputDecoration(
              hintText: 'What needs to change?',
              counterText: '',
            ),
            style: const TextStyle(fontSize: 13, height: 1.4),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Send back')),
      ],
    );
  }
}
