import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/supabase/planner_repository.dart';
import '../../shared/utils/planner_colors.dart';
import '../../shared/widgets/app_dialog.dart';

/// Joins a workspace by code. Returns the workspace name on success, null if
/// the user backed out.
Future<String?> showJoinWorkspaceDialog({
  required BuildContext context,
  required PlannerRepository repository,
}) {
  return showDialog<String>(
    context: context,
    builder: (context) => _JoinWorkspaceDialog(repository: repository),
  );
}

class _JoinWorkspaceDialog extends StatefulWidget {
  const _JoinWorkspaceDialog({required this.repository});

  final PlannerRepository repository;

  @override
  State<_JoinWorkspaceDialog> createState() => _JoinWorkspaceDialogState();
}

class _JoinWorkspaceDialogState extends State<_JoinWorkspaceDialog> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode();

  bool _joining = false;
  String? _error;

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

  Future<void> _join() async {
    final code = _controller.text.trim();
    if (code.isEmpty) {
      setState(() => _error = 'Enter the code you were given.');
      return;
    }

    setState(() {
      _joining = true;
      _error = null;
    });

    try {
      final name = await widget.repository.joinWorkspaceWithCode(code);
      if (mounted) {
        Navigator.of(context).pop(name);
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          // The repository throws a ready-to-read message for the expected
          // cases, so this does not need further translation.
          _error = error is String ? error : error.toString();
          _joining = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      icon: Icons.login_rounded,
      title: 'Join a workspace',
      message:
          'Ask someone in the workspace for its join code — an owner or admin '
          'can find it under Members & invites.',
      width: 440,
      content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _controller,
              focusNode: _focus,
              autocorrect: false,
              enableSuggestions: false,
              textCapitalization: TextCapitalization.characters,
              // Uppercase as they type: the codes are printed uppercase, and
              // matching that avoids a "why isn't this working" moment even
              // though the server accepts either case.
              inputFormatters: [_UpperCaseFormatter()],
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.6,
              ),
              decoration: const InputDecoration(
                hintText: 'PLNR-XXXX-XXXX',
                hintStyle: TextStyle(
                  color: plannerFaint,
                  fontSize: 17,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 1.6,
                ),
              ),
              onSubmitted: (_) => _joining ? null : _join(),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.error_outline_rounded,
                    size: 15,
                    color: plannerRed,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _error!,
                      style: const TextStyle(
                        color: plannerRed,
                        fontSize: 12.5,
                        height: 1.45,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      actions: [
        TextButton(
          onPressed: _joining ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _joining ? null : _join,
          child: _joining
              ? const SizedBox(
                  width: 15,
                  height: 15,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Join workspace'),
        ),
      ],
    );
  }
}

/// Uppercases input as it is typed, preserving the cursor position.
class _UpperCaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return newValue.copyWith(text: newValue.text.toUpperCase());
  }
}

/// The join code panel shown to owners and admins in the members dialog.
class JoinCodeCard extends StatelessWidget {
  const JoinCodeCard({
    super.key,
    required this.code,
    required this.canManage,
    required this.onRegenerate,
  });

  final String code;
  final bool canManage;
  final VoidCallback onRegenerate;

  @override
  Widget build(BuildContext context) {
    if (code.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      decoration: BoxDecoration(
        color: plannerSurface,
        borderRadius: BorderRadius.circular(radiusMd),
        border: Border.all(color: plannerBorder),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'JOIN CODE',
                  style: TextStyle(
                    color: plannerFaint,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 3),
                SelectableText(
                  code,
                  style: const TextStyle(
                    color: plannerInk,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.4,
                  ),
                ),
                const SizedBox(height: 3),
                const Text(
                  'Anyone with this code can join as a member.',
                  style: TextStyle(color: plannerMuted, fontSize: 11.5),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Copy code',
            icon: const Icon(Icons.copy_rounded, size: 16),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: code));
              ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(
                  const SnackBar(content: Text('Join code copied')),
                );
            },
          ),
          if (canManage)
            IconButton(
              tooltip: 'Generate a new code',
              icon: const Icon(Icons.refresh_rounded, size: 16),
              onPressed: onRegenerate,
            ),
        ],
      ),
    );
  }
}
