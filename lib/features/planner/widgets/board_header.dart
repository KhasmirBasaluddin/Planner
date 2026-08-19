import 'package:flutter/material.dart';

import '../../../models/planner_models.dart';
import '../../../shared/utils/planner_colors.dart';
import '../../../shared/widgets/user_avatar.dart';

class BoardHeader extends StatelessWidget {
  const BoardHeader({
    super.key,
    required this.board,
    required this.members,
    required this.readOnly,
    required this.onAddTask,
    required this.onAddGroup,
    required this.onRenameBoard,
    required this.onDeleteBoard,
  });

  final Board board;
  final List<WorkspaceMember> members;
  final bool readOnly;
  final VoidCallback onAddTask;
  final VoidCallback onAddGroup;
  final VoidCallback onRenameBoard;
  final VoidCallback onDeleteBoard;

  @override
  Widget build(BuildContext context) {
    final total = board.taskCount;
    final done = board.doneCount;
    final ratio = total == 0 ? 0.0 : done / total;
    final canAddTask = board.groups.isNotEmpty && !readOnly;

    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 900;
        // Below this the right-hand controls crowd the title out entirely, so
        // search collapses to an icon-width field and avatars drop away.
        final tight = constraints.maxWidth < 700;
        // The frame breathes with the window instead of holding desktop
        // margins on a squeezed one.
        final hPad = tight ? 16.0 : 28.0;

        return Container(
          padding: EdgeInsets.fromLTRB(hPad, tight ? 14 : 20, hPad, 0),
          decoration: const BoxDecoration(
            color: plannerCard,
            border: Border(bottom: BorderSide(color: plannerBorder)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title and its stats on the left, controls pinned right. The
              // Spacer used to sit before the controls with nothing after them,
              // which left the search and buttons stranded mid-row.
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    // The board's colour tile anchors both lines, the way the
                    // workspace tile anchors the sidebar — a 10px dot beside a
                    // 20px title read as an afterthought. Dropped entirely once
                    // the window is tight and the title needs every pixel.
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        if (!tight) ...[
                          _BoardTile(board: board),
                          const SizedBox(width: 12),
                        ],
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      board.name,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: plannerInk,
                                        fontSize: 20,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: -0.45,
                                      ),
                                    ),
                                  ),
                                  if (readOnly) ...[
                                    const SizedBox(width: 9),
                                    const _ReadOnlyBadge(),
                                  ],
                                  if (!readOnly)
                                    _BoardActionsMenu(
                                      onRenameBoard: onRenameBoard,
                                      onDeleteBoard: onDeleteBoard,
                                    ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              // Sits under the title rather than on its own
                              // full-width line, so the stats read as belonging
                              // to the board name.
                              //
                              // Scrolls rather than overflows: the bar has a
                              // fixed width and the pills grow with the number
                              // of statuses in play, so on a narrow window the
                              // row can exceed whatever the controls on the
                              // right leave behind.
                              SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                physics: const ClampingScrollPhysics(),
                                child: Row(
                                  children: [
                                    _ProgressSummary(
                                      board: board,
                                      done: done,
                                      total: total,
                                      ratio: ratio,
                                    ),
                                    if (!narrow) ...[
                                      const SizedBox(width: 16),
                                      _StatusBreakdown(board: board),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 20),
                  if (!narrow && members.isNotEmpty) ...[
                    AvatarStack(
                      profiles: members.map((m) => m.profile).toList(),
                      size: 27,
                    ),
                    const SizedBox(width: 14),
                  ],
                  if (!readOnly) ...[
                    const SizedBox(width: 8),
                    // Icon-only once labels no longer fit: two labelled buttons
                    // plus a search field is more than a narrow window can hold.
                    if (tight)
                      OutlinedButton(
                        onPressed: onAddGroup,
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                        ),
                        child: const Tooltip(
                          message: 'New group',
                          child: Icon(Icons.add_rounded, size: 16),
                        ),
                      )
                    else
                      OutlinedButton.icon(
                        onPressed: onAddGroup,
                        icon: const Icon(Icons.add_rounded, size: 15),
                        label: const Text('Group'),
                      ),
                    const SizedBox(width: 8),
                    if (tight)
                      FilledButton(
                        onPressed: canAddTask ? onAddTask : null,
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                        ),
                        child: const Tooltip(
                          message: 'New task',
                          child: Icon(Icons.add_rounded, size: 17),
                        ),
                      )
                    else
                      FilledButton.icon(
                        onPressed: canAddTask ? onAddTask : null,
                        icon: const Icon(Icons.add_rounded, size: 15),
                        label: const Text('New task'),
                      ),
                  ],
                ],
              ),
              SizedBox(height: tight ? 14 : 18),
            ],
          ),
        );
      },
    );
  }
}

/// The board's colour as a tile with its initial — the same visual weight the
/// workspace gets in the sidebar, so the header has an anchor.
class _BoardTile extends StatelessWidget {
  const _BoardTile({required this.board});

  final Board board;

  @override
  Widget build(BuildContext context) {
    final initial = board.name.trim().isEmpty
        ? 'B'
        : board.name.trim().characters.first.toUpperCase();
    return Container(
      width: 36,
      height: 36,
      // Flat, like every other surface in the app — the earlier colored glow
      // read as a gradient and fought the paper-plain ground.
      decoration: BoxDecoration(
        color: board.color,
        borderRadius: BorderRadius.circular(radiusMd),
      ),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// Completion as a bar segmented by status colour — one glance says not just
/// how much is done but where the rest of the work is sitting.
class _ProgressSummary extends StatelessWidget {
  const _ProgressSummary({
    required this.board,
    required this.done,
    required this.total,
    required this.ratio,
  });

  final Board board;
  final int done;
  final int total;
  final double ratio;

  @override
  Widget build(BuildContext context) {
    final counts = <String, int>{};
    var unlabelled = 0;
    for (final group in board.groups) {
      for (final task in group.tasks) {
        final id = task.statusId;
        if (id == null || board.statusById(id) == null) {
          unlabelled += 1;
        } else {
          counts[id] = (counts[id] ?? 0) + 1;
        }
      }
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Tooltip(
          message: total == 0
              ? 'No tasks yet'
              : '${(ratio * 100).round()}% of this board is done',
          child: SizedBox(
            width: 132,
            height: 7,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(radiusXs),
              child: total == 0
                  ? const ColoredBox(color: plannerDivider)
                  // Stretch, or the childless ColoredBoxes collapse to zero
                  // height and the bar becomes 132px of invisible space —
                  // which left the stats "floating" mid-header.
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final status in board.statuses)
                          if ((counts[status.id] ?? 0) > 0)
                            Expanded(
                              flex: counts[status.id]!,
                              child: ColoredBox(color: statusColor(status)),
                            ),
                        if (unlabelled > 0)
                          Expanded(
                            flex: unlabelled,
                            child: const ColoredBox(color: plannerDivider),
                          ),
                      ],
                    ),
            ),
          ),
        ),
        const SizedBox(width: 9),
        Text(
          total == 0
              ? 'No tasks'
              : '${(ratio * 100).round()}% · $done of $total done',
          style: const TextStyle(
            color: plannerText,
            fontSize: 12.5,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

/// Per-status counts as tinted pills, with overdue leading in red when any
/// task has slipped — the header answers "how is this board doing" before a
/// single row is read.
class _StatusBreakdown extends StatelessWidget {
  const _StatusBreakdown({required this.board});

  final Board board;

  @override
  Widget build(BuildContext context) {
    final counts = <String, int>{};
    var overdue = 0;
    for (final group in board.groups) {
      for (final task in group.tasks) {
        final id = task.statusId;
        if (id != null) {
          counts[id] = (counts[id] ?? 0) + 1;
        }
        if (task.isOverdue(done: board.isDone(task))) {
          overdue += 1;
        }
      }
    }
    if (counts.isEmpty && overdue == 0) {
      return const SizedBox.shrink();
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (overdue > 0)
          _StatPill(
            color: plannerRed,
            label: '$overdue overdue',
            icon: Icons.error_outline_rounded,
          ),
        for (final status in board.statuses)
          if ((counts[status.id] ?? 0) > 0)
            _StatPill(
              color: statusColor(status),
              label: '${counts[status.id]} ${status.name.toLowerCase()}',
            ),
      ],
    );
  }
}

class _StatPill extends StatelessWidget {
  const _StatPill({required this.color, required this.label, this.icon});

  final Color color;
  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 7),
      child: Container(
        height: 21,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: tint(color, 0.10),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null)
              Icon(icon, size: 11, color: color)
            else
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                color: Color.lerp(color, plannerInk, 0.3),
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReadOnlyBadge extends StatelessWidget {
  const _ReadOnlyBadge();

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'You have view-only access to this workspace',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: plannerDivider,
          borderRadius: BorderRadius.circular(radiusXs),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.visibility_outlined, size: 12, color: plannerMuted),
            SizedBox(width: 5),
            Text(
              'View only',
              style: TextStyle(
                color: plannerMuted,
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

class _BoardActionsMenu extends StatelessWidget {
  const _BoardActionsMenu({
    required this.onRenameBoard,
    required this.onDeleteBoard,
  });

  final VoidCallback onRenameBoard;
  final VoidCallback onDeleteBoard;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_BoardAction>(
      tooltip: 'Board options',
      offset: const Offset(0, 30),
      constraints: const BoxConstraints(minWidth: 200, maxWidth: 260),
      onSelected: (action) {
        switch (action) {
          case _BoardAction.rename:
            onRenameBoard();
          case _BoardAction.delete:
            onDeleteBoard();
        }
      },
      itemBuilder: (context) => const [
        PopupMenuItem(
          value: _BoardAction.rename,
          height: 38,
          child: _MenuActionLabel(
            icon: Icons.edit_outlined,
            label: 'Edit board',
          ),
        ),
        PopupMenuItem(
          value: _BoardAction.delete,
          height: 38,
          child: _MenuActionLabel(
            icon: Icons.delete_outline_rounded,
            label: 'Delete board',
            danger: true,
          ),
        ),
      ],
      child: const SizedBox(
        width: 28,
        height: 28,
        child: Icon(Icons.more_horiz_rounded, color: plannerFaint, size: 18),
      ),
    );
  }
}

enum _BoardAction { rename, delete }

class _MenuActionLabel extends StatelessWidget {
  const _MenuActionLabel({
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
