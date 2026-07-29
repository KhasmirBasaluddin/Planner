p = 'lib/features/planner/widgets/planner_dialogs.dart'
s = open(p, encoding='utf-8').read()

start = s.index('class _MessageBubble extends StatefulWidget {')
end = s.index('class _YouTag extends StatelessWidget {')

new = '''class _MessageBubble extends StatefulWidget {
  const _MessageBubble({
    required this.comment,
    required this.members,
    required this.currentUserId,
    required this.onEdit,
    required this.onDelete,
    required this.onReact,
    this.onReply,
    this.compact = false,
    this.grouped = false,
  });

  final TaskComment comment;
  final List<WorkspaceMember> members;
  final String currentUserId;
  final VoidCallback? onReply;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final ValueChanged<String> onReact;
  final bool compact;

  /// True when the message above is from the same person, close in time.
  /// Groups run without repeating the avatar and name.
  final bool grouped;

  @override
  State<_MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<_MessageBubble> {
  bool _hovered = false;

  bool get _isMine => widget.comment.author?.id == widget.currentUserId;

  bool get _mentionsMe =>
      widget.comment.mentionedIds.contains(widget.currentUserId);

  @override
  Widget build(BuildContext context) {
    final comment = widget.comment;
    final author = comment.author;

    // Your own messages sit right, everyone else left. It is the strongest
    // signal a chat has, and reading a column of identical rows to find the
    // name was doing that work instead.
    final alignment = _isMine
        ? CrossAxisAlignment.end
        : CrossAxisAlignment.start;

    return MouseRegion(
      onEnter: (_) => setHoverSafely(this, () => _hovered = true),
      onExit: (_) => setHoverSafely(this, () => _hovered = false),
      child: Padding(
        padding: EdgeInsets.only(top: widget.grouped ? 2 : 12),
        child: Column(
          crossAxisAlignment: alignment,
          mainAxisSize: MainAxisSize.min,
          children: [
            // The byline appears once per run, not once per message.
            if (!widget.grouped)
              Padding(
                padding: EdgeInsets.only(
                  left: _isMine ? 0 : 38,
                  right: _isMine ? 2 : 0,
                  bottom: 4,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!_isMine) ...[
                      Text(
                        author?.displayName ?? 'Someone',
                        style: const TextStyle(
                          color: plannerInk,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 6),
                    ],
                    Text(
                      comment.age,
                      style: const TextStyle(
                        color: plannerFaint,
                        fontSize: 10.5,
                      ),
                    ),
                    if (comment.wasEdited) ...[
                      const SizedBox(width: 5),
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
                // The avatar column holds its width even when grouped, so the
                // bubbles in a run stay aligned with each other.
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
                // Actions ride the outside edge of the bubble, out of the
                // text's way rather than competing with it for the byline.
                if (_isMine) _HoverActions(visible: _hovered, state: widget),
                Flexible(
                  child: _Bubble(
                    comment: comment,
                    members: widget.members,
                    currentUserId: widget.currentUserId,
                    isMine: _isMine,
                    mentionsMe: _mentionsMe,
                    onReact: widget.onReact,
                  ),
                ),
                if (!_isMine) _HoverActions(visible: _hovered, state: widget),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The message itself: text, and any reactions under it.
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
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: background,
            // The corner nearest the sender is squared off, which is what
            // makes a bubble point at whoever wrote it.
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
            // On a blue ground a blue mention disappears, so it inverts.
            mentionColor: isMine && !mentionsMe ? Colors.white : null,
          ),
        ),
        if (comment.reactions.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 5),
            child: _ReactionChips(
              reactions: comment.reactions,
              mine: comment.myReactions,
              onToggle: onReact,
            ),
          ),
      ],
    );
  }
}

/// The "..." button, faded until the message is hovered.
class _HoverActions extends StatelessWidget {
  const _HoverActions({required this.visible, required this.state});

  final bool visible;
  final _MessageBubble state;

  @override
  Widget build(BuildContext context) {
    final isMine = state.comment.author?.id == state.currentUserId;

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
            canReply: state.onReply != null,
            onReply: state.onReply,
            onEdit: state.onEdit,
            onDelete: state.onDelete,
            onReact: state.onReact,
          ),
        ),
      ),
    );
  }
}

/// Stands in for a deleted account.
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
      child: const Icon(
        Icons.person_outline,
        size: 13,
        color: plannerFaint,
      ),
    );
  }
}

'''

s = s[:start] + new + s[end:]

# _MessageBody now takes its colours from the bubble.
old_body = """class _MessageBody extends StatelessWidget {
  const _MessageBody({
    required this.body,
    required this.members,
    required this.currentUserId,
  });

  final String body;
  final List<WorkspaceMember> members;
  final String currentUserId;

  @override
  Widget build(BuildContext context) {
    return SelectableText.rich(
      TextSpan(
        style: const TextStyle(
          color: plannerText,
          fontSize: 13,
          height: 1.45,
        ),
        children: _spans(),
      ),
    );
  }"""

new_body = """class _MessageBody extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return SelectableText.rich(
      TextSpan(
        style: TextStyle(color: color, fontSize: 13, height: 1.45),
        children: _spans(),
      ),
    );
  }"""

assert old_body in s, 'message body not found'
s = s.replace(old_body, new_body)

s = s.replace("""          style: TextStyle(
            // @everyone includes you, so it gets the same colour as being
            // named directly.
            color: isMe ? plannerOrange : plannerBlue,
            fontWeight: FontWeight.w600,
          ),""",
"""          style: TextStyle(
            // @everyone includes you, so it gets the same colour as being
            // named directly.
            color: mentionColor ?? (isMe ? plannerOrange : plannerBlue),
            fontWeight: FontWeight.w600,
          ),""")

open(p, 'w', encoding='utf-8', newline='\n').write(s)
print('bubble rewritten:', 'class _Bubble extends StatelessWidget' in s)
print('grouping:', 'this.grouped = false' in s)
