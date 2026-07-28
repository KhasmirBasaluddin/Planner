import 'package:flutter/material.dart';

import '../utils/planner_colors.dart';

/// The shell every dialog in the app uses.
///
/// Material's `AlertDialog` gives a bare title and body, which makes a warning
/// look identical to a confirmation. This adds a tinted icon that carries the
/// tone before the text is read, a proper heading/subheading pair, and a footer
/// separated by a rule so the actions read as a distinct zone rather than text
/// floating under the message.
class AppDialog extends StatelessWidget {
  const AppDialog({
    super.key,
    required this.icon,
    required this.title,
    required this.actions,
    this.tone,
    this.message,
    this.content,
    this.width = 420,
  });

  final IconData icon;
  final String title;

  /// Supporting line under the heading. Optional when [content] speaks for
  /// itself.
  final String? message;

  /// Body below the message — form fields and the like.
  final Widget? content;

  /// Colours the icon and its background. Defaults to the brand blue; pass
  /// [plannerRed] for destructive actions, [plannerYellow] for warnings.
  final Color? tone;

  final List<Widget> actions;
  final double width;

  @override
  Widget build(BuildContext context) {
    final accent = tone ?? plannerBlue;

    // Cap the dialog against the window, not just its own content. Without a
    // ceiling here a tall body (the task form, say) pushes past the bottom of a
    // short window and Flutter reports a RenderFlex overflow.
    final viewport = MediaQuery.sizeOf(context);
    final maxHeight = viewport.height - 80;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: width,
          maxHeight: maxHeight < 260 ? viewport.height : maxHeight,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: tint(accent, 0.10),
                      borderRadius: BorderRadius.circular(radiusMd),
                    ),
                    child: Icon(icon, size: 19, color: accent),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            title,
                            style: const TextStyle(
                              color: plannerInk,
                              fontSize: 16.5,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.3,
                              height: 1.3,
                            ),
                          ),
                        ),
                        if (message != null) ...[
                          const SizedBox(height: 6),
                          Text(
                            message!,
                            style: const TextStyle(
                              color: plannerMuted,
                              fontSize: 13,
                              height: 1.55,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),

            if (content != null)
              // Flexible + scroll: the header and footer stay put while a long
              // body scrolls, rather than the whole dialog growing off-screen.
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                  child: content!,
                ),
              ),

            const SizedBox(height: 22),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  for (var i = 0; i < actions.length; i++) ...[
                    if (i > 0) const SizedBox(width: 8),
                    actions[i],
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Field label used inside dialogs.
class DialogFieldLabel extends StatelessWidget {
  const DialogFieldLabel(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        children: [
          Text(
            text,
            style: const TextStyle(
              color: plannerInk,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (trailing != null) ...[const Spacer(), trailing!],
        ],
      ),
    );
  }
}
