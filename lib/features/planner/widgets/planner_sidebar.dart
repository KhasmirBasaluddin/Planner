import 'package:flutter/material.dart';

import '../../../models/planner_models.dart';
import '../../../shared/utils/planner_colors.dart';

/// The left rail: workspace switcher at the top, boards in the middle, account
/// controls at the bottom. Collapses to icons on narrow windows.
class PlannerSidebar extends StatefulWidget {
  const PlannerSidebar({
    super.key,
    required this.workspaces,
    required this.selectedWorkspaceIndex,
    required this.boards,
    required this.selectedBoardIndex,
    required this.members,
    required this.loading,
    required this.compact,
    required this.onWorkspaceSelected,
    required this.onCreateWorkspace,
    required this.onJoinWorkspace,
    required this.onRenameWorkspace,
    required this.onManageMembers,
    required this.onLeaveWorkspace,
    required this.onDeleteWorkspace,
    required this.onSignOut,
    required this.onBoardSelected,
    required this.onCreateBoard,
    required this.onRenameBoard,
    required this.onDeleteBoard,
    required this.onPinBoard,
  });

  final List<Workspace> workspaces;
  final int selectedWorkspaceIndex;
  final List<Board> boards;
  final int selectedBoardIndex;
  final List<WorkspaceMember> members;

  /// True while boards are being fetched. Without this the list briefly shows
  /// "No boards yet", which reads as a wrong answer rather than a pending one.
  final bool loading;
  final bool compact;
  final ValueChanged<int> onWorkspaceSelected;
  final VoidCallback onCreateWorkspace;
  final VoidCallback onJoinWorkspace;
  final VoidCallback onRenameWorkspace;
  final VoidCallback onManageMembers;
  final VoidCallback onLeaveWorkspace;
  final VoidCallback onDeleteWorkspace;
  final VoidCallback onSignOut;
  final ValueChanged<int> onBoardSelected;
  final VoidCallback onCreateBoard;
  final ValueChanged<Board> onRenameBoard;
  final ValueChanged<Board> onDeleteBoard;
  final ValueChanged<Board> onPinBoard;

  @override
  State<PlannerSidebar> createState() => _PlannerSidebarState();
}

class _PlannerSidebarState extends State<PlannerSidebar> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Workspace> get workspaces => widget.workspaces;
  int get selectedWorkspaceIndex => widget.selectedWorkspaceIndex;
  List<Board> get boards => widget.boards;
  int get selectedBoardIndex => widget.selectedBoardIndex;
  List<WorkspaceMember> get members => widget.members;
  bool get loading => widget.loading;
  bool get compact => widget.compact;
  ValueChanged<int> get onWorkspaceSelected => widget.onWorkspaceSelected;
  VoidCallback get onCreateWorkspace => widget.onCreateWorkspace;
  VoidCallback get onJoinWorkspace => widget.onJoinWorkspace;
  VoidCallback get onRenameWorkspace => widget.onRenameWorkspace;
  VoidCallback get onManageMembers => widget.onManageMembers;
  VoidCallback get onLeaveWorkspace => widget.onLeaveWorkspace;
  VoidCallback get onDeleteWorkspace => widget.onDeleteWorkspace;
  VoidCallback get onSignOut => widget.onSignOut;
  ValueChanged<int> get onBoardSelected => widget.onBoardSelected;
  VoidCallback get onCreateBoard => widget.onCreateBoard;
  ValueChanged<Board> get onRenameBoard => widget.onRenameBoard;
  ValueChanged<Board> get onDeleteBoard => widget.onDeleteBoard;
  ValueChanged<Board> get onPinBoard => widget.onPinBoard;

  Workspace? get _workspace {
    if (workspaces.isEmpty) {
      return null;
    }
    return workspaces[selectedWorkspaceIndex.clamp(0, workspaces.length - 1)];
  }

  /// Boards matching the search, pinned ones first.
  ///
  /// Indexes are carried alongside, because selection is by position in the
  /// unfiltered list — reordering or filtering the display must not change
  /// which board a tap selects.
  List<({Board board, int index})> get _visibleBoards {
    final query = _query.trim().toLowerCase();
    final entries = <({Board board, int index})>[];
    for (var i = 0; i < boards.length; i++) {
      if (query.isEmpty || boards[i].name.toLowerCase().contains(query)) {
        entries.add((board: boards[i], index: i));
      }
    }
    // Stable: equally-pinned boards keep the order the server sent.
    entries.sort((a, b) {
      if (a.board.pinned == b.board.pinned) {
        return 0;
      }
      return a.board.pinned ? -1 : 1;
    });
    return entries;
  }

  /// Shown whenever there is more than one board to choose between.
  ///
  /// An earlier version hid it below six boards, on the theory that a short
  /// list is faster to scan than to type into. That reasoning was wrong in
  /// practice: a control that appears only past some invisible threshold reads
  /// as missing, and someone looking for it has no way to know why it is not
  /// there. The collapsed rail is the one real exception — there is no room.
  bool get _showSearch => !compact && boards.length > 1;

  @override
  Widget build(BuildContext context) {
    // ConstrainedBox as well as width: inside a Row the parent can hand down a
    // tighter maxWidth than the requested width, and the rail then renders
    // narrower than its contents expect. Pinning min and max keeps it honest.
    final railWidth = compact ? 76.0 : 268.0;

    return ConstrainedBox(
      constraints: BoxConstraints(minWidth: railWidth, maxWidth: railWidth),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 170),
        curve: Curves.easeOutCubic,
        width: railWidth,
        color: plannerSidebar,
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: compact
                    ? const EdgeInsets.fromLTRB(14, 18, 14, 14)
                    : const EdgeInsets.fromLTRB(16, 18, 16, 14),
                child: _WorkspaceSwitcher(
                  workspace: _workspace,
                  workspaces: workspaces,
                  selectedIndex: selectedWorkspaceIndex,
                  compact: compact,
                  memberCount: members.length,
                  onSelected: onWorkspaceSelected,
                  onCreate: onCreateWorkspace,
                  onJoin: onJoinWorkspace,
                  onRename: onRenameWorkspace,
                  onManageMembers: onManageMembers,
                  onLeave: onLeaveWorkspace,
                  onDelete: onDeleteWorkspace,
                ),
              ),
              Divider(color: Colors.white.withValues(alpha: 0.07), height: 1),
              // Until a workspace exists there is nowhere to put a board, so the
              // whole section is hidden rather than offering an action that
              // cannot succeed. The welcome screen in the content area is the
              // only thing to do at this point.
              if (workspaces.isEmpty)
                const Spacer()
              else ...[
                if (!compact)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 18, 16, 8),
                    child: Row(
                      children: [
                        const Text(
                          'BOARDS',
                          style: TextStyle(
                            color: Color(0xFF848AAE),
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.7,
                          ),
                        ),
                        const Spacer(),
                        _MiniIconButton(
                          icon: Icons.add_rounded,
                          tooltip: 'New board',
                          onPressed: onCreateBoard,
                        ),
                      ],
                    ),
                  )
                else
                  const SizedBox(height: 14),
                if (_showSearch)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: _BoardSearchField(
                      controller: _searchController,
                      onChanged: (value) => setState(() => _query = value),
                    ),
                  ),
                Expanded(
                  child: loading
                      ? const SizedBox.shrink()
                      : boards.isEmpty
                      ? _EmptyBoards(compact: compact, onCreate: onCreateBoard)
                      : Builder(
                          builder: (context) {
                            final visible = _visibleBoards;
                            if (visible.isEmpty) {
                              return const _NoBoardMatches();
                            }
                            return ListView.builder(
                              padding: EdgeInsets.symmetric(
                                horizontal: compact ? 14 : 12,
                              ),
                              itemCount: visible.length,
                              itemBuilder: (context, position) {
                                final entry = visible[position];
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 2),
                                  child: _BoardNavItem(
                                    board: entry.board,
                                    selected: selectedBoardIndex == entry.index,
                                    compact: compact,
                                    onTap: () => onBoardSelected(entry.index),
                                    onRename: () => onRenameBoard(entry.board),
                                    onDelete: () => onDeleteBoard(entry.board),
                                    onPin: () => onPinBoard(entry.board),
                                  ),
                                );
                              },
                            );
                          },
                        ),
                ),
                if (compact)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Center(
                      child: _MiniIconButton(
                        icon: Icons.add_rounded,
                        tooltip: 'New board',
                        onPressed: onCreateBoard,
                      ),
                    ),
                  ),
              ],
              // Pinned to the bottom of the rail: signing out is a top-level
              // action people expect to find here, not inside a menu.
              Divider(color: Colors.white.withValues(alpha: 0.07), height: 1),
              _SidebarSignOut(compact: compact, onPressed: onSignOut),
            ],
          ),
        ),
      ),
    );
  }
}

/// Workspace identity plus the menu for switching, inviting and creating.
class _WorkspaceSwitcher extends StatelessWidget {
  const _WorkspaceSwitcher({
    required this.workspace,
    required this.workspaces,
    required this.selectedIndex,
    required this.compact,
    required this.memberCount,
    required this.onSelected,
    required this.onCreate,
    required this.onJoin,
    required this.onRename,
    required this.onManageMembers,
    required this.onLeave,
    required this.onDelete,
  });

  final Workspace? workspace;
  final List<Workspace> workspaces;
  final int selectedIndex;
  final bool compact;
  final int memberCount;
  final ValueChanged<int> onSelected;
  final VoidCallback onCreate;
  final VoidCallback onJoin;
  final VoidCallback onRename;
  final VoidCallback onManageMembers;
  final VoidCallback onLeave;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final current = workspace;
    final initial = (current?.name.trim().isNotEmpty ?? false)
        ? current!.name.trim().characters.first.toUpperCase()
        : 'W';

    return PopupMenuButton<_WorkspaceAction>(
      tooltip: compact ? (current?.name ?? 'Workspace') : '',
      offset: const Offset(0, 46),
      // A fixed width, not just a minimum: in the collapsed sidebar the button
      // is 44px wide and the menu inherits that as its maximum, so every row
      // inside it overflowed.
      constraints: const BoxConstraints(minWidth: 260, maxWidth: 300),
      onSelected: (action) {
        switch (action) {
          case _WorkspaceSwitchAction():
            onSelected(action.index);
          case _WorkspaceMenuAction(kind: final kind):
            switch (kind) {
              case _MenuKind.create:
                onCreate();
              case _MenuKind.join:
                onJoin();
              case _MenuKind.rename:
                onRename();
              case _MenuKind.members:
                onManageMembers();
              case _MenuKind.leave:
                onLeave();
              case _MenuKind.delete:
                onDelete();
            }
        }
      },
      itemBuilder: (context) => [
        if (workspaces.length > 1) ...[
          const PopupMenuItem(
            enabled: false,
            height: 30,
            child: Text(
              'SWITCH WORKSPACE',
              style: TextStyle(
                color: plannerFaint,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
              ),
            ),
          ),
          for (var i = 0; i < workspaces.length; i++)
            PopupMenuItem(
              value: _WorkspaceSwitchAction(i),
              height: 40,
              child: Row(
                children: [
                  Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: workspaces[i].color,
                      borderRadius: BorderRadius.circular(radiusXs),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      workspaces[i].name.trim().isEmpty
                          ? 'W'
                          : workspaces[i].name
                                .trim()
                                .characters
                                .first
                                .toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      workspaces[i].name,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: i == selectedIndex
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                    ),
                  ),
                  if (i == selectedIndex)
                    const Icon(
                      Icons.check_rounded,
                      size: 15,
                      color: plannerBlue,
                    ),
                ],
              ),
            ),
          const PopupMenuDivider(),
        ],
        // Managing the workspace — its people, name and colour — is for owners
        // and admins. A member can edit every task in it and still have no
        // business renaming or deleting it, so those entries are absent rather
        // than shown-and-refused. The database enforces the same split, so a
        // member who reached them anyway would only get an error.
        if (workspace != null && workspace!.role.canManageMembers) ...[
          PopupMenuItem(
            value: const _WorkspaceMenuAction(_MenuKind.members),
            height: 40,
            child: _MenuRow(
              icon: Icons.group_add_outlined,
              label: 'Members & invites',
              trailing: '$memberCount',
            ),
          ),
          PopupMenuItem(
            value: const _WorkspaceMenuAction(_MenuKind.rename),
            height: 40,
            child: const _MenuRow(
              icon: Icons.edit_outlined,
              label: 'Workspace settings',
            ),
          ),
        ],
        // Everyone else gets the team roster, read-only. Seeing who you work
        // with is not a management action.
        if (workspace != null && !workspace!.role.canManageMembers)
          PopupMenuItem(
            value: const _WorkspaceMenuAction(_MenuKind.members),
            height: 40,
            child: _MenuRow(
              icon: Icons.group_outlined,
              label: 'View members',
              trailing: '$memberCount',
            ),
          ),
        // Leaving and deleting are mutually exclusive: the owner cannot walk
        // away and leave nobody able to manage the workspace, and nobody else
        // can delete it.
        if (workspace != null && workspace!.role != WorkspaceRole.owner)
          PopupMenuItem(
            value: const _WorkspaceMenuAction(_MenuKind.leave),
            height: 40,
            child: const _MenuRow(
              icon: Icons.logout_rounded,
              label: 'Leave workspace',
              danger: true,
            ),
          ),
        if (workspace?.role == WorkspaceRole.owner)
          PopupMenuItem(
            value: const _WorkspaceMenuAction(_MenuKind.delete),
            height: 40,
            child: const _MenuRow(
              icon: Icons.delete_outline_rounded,
              label: 'Delete workspace',
              danger: true,
            ),
          ),
        if (workspace != null) const PopupMenuDivider(),
        PopupMenuItem(
          value: const _WorkspaceMenuAction(_MenuKind.create),
          height: 40,
          child: const _MenuRow(
            icon: Icons.add_rounded,
            label: 'New workspace',
          ),
        ),
        PopupMenuItem(
          value: const _WorkspaceMenuAction(_MenuKind.join),
          height: 40,
          child: const _MenuRow(
            icon: Icons.login_rounded,
            label: 'Join with a code',
          ),
        ),
      ],
      child: Row(
        mainAxisAlignment: compact
            ? MainAxisAlignment.center
            : MainAxisAlignment.start,
        children: [
          // Always the workspace initial on its own colour. An earlier version
          // showed the app logo when only one workspace existed and switched to
          // an initial once there were several — which made the same workspace
          // change appearance depending on how many others happened to exist.
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: current?.color ?? plannerBlue,
              borderRadius: BorderRadius.circular(radiusMd),
            ),
            alignment: Alignment.center,
            child: Text(
              initial,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (!compact) ...[
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    current?.name ?? 'Get started',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.1,
                    ),
                  ),
                  Text(
                    // "0 members" is wrong before a workspace exists, and
                    // misleading right after one is created while the member
                    // list is still loading.
                    current == null
                        ? 'No workspace yet'
                        : memberCount <= 1
                        ? 'Just you'
                        : '$memberCount members',
                    style: const TextStyle(
                      color: Color(0xFF848AAE),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.unfold_more_rounded,
              size: 15,
              color: Color(0xFF848AAE),
            ),
          ],
        ],
      ),
    );
  }
}

sealed class _WorkspaceAction {
  const _WorkspaceAction();
}

class _WorkspaceSwitchAction extends _WorkspaceAction {
  const _WorkspaceSwitchAction(this.index);
  final int index;
}

enum _MenuKind { create, join, rename, members, leave, delete }

class _WorkspaceMenuAction extends _WorkspaceAction {
  const _WorkspaceMenuAction(this.kind);
  final _MenuKind kind;
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({
    required this.icon,
    required this.label,
    this.trailing,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final String? trailing;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger ? plannerRed : plannerText;
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        if (trailing != null)
          Text(
            trailing!,
            style: const TextStyle(color: plannerFaint, fontSize: 11.5),
          ),
      ],
    );
  }
}

class _BoardNavItem extends StatefulWidget {
  const _BoardNavItem({
    required this.board,
    required this.selected,
    required this.compact,
    required this.onTap,
    required this.onRename,
    required this.onDelete,
    required this.onPin,
  });

  final Board board;
  final bool selected;
  final bool compact;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final VoidCallback onPin;

  @override
  State<_BoardNavItem> createState() => _BoardNavItemState();
}

class _BoardNavItemState extends State<_BoardNavItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final board = widget.board;
    final done = board.doneCount;
    final total = board.taskCount;

    return Tooltip(
      message: widget.compact ? board.name : '',
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: Material(
          color: widget.selected
              ? plannerSidebarHi
              : (_hovered
                    ? Colors.white.withValues(alpha: 0.05)
                    : Colors.transparent),
          borderRadius: BorderRadius.circular(radiusSm),
          child: InkWell(
            borderRadius: BorderRadius.circular(radiusSm),
            onTap: widget.onTap,
            child: Container(
              height: 38,
              padding: EdgeInsets.symmetric(
                horizontal: widget.compact ? 0 : 10,
              ),
              child: Row(
                mainAxisAlignment: widget.compact
                    ? MainAxisAlignment.center
                    : MainAxisAlignment.start,
                children: [
                  // A selected board gets a solid swatch; others a ring, so the
                  // active item reads at a glance.
                  Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      color: widget.selected ? board.color : Colors.transparent,
                      shape: BoxShape.circle,
                      border: Border.all(color: board.color, width: 1.8),
                    ),
                  ),
                  if (!widget.compact) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      child: Row(
                        children: [
                          Flexible(
                            child: Text(
                              board.name,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: widget.selected
                                    ? Colors.white
                                    : const Color(0xFFC8CBDD),
                                fontSize: 13,
                                fontWeight: widget.selected
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                              ),
                            ),
                          ),
                          // Marks why this board is sitting above the others.
                          if (board.pinned) ...[
                            const SizedBox(width: 5),
                            const Icon(
                              Icons.push_pin_rounded,
                              size: 11,
                              color: Color(0xFF7A80A3),
                            ),
                          ],
                        ],
                      ),
                    ),
                    // Always built, only faded. Rendering this behind an
                    // `if (_hovered)` removed the menu from the tree the moment
                    // the pointer left the row — which happens as soon as the
                    // popup opens — so onSelected never fired and Delete board
                    // did nothing at all.
                    SizedBox(
                      width: 30,
                      child: Stack(
                        alignment: Alignment.centerRight,
                        children: [
                          if (total > 0)
                            AnimatedOpacity(
                              duration: const Duration(milliseconds: 120),
                              opacity: _hovered ? 0 : 1,
                              child: Text(
                                '$done/$total',
                                style: const TextStyle(
                                  color: Color(0xFF7A80A3),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          AnimatedOpacity(
                            duration: const Duration(milliseconds: 120),
                            opacity: _hovered ? 1 : 0,
                            child: IgnorePointer(
                              // Only clickable while visible, so the invisible
                              // menu cannot swallow taps meant for the row.
                              ignoring: !_hovered,
                              child: _BoardRowMenu(
                                pinned: board.pinned,
                                onPin: widget.onPin,
                                onRename: widget.onRename,
                                onDelete: widget.onDelete,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Filters the board list by name.
///
/// Dark-on-dark rather than the light form fields elsewhere: this sits inside
/// the sidebar, and a white box here would read as a hole punched in it.
class _BoardSearchField extends StatelessWidget {
  const _BoardSearchField({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 32,
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        style: const TextStyle(color: Colors.white, fontSize: 12.5),
        cursorColor: Colors.white70,
        cursorHeight: 14,
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 8),
          hintText: 'Search boards',
          hintStyle: const TextStyle(color: Color(0xFF7A80A3), fontSize: 12.5),
          prefixIcon: const Icon(
            Icons.search_rounded,
            size: 15,
            color: Color(0xFF7A80A3),
          ),
          prefixIconConstraints: const BoxConstraints(
            minWidth: 32,
            minHeight: 32,
          ),
          suffixIcon: controller.text.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(
                    Icons.close_rounded,
                    size: 14,
                    color: Color(0xFF7A80A3),
                  ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 30,
                    minHeight: 30,
                  ),
                  tooltip: 'Clear',
                  onPressed: () {
                    controller.clear();
                    onChanged('');
                  },
                ),
          filled: true,
          // A plain colour here is only the *resting* fill — Material paints
          // its hover and focus overlays on top, and on this dark rail those
          // overlays are pale enough to swallow the white text. Resolving the
          // same colour for every state keeps the field dark throughout.
          fillColor: const WidgetStatePropertyAll(
            plannerSidebarHi,
          ).resolve(const {}),
          hoverColor: Colors.transparent,
          focusColor: Colors.transparent,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(radiusSm),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(radiusSm),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(radiusSm),
            borderSide: const BorderSide(color: Color(0xFF4A5080)),
          ),
        ),
      ),
    );
  }
}

/// Shown when a search matches nothing — distinct from having no boards at
/// all, which offers a Create button instead.
class _NoBoardMatches extends StatelessWidget {
  const _NoBoardMatches();

  @override
  Widget build(BuildContext context) {
    // The parent is an Expanded, so this Column is as wide as the rail. Its
    // children were left-aligned by default, which read as a layout mistake
    // rather than an empty state — hence stretch plus centred text, and
    // mainAxisSize.min so the group sits at the top rather than spreading
    // down the whole remaining height.
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(Icons.search_off_rounded, size: 20, color: Color(0xFF5B6089)),
          SizedBox(height: 10),
          Text(
            'No boards match',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFF9096B8),
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
            ),
          ),
          SizedBox(height: 3),
          Text(
            'Try a different search.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF6B7099), fontSize: 11.5),
          ),
        ],
      ),
    );
  }
}

class _EmptyBoards extends StatelessWidget {
  const _EmptyBoards({required this.compact, required this.onCreate});

  final bool compact;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'No boards yet',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 12.5,
            ),
          ),
          const SizedBox(height: 4),
          InkWell(
            onTap: onCreate,
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 2),
              child: Text(
                'Create your first board',
                style: TextStyle(
                  color: Color(0xFF9FB0FF),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniIconButton extends StatelessWidget {
  const _MiniIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(radiusXs),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(icon, size: 16, color: const Color(0xFF9096B8)),
        ),
      ),
    );
  }
}

class _BoardRowMenu extends StatelessWidget {
  const _BoardRowMenu({
    required this.pinned,
    required this.onPin,
    required this.onRename,
    required this.onDelete,
  });

  final bool pinned;
  final VoidCallback onPin;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_SidebarBoardAction>(
      tooltip: 'Board actions',
      offset: const Offset(0, 28),
      // Same reason as the workspace menu: the trigger is a 22px icon, and
      // without this the menu inherits that as its maximum width.
      constraints: const BoxConstraints(minWidth: 200, maxWidth: 260),
      onSelected: (action) {
        switch (action) {
          case _SidebarBoardAction.pin:
            onPin();
          case _SidebarBoardAction.rename:
            onRename();
          case _SidebarBoardAction.delete:
            onDelete();
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: _SidebarBoardAction.pin,
          height: 38,
          child: _MenuRow(
            icon: pinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
            label: pinned ? 'Unpin board' : 'Pin to top',
          ),
        ),
        const PopupMenuItem(
          value: _SidebarBoardAction.rename,
          height: 38,
          child: _MenuRow(icon: Icons.edit_outlined, label: 'Edit board'),
        ),
        const PopupMenuItem(
          value: _SidebarBoardAction.delete,
          height: 38,
          child: _MenuRow(
            icon: Icons.delete_outline_rounded,
            label: 'Delete board',
            danger: true,
          ),
        ),
      ],
      child: const SizedBox(
        width: 22,
        height: 22,
        child: Icon(
          Icons.more_horiz_rounded,
          color: Color(0xFF9096B8),
          size: 16,
        ),
      ),
    );
  }
}

enum _SidebarBoardAction { pin, rename, delete }

/// Sign out, at the foot of the sidebar. Red on hover so the consequence is
/// clear without shouting at rest.
class _SidebarSignOut extends StatefulWidget {
  const _SidebarSignOut({required this.compact, required this.onPressed});

  final bool compact;
  final VoidCallback onPressed;

  @override
  State<_SidebarSignOut> createState() => _SidebarSignOutState();
}

class _SidebarSignOutState extends State<_SidebarSignOut> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final foreground = _hovered ? plannerRed : const Color(0xFF9096B8);

    return Padding(
      padding: widget.compact
          ? const EdgeInsets.fromLTRB(14, 10, 14, 12)
          : const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Tooltip(
        message: widget.compact ? 'Sign out' : '',
        child: MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: Material(
            color: _hovered
                ? plannerRed.withValues(alpha: 0.14)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(radiusSm),
            child: InkWell(
              borderRadius: BorderRadius.circular(radiusSm),
              onTap: widget.onPressed,
              child: Container(
                height: 36,
                padding: EdgeInsets.symmetric(
                  horizontal: widget.compact ? 0 : 10,
                ),
                child: Row(
                  mainAxisAlignment: widget.compact
                      ? MainAxisAlignment.center
                      : MainAxisAlignment.start,
                  children: [
                    Icon(Icons.logout_rounded, size: 16, color: foreground),
                    if (!widget.compact) ...[
                      const SizedBox(width: 9),
                      Text(
                        'Sign out',
                        style: TextStyle(
                          color: foreground,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
