import 'package:flutter/material.dart';

import '../../../models/planner_models.dart';
import '../../../shared/utils/planner_colors.dart';
import '../../../shared/widgets/app_dialog.dart';
import 'planner_dialogs.dart' show formatDate;

/// One task the banner is raising: why it needs attention, most pressing
/// reason first.
class AttentionEntry {
  const AttentionEntry({
    required this.task,
    required this.overdue,
    required this.dueSoon,
    required this.urgent,
  });

  final PlannerTask task;
  final bool overdue;

  /// Due today or tomorrow.
  final bool dueSoon;

  /// Urgent priority.
  final bool urgent;

  String get reason {
    final due = task.dueDate;
    if (overdue && due != null) {
      return 'Overdue — was due ${formatDate(due)}';
    }
    if (dueSoon && due != null) {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final dueDay = DateTime(due.year, due.month, due.day);
      return dueDay == today ? 'Due today' : 'Due tomorrow';
    }
    return 'Urgent priority';
  }

  Color get tone =>
      overdue ? plannerRed : (dueSoon ? plannerOrange : plannerRed);

  /// Orders the most pressing first: overdue, then imminent, then urgent.
  int get rank => overdue ? 0 : (dueSoon ? 1 : 2);
}

/// The strip under the navbar that will not let a deadline pass silently.
///
/// The bell only helps someone who opens it, and a due date is exactly the
/// kind of news that gets missed until it is late. This stays on screen while
/// the board holds overdue, imminent, or urgent unfinished tasks. Dismissable,
/// but any change to that set brings it back — silence is only ever bought
/// for the tasks already seen.
class AttentionBanner extends StatelessWidget {
  const AttentionBanner({
    super.key,
    required this.entries,
    required this.onOpenTask,
    required this.onDismiss,
  });

  final List<AttentionEntry> entries;
  final ValueChanged<PlannerTask> onOpenTask;
  final VoidCallback onDismiss;

  /// Stable identity for a set of alerts, so the page can tell "same ones the
  /// user dismissed" from "something changed".
  static String signatureOf(List<AttentionEntry> entries) {
    final parts = [
      for (final entry in entries)
        '${entry.task.id}:${entry.overdue}:${entry.dueSoon}:${entry.urgent}',
    ]..sort();
    return parts.join('|');
  }

  int get _overdueCount => entries.where((e) => e.overdue).length;
  int get _dueSoonCount => entries.where((e) => e.dueSoon).length;
  int get _urgentCount => entries.where((e) => e.urgent).length;

  String get _summary {
    final parts = <String>[
      if (_overdueCount > 0) '$_overdueCount overdue',
      if (_dueSoonCount > 0)
        '$_dueSoonCount due ${_dueSoonCount == 1 ? '' : 'dates '}soon'
            .replaceAll('  ', ' '),
      if (_urgentCount > 0) '$_urgentCount urgent',
    ];
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final hot = _overdueCount > 0;
    final tone = hot ? plannerRed : plannerOrange;

    return Material(
      color: Color.alphaBlend(tint(tone, 0.08), plannerCard),
      child: InkWell(
        onTap: () => _showList(context),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: tint(tone, 0.25))),
          ),
          child: Row(
            children: [
              Icon(
                hot
                    ? Icons.error_outline_rounded
                    : Icons.notification_important_outlined,
                size: 16,
                color: tone,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  '${entries.length} task${entries.length == 1 ? '' : 's'} '
                  'need${entries.length == 1 ? 's' : ''} attention — $_summary',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Color.lerp(tone, plannerInk, 0.35),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => _showList(context),
                style: TextButton.styleFrom(
                  minimumSize: Size.zero,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  foregroundColor: tone,
                  textStyle: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                child: const Text('Review'),
              ),
              const SizedBox(width: 2),
              Tooltip(
                message: 'Hide until these change',
                child: InkWell(
                  onTap: onDismiss,
                  borderRadius: BorderRadius.circular(radiusXs),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(Icons.close_rounded, size: 14, color: tone),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showList(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AppDialog(
        icon: Icons.notification_important_outlined,
        tone: _overdueCount > 0 ? plannerRed : plannerYellow,
        title: 'Needs attention',
        message: 'Most pressing first. Click a task to open it.',
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final entry in entries)
              _AttentionRow(
                entry: entry,
                onTap: () {
                  Navigator.of(dialogContext).pop();
                  onOpenTask(entry.task);
                },
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

class _AttentionRow extends StatelessWidget {
  const _AttentionRow({required this.entry, required this.onTap});

  final AttentionEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(radiusSm),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: entry.tone,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    entry.task.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: plannerInk,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    entry.urgent && entry.rank < 2
                        ? '${entry.reason} · Urgent priority'
                        : entry.reason,
                    style: TextStyle(color: entry.tone, fontSize: 11.5),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              size: 16,
              color: plannerFaint,
            ),
          ],
        ),
      ),
    );
  }
}
