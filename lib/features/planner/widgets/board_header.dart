import 'package:flutter/material.dart';

import '../../../models/planner_models.dart';
import '../../../shared/utils/planner_colors.dart';

class BoardHeader extends StatelessWidget {
  const BoardHeader({
    super.key,
    required this.board,
    required this.searchController,
    required this.query,
    required this.onSearchChanged,
    required this.onAddTask,
    required this.onAddGroup,
    required this.onRenameBoard,
    required this.onDeleteBoard,
  });

  final Board board;
  final TextEditingController searchController;
  final String query;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onAddTask;
  final VoidCallback onAddGroup;
  final VoidCallback onRenameBoard;
  final VoidCallback onDeleteBoard;

  @override
  Widget build(BuildContext context) {
    final completion = board.taskCount == 0
        ? 0
        : (board.doneCount / board.taskCount * 100).round();
    final canAddTask = board.groups.isNotEmpty;

    return Container(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 18),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: plannerBorder)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 860;
          final metrics = Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              MetricTile(
                icon: Icons.list_alt_rounded,
                label: 'Tasks',
                value: '${board.taskCount}',
                color: plannerBlue,
              ),
              MetricTile(
                icon: Icons.check_circle_rounded,
                label: 'Done',
                value: '${board.doneCount}',
                color: plannerGreen,
              ),
              MetricTile(
                icon: Icons.trending_up_rounded,
                label: 'Complete',
                value: '$completion%',
                color: plannerPurple,
              ),
            ],
          );
          final search = SizedBox(
            width: narrow ? double.infinity : 300,
            child: _SearchField(
              controller: searchController,
              query: query,
              onChanged: onSearchChanged,
            ),
          );

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                board.name,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: plannerInk,
                                  fontSize: 30,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            _BoardActionsMenu(
                              onRenameBoard: onRenameBoard,
                              onDeleteBoard: onDeleteBoard,
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'A private desktop workspace for projects, tasks, owners, dates, and progress.',
                          style: TextStyle(color: plannerMuted),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  OutlinedButton.icon(
                    onPressed: onAddGroup,
                    icon: const Icon(Icons.add_box_outlined),
                    label: const Text('New group'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: plannerText,
                      side: const BorderSide(color: plannerBorder),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 16,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  FilledButton.icon(
                    onPressed: canAddTask ? onAddTask : null,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('New task'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 16,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              if (narrow) ...[
                metrics,
                const SizedBox(height: 14),
                search,
              ] else
                Row(children: [metrics, const Spacer(), search]),
            ],
          );
        },
      ),
    );
  }
}

class MetricTile extends StatelessWidget {
  const MetricTile({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 150,
      height: 62,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: plannerBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 19),
          ),
          const SizedBox(width: 10),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: const TextStyle(
                  color: plannerInk,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                label,
                style: const TextStyle(color: plannerMuted, fontSize: 12),
              ),
            ],
          ),
        ],
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
    return TextField(
      controller: controller,
      onChanged: onChanged,
      decoration: InputDecoration(
        prefixIcon: const Icon(Icons.search_rounded, size: 20),
        suffixIcon: query.isEmpty
            ? null
            : IconButton(
                onPressed: () {
                  controller.clear();
                  onChanged('');
                },
                icon: const Icon(Icons.close_rounded, size: 18),
              ),
        hintText: 'Search tasks',
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
      tooltip: 'Board actions',
      offset: const Offset(0, 36),
      color: Colors.white,
      surfaceTintColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onSelected: (action) {
        switch (action) {
          case _BoardAction.rename:
            onRenameBoard();
            break;
          case _BoardAction.delete:
            onDeleteBoard();
            break;
        }
      },
      itemBuilder: (context) => const [
        PopupMenuItem(
          value: _BoardAction.rename,
          child: _MenuActionLabel(
            icon: Icons.edit_outlined,
            label: 'Rename board',
          ),
        ),
        PopupMenuItem(
          value: _BoardAction.delete,
          child: _MenuActionLabel(
            icon: Icons.delete_outline_rounded,
            label: 'Delete board',
            danger: true,
          ),
        ),
      ],
      child: const SizedBox(
        width: 34,
        height: 34,
        child: Icon(Icons.more_horiz_rounded, color: plannerText, size: 22),
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
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 10),
        Text(
          label,
          style: TextStyle(color: color, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}
