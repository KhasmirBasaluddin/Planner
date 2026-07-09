import 'package:flutter/material.dart';

import '../../../models/planner_models.dart';
import '../../../shared/utils/planner_colors.dart';

class BoardToolbar extends StatelessWidget {
  const BoardToolbar({
    super.key,
    required this.mode,
    required this.onModeChanged,
  });

  final ViewMode mode;
  final ValueChanged<ViewMode> onModeChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 58,
      padding: const EdgeInsets.symmetric(horizontal: 28),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: plannerBorder)),
      ),
      child: Row(
        children: [
          ViewButton(
            icon: Icons.table_rows_rounded,
            label: 'Table',
            selected: mode == ViewMode.table,
            onTap: () => onModeChanged(ViewMode.table),
          ),
          ViewButton(
            icon: Icons.view_kanban_rounded,
            label: 'Kanban',
            selected: mode == ViewMode.kanban,
            onTap: () => onModeChanged(ViewMode.kanban),
          ),
          ViewButton(
            icon: Icons.calendar_today_rounded,
            label: 'Calendar',
            selected: mode == ViewMode.calendar,
            onTap: () => onModeChanged(ViewMode.calendar),
          ),
          const Spacer(),
          const ToolButton(icon: Icons.filter_list_rounded, label: 'Filter'),
          const SizedBox(width: 8),
          const ToolButton(icon: Icons.swap_vert_rounded, label: 'Sort'),
          const SizedBox(width: 8),
          const ToolButton(icon: Icons.more_horiz_rounded, label: 'More'),
        ],
      ),
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
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFFEAF2FF) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 18,
                color: selected ? plannerBlue : plannerMuted,
              ),
              const SizedBox(width: 7),
              Text(
                label,
                style: TextStyle(
                  color: selected ? plannerBlue : plannerText,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ToolButton extends StatelessWidget {
  const ToolButton({super.key, required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: () {},
      icon: Icon(icon, size: 17),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: plannerText,
        side: const BorderSide(color: plannerBorder),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}
