import 'package:flutter/material.dart';

import '../../../models/planner_models.dart';
import '../../../models/board_filter.dart';
import '../../../shared/utils/planner_colors.dart';
import 'filter_panel.dart';

class BoardToolbar extends StatelessWidget {
  const BoardToolbar({
    super.key,
    required this.mode,
    required this.onModeChanged,
    required this.searchController,
    required this.search,
    required this.filters,
    required this.savedViews,
    required this.onSearchChanged,
    required this.onSaveView,
    required this.onDeleteView,
    required this.onApplyView,
    required this.taskOrder,
    required this.onTaskOrderChanged,
  });

  final ViewMode mode;
  final ValueChanged<ViewMode> onModeChanged;

  /// The search lives on this row rather than up in the header: it belongs
  /// beside the view switcher it acts on, and the header row was crowded
  /// enough that the bar had to shrink to fit beside the board title.
  final TextEditingController searchController;
  final BoardSearch search;
  final List<BoardFilter> filters;
  final List<SavedView> savedViews;
  final ValueChanged<BoardSearch> onSearchChanged;
  final void Function(String name, bool isDefault) onSaveView;
  final ValueChanged<SavedView> onDeleteView;
  final ValueChanged<SavedView> onApplyView;
  final TaskOrder taskOrder;
  final ValueChanged<TaskOrder> onTaskOrderChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Narrower search on a small window, so the view buttons keep their
        // labels rather than being scrolled out of reach.
        final searchWidth = constraints.maxWidth < 900 ? 260.0 : 340.0;

        return Container(
          height: 50,
          padding: const EdgeInsets.symmetric(horizontal: 28),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(bottom: BorderSide(color: plannerBorder)),
          ),
          child: Row(
            children: [
              // The view buttons take only the width their labels need.
              //
              // Expanded, with the buttons pinned left inside it, so the
              // leftover width is absorbed here and the search is pushed
              // against the right edge. A Spacer cannot do that job beside a
              // scroll view: the scroller reports an unbounded width, claims
              // its share first, and the search stopped ~120px shy of the edge.
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    physics: const ClampingScrollPhysics(),
                    child: Row(
                      children: [
                        ViewButton(
                          icon: Icons.table_rows_outlined,
                          label: 'Table',
                          selected: mode == ViewMode.table,
                          onTap: () => onModeChanged(ViewMode.table),
                        ),
                        ViewButton(
                          icon: Icons.view_kanban_outlined,
                          label: 'Kanban',
                          selected: mode == ViewMode.kanban,
                          onTap: () => onModeChanged(ViewMode.kanban),
                        ),
                        ViewButton(
                          icon: Icons.calendar_today_outlined,
                          label: 'Calendar',
                          selected: mode == ViewMode.calendar,
                          onTap: () => onModeChanged(ViewMode.calendar),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              SizedBox(
                width: searchWidth,
                child: FilterBar(
                  controller: searchController,
                  search: search,
                  filters: filters,
                  savedViews: savedViews,
                  onChanged: onSearchChanged,
                  onSaveView: onSaveView,
                  onDeleteView: onDeleteView,
                  onApplyView: onApplyView,
                  taskOrder: taskOrder,
                  onTaskOrderChanged: onTaskOrderChanged,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class ViewButton extends StatelessWidget {
  const ViewButton({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFFF0F1F5) : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            children: [
              Icon(icon, size: 16, color: selected ? plannerInk : plannerMuted),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: selected ? plannerInk : plannerMuted,
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
