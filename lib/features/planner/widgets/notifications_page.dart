import 'package:flutter/material.dart';

import '../../../core/supabase/planner_repository.dart';
import '../../../models/planner_models.dart';
import '../../../shared/utils/planner_colors.dart';
import '../../../shared/widgets/user_avatar.dart';

/// The whole notification history, as a view inside the app rather than a
/// route of its own.
///
/// The bell panel deliberately shows a recent slice — it is something you
/// glance at on the way past. This is the other half: everything, filterable,
/// with room to read it. It replaces the board in the content area and leaves
/// the sidebar and navbar in place, so it reads as another view of the same
/// application rather than a separate screen you have been thrown into.
class NotificationsView extends StatefulWidget {
  const NotificationsView({
    super.key,
    required this.repository,
    required this.onOpen,
    required this.onMarkAllRead,
    required this.onClose,
  });

  final PlannerRepository repository;
  final ValueChanged<AppNotification> onOpen;
  final VoidCallback onMarkAllRead;
  final VoidCallback onClose;

  @override
  State<NotificationsView> createState() => _NotificationsViewState();
}

/// The slices offered above the list. Kept coarse on purpose: these are the
/// questions people actually arrive with, and a filter per notification kind
/// would be a wall of chips nobody reads.
enum _Filter { all, unread, mentions, tasks }

extension on _Filter {
  String get label => switch (this) {
    _Filter.all => 'All',
    _Filter.unread => 'Unread',
    _Filter.mentions => 'Mentions',
    _Filter.tasks => 'Tasks',
  };

  IconData get icon => switch (this) {
    _Filter.all => Icons.inbox_rounded,
    _Filter.unread => Icons.mark_email_unread_outlined,
    _Filter.mentions => Icons.alternate_email_rounded,
    _Filter.tasks => Icons.task_alt_rounded,
  };

  bool matches(AppNotification n) => switch (this) {
    _Filter.all => true,
    _Filter.unread => n.isUnread,
    _Filter.mentions =>
      n.kind == NotificationKind.mentioned ||
          n.kind == NotificationKind.commentAdded,
    _Filter.tasks => const {
      NotificationKind.taskAssigned,
      NotificationKind.taskUnassigned,
      NotificationKind.taskDueSoon,
      NotificationKind.taskOverdue,
      NotificationKind.taskStatusChanged,
      NotificationKind.noteAdded,
    }.contains(n.kind),
  };
}

class _NotificationsViewState extends State<NotificationsView> {
  List<AppNotification> _all = [];
  _Filter _filter = _Filter.all;
  bool _loading = true;
  String? _error;

  /// Well past what the bell asks for. This is where someone goes looking for
  /// something specific, so it should not stop at the recent handful.
  static const int _historyLimit = 500;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final items = await widget.repository.loadNotifications(
        limit: _historyLimit,
      );
      if (mounted) {
        setState(() {
          _all = items;
          _loading = false;
          _error = null;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = error.toString();
        });
      }
    }
  }

  List<AppNotification> get _visible =>
      _all.where(_filter.matches).toList();

  int _countFor(_Filter filter) => _all.where(filter.matches).length;

  int get _unread => _countFor(_Filter.unread);

  void _markAllRead() {
    widget.onMarkAllRead();
    // Repaint at once rather than waiting for the realtime echo, which would
    // leave every row looking untouched for a beat.
    setState(() => _all = [for (final n in _all) n.markedRead()]);
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visible;

    return Container(
      color: plannerSurface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(
            unread: _unread,
            onBack: widget.onClose,
            onMarkAllRead: _unread > 0 ? _markAllRead : null,
            onRefresh: _loading ? null : _load,
          ),
          _FilterBar(
            current: _filter,
            countOf: _countFor,
            onChanged: (filter) => setState(() => _filter = filter),
          ),
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  )
                : _error != null
                ? _Message(
                    icon: Icons.error_outline_rounded,
                    title: 'Could not load notifications',
                    detail: _error!,
                    tone: plannerRed,
                    onRetry: _load,
                  )
                : visible.isEmpty
                ? _Message(
                    icon: _filter.icon,
                    title: switch (_filter) {
                      _Filter.unread => 'Nothing unread',
                      _Filter.mentions => 'No mentions yet',
                      _Filter.tasks => 'No task activity yet',
                      _Filter.all => 'No notifications yet',
                    },
                    detail: switch (_filter) {
                      _Filter.unread => 'You are all caught up.',
                      _Filter.mentions =>
                        'When someone @mentions you or replies, it lands here.',
                      _Filter.tasks =>
                        'Assignments, due dates and status changes land here.',
                      _Filter.all =>
                        'Assignments, mentions and replies will appear here.',
                    },
                  )
                : _Timeline(
                    items: visible,
                    onOpen: widget.onOpen,
                  ),
          ),
        ],
      ),
    );
  }
}

/// Title row, matching the board header's weight so switching between them
/// does not feel like changing applications.
class _Header extends StatelessWidget {
  const _Header({
    required this.unread,
    required this.onBack,
    required this.onMarkAllRead,
    required this.onRefresh,
  });

  final int unread;
  final VoidCallback onBack;
  final VoidCallback? onMarkAllRead;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
      decoration: const BoxDecoration(
        color: plannerCard,
        border: Border(bottom: BorderSide(color: plannerBorder)),
      ),
      child: Row(
        children: [
          _IconAction(
            icon: Icons.arrow_back_rounded,
            tooltip: 'Back to board',
            onPressed: onBack,
          ),
          const SizedBox(width: 12),
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: tint(plannerBlue, 0.1),
              borderRadius: BorderRadius.circular(radiusMd),
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.notifications_rounded,
              size: 18,
              color: plannerBlue,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Notifications',
                  style: TextStyle(
                    color: plannerInk,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                  ),
                ),
                Text(
                  unread == 0
                      ? 'Everything read'
                      : '$unread unread',
                  style: const TextStyle(
                    color: plannerMuted,
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          if (onMarkAllRead != null)
            TextButton.icon(
              onPressed: onMarkAllRead,
              icon: const Icon(Icons.done_all_rounded, size: 16),
              label: const Text('Mark all read'),
            ),
          const SizedBox(width: 4),
          _IconAction(
            icon: Icons.refresh_rounded,
            tooltip: 'Refresh',
            onPressed: onRefresh,
          ),
        ],
      ),
    );
  }
}

class _IconAction extends StatelessWidget {
  const _IconAction({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(radiusSm),
        child: InkWell(
          borderRadius: BorderRadius.circular(radiusSm),
          onTap: onPressed,
          child: SizedBox(
            width: 32,
            height: 32,
            child: Icon(
              icon,
              size: 18,
              color: onPressed == null ? plannerFaint : plannerMuted,
            ),
          ),
        ),
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.current,
    required this.countOf,
    required this.onChanged,
  });

  final _Filter current;
  final int Function(_Filter) countOf;
  final ValueChanged<_Filter> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      decoration: const BoxDecoration(
        color: plannerCard,
        border: Border(bottom: BorderSide(color: plannerBorder)),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final filter in _Filter.values)
            _Chip(
              filter: filter,
              count: countOf(filter),
              selected: current == filter,
              onTap: () => onChanged(filter),
            ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.filter,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final _Filter filter;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? plannerBlue : plannerSurface,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected ? plannerBlue : plannerBorder,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                filter.icon,
                size: 14,
                color: selected ? Colors.white : plannerMuted,
              ),
              const SizedBox(width: 6),
              Text(
                filter.label,
                style: TextStyle(
                  color: selected ? Colors.white : plannerText,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 1,
                ),
                decoration: BoxDecoration(
                  color: selected
                      ? Colors.white.withValues(alpha: 0.22)
                      : plannerBorder,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    color: selected ? Colors.white : plannerMuted,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The list, grouped under date headings and centred in a readable column.
///
/// Full-bleed rows across a wide desktop window put the timestamp a long way
/// from the title it belongs to, which is what made the first version read as
/// a spreadsheet.
class _Timeline extends StatelessWidget {
  const _Timeline({required this.items, required this.onOpen});

  final List<AppNotification> items;
  final ValueChanged<AppNotification> onOpen;

  @override
  Widget build(BuildContext context) {
    final groups = _groupByDay(items);

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
      itemCount: groups.length,
      itemBuilder: (context, index) {
        final entry = groups.entries.elementAt(index);
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: EdgeInsets.only(top: index == 0 ? 0 : 22, bottom: 9),
                  child: Row(
                    children: [
                      Text(
                        entry.key,
                        style: const TextStyle(
                          color: plannerMuted,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Divider(height: 1, color: plannerBorder),
                      ),
                    ],
                  ),
                ),
                for (final notification in entry.value)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 7),
                    child: _Row(
                      notification: notification,
                      onTap: () => onOpen(notification),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Buckets by day, preserving the newest-first order the query returned.
  static Map<String, List<AppNotification>> _groupByDay(
    List<AppNotification> items,
  ) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final grouped = <String, List<AppNotification>>{};

    for (final item in items) {
      final when = item.createdAt.toLocal();
      final days = today
          .difference(DateTime(when.year, when.month, when.day))
          .inDays;
      final label = switch (days) {
        0 => 'TODAY',
        1 => 'YESTERDAY',
        < 7 => 'EARLIER THIS WEEK',
        < 30 => 'THIS MONTH',
        _ => 'OLDER',
      };
      grouped.putIfAbsent(label, () => []).add(item);
    }
    return grouped;
  }
}

class _Row extends StatefulWidget {
  const _Row({required this.notification, required this.onTap});

  final AppNotification notification;
  final VoidCallback onTap;

  @override
  State<_Row> createState() => _RowState();
}

class _RowState extends State<_Row> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final notification = widget.notification;
    final unread = notification.isUnread;
    final actor = notification.actor;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
          decoration: BoxDecoration(
            // Unread carries a faint wash as well as the dot, so a glance down
            // the list finds them without reading a word.
            color: unread ? tint(plannerBlue, 0.05) : plannerCard,
            borderRadius: BorderRadius.circular(radiusMd),
            border: Border.all(
              color: _hovered
                  ? plannerBlue.withValues(alpha: 0.45)
                  : (unread
                        ? plannerBlue.withValues(alpha: 0.22)
                        : plannerBorder),
            ),
            boxShadow: _hovered ? shadowLg : null,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // The person, where there is one — a face identifies the event
              // faster than an icon for its category. System-raised
              // notifications keep the icon.
              if (actor != null)
                UserAvatar(profile: actor, size: 32, showTooltip: false)
              else
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: tint(plannerBlue, 0.1),
                    borderRadius: BorderRadius.circular(radiusSm),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    notification.kind.icon,
                    size: 16,
                    color: plannerBlue,
                  ),
                ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      notification.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: plannerInk,
                        fontSize: 13,
                        fontWeight: unread
                            ? FontWeight.w700
                            : FontWeight.w500,
                        height: 1.35,
                      ),
                    ),
                    if (notification.body.trim().isNotEmpty) ...[
                      const SizedBox(height: 3),
                      // Two lines at most. A pasted wall of text used to run
                      // the full width of the window and dwarf its own title.
                      Text(
                        notification.body.trim(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: plannerMuted,
                          fontSize: 12,
                          height: 1.4,
                        ),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(
                          notification.kind.icon,
                          size: 12,
                          color: plannerFaint,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          _time(notification.createdAt),
                          style: const TextStyle(
                            color: plannerFaint,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              if (unread)
                Container(
                  margin: const EdgeInsets.only(top: 5),
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: plannerBlue,
                    shape: BoxShape.circle,
                  ),
                )
              else
                const SizedBox(width: 8),
            ],
          ),
        ),
      ),
    );
  }

  /// Clock time for today, a date beyond it. Under a day heading the date
  /// would only repeat what the heading already said.
  static String _time(DateTime at) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final local = at.toLocal();
    final now = DateTime.now();
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    final suffix = local.hour < 12 ? 'AM' : 'PM';
    final clock = '$hour:$minute $suffix';

    final sameDay = local.year == now.year &&
        local.month == now.month &&
        local.day == now.day;
    if (sameDay) {
      return clock;
    }
    final year = local.year == now.year ? '' : ' ${local.year}';
    return '${local.day} ${months[local.month - 1]}$year · $clock';
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    required this.detail,
    this.tone = plannerFaint,
    this.onRetry,
  });

  final IconData icon;
  final String title;
  final String detail;
  final Color tone;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: tint(tone, 0.1),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Icon(icon, size: 26, color: tone),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: plannerInk,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 340),
              child: Text(
                detail,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: plannerMuted,
                  fontSize: 12.5,
                  height: 1.45,
                ),
              ),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('Try again'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
