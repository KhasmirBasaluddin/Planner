import 'package:flutter/material.dart';

import '../../../models/planner_models.dart';
import '../../../shared/utils/planner_colors.dart';

class BoardToolbar extends StatelessWidget {
  const BoardToolbar({
    super.key,
    required this.mode,
    required this.taskOrder,
    required this.onModeChanged,
    required this.onTaskOrderChanged,
  });

  final ViewMode mode;
  final TaskOrder taskOrder;
  final ValueChanged<ViewMode> onModeChanged;
  final ValueChanged<TaskOrder> onTaskOrderChanged;

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
          TaskOrderMenu(value: taskOrder, onChanged: onTaskOrderChanged),
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

class TaskOrderMenu extends StatelessWidget {
  const TaskOrderMenu({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final TaskOrder value;
  final ValueChanged<TaskOrder> onChanged;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<TaskOrder>(
      tooltip: 'Sort tasks',
      offset: const Offset(0, 40),
      color: Colors.white,
      surfaceTintColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onSelected: onChanged,
      itemBuilder: (context) => [
        for (final order in TaskOrder.values)
          PopupMenuItem(
            value: order,
            child: Row(
              children: [
                Icon(
                  order == value ? Icons.check_rounded : Icons.sort_rounded,
                  size: 18,
                  color: order == value ? plannerBlue : plannerMuted,
                ),
                const SizedBox(width: 10),
                Text(order.label),
              ],
            ),
          ),
      ],
      child: Container(
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: value == TaskOrder.manual
              ? Colors.white
              : const Color(0xFFEAF2FF),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: value == TaskOrder.manual
                ? plannerBorder
                : const Color(0xFFCFE0FF),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.swap_vert_rounded,
              size: 17,
              color: value == TaskOrder.manual ? plannerText : plannerBlue,
            ),
            const SizedBox(width: 8),
            Text(
              value == TaskOrder.manual ? 'Sort' : value.label,
              style: TextStyle(
                color: value == TaskOrder.manual ? plannerText : plannerBlue,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
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
