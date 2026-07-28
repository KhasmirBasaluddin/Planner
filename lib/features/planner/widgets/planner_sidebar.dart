import 'package:flutter/material.dart';

import '../../../models/planner_models.dart';
import '../../../shared/utils/planner_colors.dart';

class PlannerSidebar extends StatelessWidget {
  const PlannerSidebar({
    super.key,
    required this.boards,
    required this.selectedBoardIndex,
    required this.compact,
    required this.view,
    required this.noteCount,
    required this.onBoardSelected,
    required this.onNotesSelected,
    required this.onCreateBoard,
    required this.onRenameBoard,
    required this.onDeleteBoard,
  });

  final List<Board> boards;
  final int selectedBoardIndex;
  final bool compact;
  final WorkspaceView view;
  final int noteCount;
  final ValueChanged<int> onBoardSelected;
  final VoidCallback onNotesSelected;
  final VoidCallback onCreateBoard;
  final ValueChanged<Board> onRenameBoard;
  final ValueChanged<Board> onDeleteBoard;

  @override
  Widget build(BuildContext context) {
    final width = compact ? 88.0 : 280.0;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      width: width,
      color: plannerSidebar,
      padding: const EdgeInsets.fromLTRB(18, 22, 18, 20),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Brand(compact: compact),
            const SizedBox(height: 28),
            if (!compact)
              const Padding(
                padding: EdgeInsets.only(left: 12),
                child: Text(
                  'Workspaces',
                  style: TextStyle(
                    color: Color(0xFF9EA4C4),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
            if (!compact) const SizedBox(height: 10),
            Expanded(
              child: ListView.separated(
                itemCount: boards.length,
                separatorBuilder: (context, index) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final board = boards[index];
                  return _BoardNavItem(
                    board: board,
                    selected:
                        view == WorkspaceView.board &&
                        selectedBoardIndex == index,
                    compact: compact,
                    onTap: () => onBoardSelected(index),
                    onRename: () => onRenameBoard(board),
                    onDelete: () => onDeleteBoard(board),
                  );
                },
              ),
            ),
            // Notes sit below the board list, separated as a distinct
            // destination rather than another workspace.
            Divider(
              color: Colors.white.withValues(alpha: 0.1),
              height: 24,
            ),
            _NotesNavItem(
              selected: view == WorkspaceView.notes,
              compact: compact,
              noteCount: noteCount,
              onTap: onNotesSelected,
            ),
            const SizedBox(height: 12),
            _CreateBoardButton(compact: compact, onPressed: onCreateBoard),
          ],
        ),
      ),
    );
  }
}

class _NotesNavItem extends StatelessWidget {
  const _NotesNavItem({
    required this.selected,
    required this.compact,
    required this.noteCount,
    required this.onTap,
  });

  final bool selected;
  final bool compact;
  final int noteCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: compact ? 'Notes' : '',
      child: Material(
        color: selected
            ? Colors.white.withValues(alpha: 0.12)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Container(
            height: 44,
            padding: EdgeInsets.symmetric(horizontal: compact ? 0 : 12),
            child: Row(
              mainAxisAlignment: compact
                  ? MainAxisAlignment.center
                  : MainAxisAlignment.start,
              children: [
                Icon(
                  selected
                      ? Icons.sticky_note_2_rounded
                      : Icons.sticky_note_2_outlined,
                  size: 17,
                  color: selected ? noteYellow : const Color(0xFF9EA4C4),
                ),
                if (!compact) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Notes',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: selected
                            ? Colors.white
                            : Colors.white.withValues(alpha: 0.85),
                        fontSize: 13,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w500,
                      ),
                    ),
                  ),
                  if (noteCount > 0)
                    Text(
                      '$noteCount',
                      style: const TextStyle(
                        color: Color(0xFF9EA4C4),
                        fontSize: 12,
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.asset(
            'assets/images/planner.png',
            width: 36,
            height: 36,
            fit: BoxFit.cover,
          ),
        ),
        if (!compact) ...[
          const SizedBox(width: 10),
          const Text(
            'Planner',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.2,
            ),
          ),
        ],
      ],
    );
  }
}

class _BoardNavItem extends StatelessWidget {
  const _BoardNavItem({
    required this.board,
    required this.selected,
    required this.compact,
    required this.onTap,
    required this.onRename,
    required this.onDelete,
  });

  final Board board;
  final bool selected;
  final bool compact;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: compact ? board.name : '',
      child: Material(
        color: selected
            ? Colors.white.withValues(alpha: 0.12)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Container(
            height: 44,
            padding: EdgeInsets.symmetric(horizontal: compact ? 0 : 12),
            child: Row(
              mainAxisAlignment: compact
                  ? MainAxisAlignment.center
                  : MainAxisAlignment.start,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: board.color,
                    shape: BoxShape.circle,
                  ),
                ),
                if (!compact) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      board.name,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: selected
                            ? Colors.white
                            : Colors.white.withValues(alpha: 0.85),
                        fontSize: 13,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w500,
                      ),
                    ),
                  ),
                  Text(
                    '${board.taskCount}',
                    style: const TextStyle(
                      color: Color(0xFF9EA4C4),
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(width: 4),
                  _BoardRowMenu(onRename: onRename, onDelete: onDelete),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CreateBoardButton extends StatelessWidget {
  const _CreateBoardButton({required this.compact, required this.onPressed});

  final bool compact;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: compact ? 'New board' : '',
      child: SizedBox(
        width: double.infinity,
        height: 44,
        child: OutlinedButton.icon(
          onPressed: onPressed,
          icon: const Icon(Icons.add_rounded, size: 18),
          label: compact ? const SizedBox.shrink() : const Text('New board'),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            side: BorderSide(color: Colors.white.withValues(alpha: 0.18)),
            padding: EdgeInsets.zero,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ),
    );
  }
}

class _BoardRowMenu extends StatelessWidget {
  const _BoardRowMenu({required this.onRename, required this.onDelete});

  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_SidebarBoardAction>(
      tooltip: 'Board actions',
      offset: const Offset(0, 32),
      color: Colors.white,
      surfaceTintColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onSelected: (action) {
        switch (action) {
          case _SidebarBoardAction.rename:
            onRename();
            break;
          case _SidebarBoardAction.delete:
            onDelete();
            break;
        }
      },
      itemBuilder: (context) => const [
        PopupMenuItem(
          value: _SidebarBoardAction.rename,
          child: _SidebarMenuLabel(
            icon: Icons.edit_outlined,
            label: 'Edit board',
          ),
        ),
        PopupMenuItem(
          value: _SidebarBoardAction.delete,
          child: _SidebarMenuLabel(
            icon: Icons.delete_outline_rounded,
            label: 'Delete board',
            danger: true,
          ),
        ),
      ],
      child: const SizedBox(
        width: 28,
        height: 28,
        child: Icon(
          Icons.more_horiz_rounded,
          color: Color(0xFF9EA4C4),
          size: 18,
        ),
      ),
    );
  }
}

enum _SidebarBoardAction { rename, delete }

class _SidebarMenuLabel extends StatelessWidget {
  const _SidebarMenuLabel({
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

