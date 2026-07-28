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
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 28),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: plannerBorder)),
      ),
      child: Row(
        children: [
          // The three view buttons have fixed labels; on a narrow window they
          // would push Sort off the edge, so the group scrolls instead.
          Expanded(
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
          const SizedBox(width: 12),
          TaskOrderMenu(value: taskOrder, onChanged: onTaskOrderChanged),
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
    final active = value != TaskOrder.manual;
    return PopupMenuButton<TaskOrder>(
      tooltip: 'Sort tasks',
      offset: const Offset(0, 36),
      onSelected: onChanged,
      itemBuilder: (context) => [
        for (final order in TaskOrder.values)
          PopupMenuItem(
            value: order,
            height: 38,
            child: Row(
              children: [
                SizedBox(
                  width: 18,
                  child: order == value
                      ? const Icon(
                          Icons.check_rounded,
                          size: 16,
                          color: plannerBlue,
                        )
                      : null,
                ),
                const SizedBox(width: 8),
                Text(
                  order.label,
                  style: TextStyle(
                    fontSize: 13,
                    color: order == value ? plannerInk : plannerText,
                    fontWeight: order == value
                        ? FontWeight.w600
                        : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
      ],
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: active ? const Color(0xFFBFD4FA) : plannerBorder,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.swap_vert_rounded,
              size: 15,
              color: active ? plannerBlue : plannerMuted,
            ),
            const SizedBox(width: 6),
            Text(
              active ? value.label : 'Sort',
              style: TextStyle(
                color: active ? plannerBlue : plannerText,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

