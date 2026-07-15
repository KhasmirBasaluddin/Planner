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
    final groupCount = board.groups.length;
    final summary =
        '$groupCount ${groupCount == 1 ? 'group' : 'groups'} · '
        '${board.taskCount} ${board.taskCount == 1 ? 'task' : 'tasks'}';

    return Container(
      padding: const EdgeInsets.fromLTRB(28, 20, 28, 16),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: plannerBorder)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 860;
          final metrics = Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              MetricTile(label: 'Tasks', value: '${board.taskCount}'),
              MetricTile(label: 'Done', value: '${board.doneCount}'),
              MetricTile(label: 'Complete', value: '$completion%'),
            ],
          );
          final search = SizedBox(
            width: narrow ? double.infinity : 280,
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
                                  fontSize: 22,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: -0.3,
                                ),
                              ),
                            ),
                            const SizedBox(width: 2),
                            _BoardActionsMenu(
                              onRenameBoard: onRenameBoard,
                              onDeleteBoard: onDeleteBoard,
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          summary,
                          style: const TextStyle(
                            color: plannerMuted,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  OutlinedButton.icon(
                    onPressed: onAddGroup,
                    icon: const Icon(Icons.add_rounded, size: 16),
                    label: const Text('New group'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: canAddTask ? onAddTask : null,
                    icon: const Icon(Icons.add_rounded, size: 16),
                    label: const Text('New task'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (narrow) ...[
                metrics,
                const SizedBox(height: 12),
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
  const MetricTile({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 104),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: plannerBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              color: plannerMuted,
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              color: plannerInk,
              fontSize: 17,
              fontWeight: FontWeight.w600,
            ),
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
      style: const TextStyle(color: plannerInk, fontSize: 13),
      decoration: InputDecoration(
        prefixIcon: const Icon(
          Icons.search_rounded,
          size: 18,
          color: plannerMuted,
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
                  size: 16,
                  color: plannerMuted,
                ),
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
      tooltip: 'Board options',
      offset: const Offset(0, 32),
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
        width: 30,
        height: 30,
        child: Icon(Icons.more_horiz_rounded, color: plannerMuted, size: 20),
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
