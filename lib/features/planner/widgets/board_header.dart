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
    required this.searchController,
    required this.query,
    required this.onSearchChanged,
    required this.onAddTask,
    required this.onAddGroup,
    required this.onRenameBoard,
    required this.onDeleteBoard,
  });

  final Board board;
  final List<WorkspaceMember> members;
  final bool readOnly;
  final TextEditingController searchController;
  final String query;
  final ValueChanged<String> onSearchChanged;
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

    return Container(
      padding: const EdgeInsets.fromLTRB(28, 26, 28, 0),
      decoration: const BoxDecoration(
        color: plannerCard,
        border: Border(bottom: BorderSide(color: plannerBorder)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 900;
          // Below this the right-hand controls crowd the title out entirely, so
          // search collapses to an icon-width field and avatars drop away.
          final tight = constraints.maxWidth < 700;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title and its stats on the left, controls pinned right. The
              // Spacer used to sit before the controls with nothing after them,
              // which left the search and buttons stranded mid-row.
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: board.color,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 10),
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
                        const SizedBox(height: 10),
                        // Sits under the title rather than on its own full-width
                        // line, so the stats read as belonging to the board name.
                        //
                        // Scrolls rather than overflows: the progress bar has a
                        // fixed width and the status counts grow with the number
                        // of statuses in play, so on a narrow window the row can
                        // exceed whatever the controls on the right leave behind.
                        Padding(
                          padding: const EdgeInsets.only(left: 20),
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            physics: const ClampingScrollPhysics(),
                            child: Row(
                              children: [
                                _ProgressSummary(
                                  done: done,
                                  total: total,
                                  ratio: ratio,
                                ),
                                if (!narrow) ...[
                                  const SizedBox(width: 18),
                                  _StatusBreakdown(board: board),
                                ],
                              ],
                            ),
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
                  SizedBox(
                    width: tight ? 140 : (narrow ? 180 : 230),
                    child: _SearchField(
                      controller: searchController,
                      query: query,
                      onChanged: onSearchChanged,
                    ),
                  ),
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
              const SizedBox(height: 20),
            ],
          );
        },
      ),
    );
  }
}

/// Completion as a single bar plus a count — more legible at a glance than
/// three separate metric tiles.
class _ProgressSummary extends StatelessWidget {
  const _ProgressSummary({
    required this.done,
    required this.total,
    required this.ratio,
  });

  final int done;
  final int total;
  final double ratio;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 108,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(radiusXs),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 6,
              backgroundColor: plannerDivider,
              valueColor: AlwaysStoppedAnimation(
                ratio >= 1 ? plannerGreen : plannerBlue,
              ),
            ),
          ),
        ),
        const SizedBox(width: 9),
        Text(
          total == 0 ? 'No tasks' : '$done of $total done',
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

/// Small colored counts per status, so the board's health is visible without
/// scanning rows.
class _StatusBreakdown extends StatelessWidget {
  const _StatusBreakdown({required this.board});

  final Board board;

  @override
  Widget build(BuildContext context) {
    final counts = <TaskStatus, int>{};
    for (final group in board.groups) {
      for (final task in group.tasks) {
        counts[task.status] = (counts[task.status] ?? 0) + 1;
      }
    }
    if (counts.isEmpty) {
      return const SizedBox.shrink();
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final status in TaskStatus.values)
          if ((counts[status] ?? 0) > 0)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: statusColor(status),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    '${counts[status]} ${status.label.toLowerCase()}',
                    style: const TextStyle(
                      color: plannerMuted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
      ],
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

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.query,
    required this.onChanged,
  });

  final TextEditingController controller;
  final String query;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        style: const TextStyle(color: plannerInk, fontSize: 13),
        decoration: InputDecoration(
          fillColor: plannerSurface,
          contentPadding: const EdgeInsets.symmetric(vertical: 8),
          prefixIcon: const Icon(
            Icons.search_rounded,
            size: 17,
            color: plannerFaint,
          ),
          prefixIconConstraints: const BoxConstraints(
            minWidth: 34,
            minHeight: 34,
          ),
          suffixIcon: query.isEmpty
              ? null
              : IconButton(
                  onPressed: () {
                    controller.clear();
                    onChanged('');
                  },
                  icon: const Icon(
                    Icons.close_rounded,
                    size: 15,
                    color: plannerFaint,
                  ),
                ),
          hintText: 'Search tasks',
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
