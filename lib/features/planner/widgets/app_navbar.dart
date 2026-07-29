import 'package:flutter/material.dart';

import '../../../models/planner_models.dart';
import '../../../shared/utils/planner_colors.dart';
import '../../../shared/widgets/user_avatar.dart';

/// The bar across the top of the app: notifications and account on the right.
///
/// Exists mainly to give identity and sign-out somewhere sensible to live. Both
/// were previously crammed into the bottom of the sidebar, where the email had
/// to truncate to fit beside the button.
class AppNavbar extends StatelessWidget {
  const AppNavbar({
    super.key,
    required this.fullName,
    required this.email,
    required this.invites,
    required this.notifications,
    required this.onAcceptInvite,
    required this.onDeclineInvite,
    required this.onOpenNotification,
    required this.onMarkAllRead,
  });

  final String fullName;
  final String email;

  /// Invitations awaiting an answer. Shown above the feed, because they are
  /// the only notifications that need a decision rather than a glance.
  final List<PendingInvite> invites;
  final List<AppNotification> notifications;
  final ValueChanged<PendingInvite> onAcceptInvite;
  final ValueChanged<PendingInvite> onDeclineInvite;
  final ValueChanged<AppNotification> onOpenNotification;
  final VoidCallback onMarkAllRead;

  @override
  Widget build(BuildContext context) {
    // White, and without a logo: the sidebar beside it already carries the
    // brand, so repeating it here would say the same thing twice.
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: const BoxDecoration(
        color: plannerCard,
        border: Border(bottom: BorderSide(color: plannerBorder)),
      ),
      child: Row(
        children: [
          const Spacer(),
          _NotificationBell(
            invites: invites,
            notifications: notifications,
            onAccept: onAcceptInvite,
            onDecline: onDeclineInvite,
            onOpen: onOpenNotification,
            onMarkAllRead: onMarkAllRead,
          ),
          const SizedBox(width: 14),
          _AccountChip(fullName: fullName, email: email),
        ],
      ),
    );
  }
}

/// Name over email, with an avatar. Enough room here to show both, which is
/// what the sidebar could not do.
class _AccountChip extends StatelessWidget {
  const _AccountChip({required this.fullName, required this.email});

  final String fullName;
  final String email;

  @override
  Widget build(BuildContext context) {
    final name = fullName.trim().isEmpty ? _localPart(email) : fullName.trim();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 30,
          height: 30,
          // Fixed so it never squashes into an oval next to a long name.
          decoration: BoxDecoration(
            color: avatarColor(email),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text(
            name.characters.first.toUpperCase(),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: 9),
        // Capped and ellipsized: a long display name or email would otherwise
        // grow the chip until it pushed itself off the edge of the bar.
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 220),
          child: Tooltip(
            message: name == email ? email : '$name — $email',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: plannerInk,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                  ),
                ),
                Text(
                  email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: plannerMuted,
                    fontSize: 11,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  static String _localPart(String email) {
    final at = email.indexOf('@');
    return at > 0 ? email.substring(0, at) : email;
  }
}

/// Panel geometry, shared between the menu constraints and the panel itself so
/// the two cannot disagree.
const double _panelWidth = 380;
const double _panelMaxHeight = 480;

/// The notification centre.
///
/// A panel rather than a dropdown menu. `PopupMenuButton` gives every child a
/// uniform row height and its own tap-to-close, which fights all three things
/// this needs: invitation cards taller than a feed row, a header that stays put
/// while you read, and a scrolling list that does not dismiss on a stray tap.
class _NotificationBell extends StatefulWidget {
  const _NotificationBell({
    required this.invites,
    required this.notifications,
    required this.onAccept,
    required this.onDecline,
    required this.onOpen,
    required this.onMarkAllRead,
  });

  final List<PendingInvite> invites;
  final List<AppNotification> notifications;
  final ValueChanged<PendingInvite> onAccept;
  final ValueChanged<PendingInvite> onDecline;
  final ValueChanged<AppNotification> onOpen;
  final VoidCallback onMarkAllRead;

  @override
  State<_NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<_NotificationBell> {
  final MenuController _menu = MenuController();

  int get _unread => widget.notifications.where((n) => n.isUnread).length;

  /// An unanswered invitation counts however its notification row is marked —
  /// it is outstanding work, not news.
  int get _badge => _unread + widget.invites.length;

  @override
  Widget build(BuildContext context) {
    final count = _badge;

    return MenuAnchor(
      controller: _menu,
      // Pulls the panel left so its right edge sits under the bell rather than
      // running off the window. The bell is 34px wide, and 8px of inset keeps
      // the panel clear of the window edge.
      alignmentOffset: const Offset(-(_panelWidth - 34 - 8), 6),
      style: MenuStyle(
        backgroundColor: WidgetStateProperty.all(Colors.transparent),
        elevation: WidgetStateProperty.all(0),
        padding: WidgetStateProperty.all(EdgeInsets.zero),
        // A fixed width, not just the panel's own.
        //
        // MenuAnchor wraps its children in IntrinsicWidth, which asks every
        // descendant how wide it wants to be. A scrollable cannot answer that —
        // its extent depends on the space it is given, not the other way round —
        // so the ListView inside the panel threw "RenderShrinkWrappingViewport
        // does not support returning intrinsic dimensions" and the whole menu
        // failed to lay out. Constraining it here settles the width before the
        // scrollable is ever consulted.
        maximumSize: WidgetStateProperty.all(
          const Size(_panelWidth, _panelMaxHeight),
        ),
        minimumSize: WidgetStateProperty.all(const Size(_panelWidth, 0)),
        fixedSize: WidgetStateProperty.all(const Size.fromWidth(_panelWidth)),
      ),
      menuChildren: [
        _NotificationPanel(
          invites: widget.invites,
          notifications: widget.notifications,
          unread: _unread,
          onAccept: (invite) {
            _menu.close();
            widget.onAccept(invite);
          },
          onDecline: (invite) {
            _menu.close();
            widget.onDecline(invite);
          },
          onOpen: (notification) {
            _menu.close();
            widget.onOpen(notification);
          },
          // Stays open: marking everything read is something you do while
          // looking at the list, not on the way out of it.
          onMarkAllRead: widget.onMarkAllRead,
        ),
      ],
      builder: (context, controller, _) {
        return Tooltip(
          message: count == 0
              ? 'Notifications'
              : '$count unread notification${count == 1 ? '' : 's'}',
          child: InkWell(
            onTap: () =>
                controller.isOpen ? controller.close() : controller.open(),
            borderRadius: BorderRadius.circular(radiusSm),
            child: SizedBox(
              width: 34,
              height: 34,
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  Icon(
                    count > 0
                        ? Icons.notifications_rounded
                        : Icons.notifications_none_rounded,
                    size: 19,
                    color: count > 0 ? plannerBlue : plannerMuted,
                  ),
                  if (count > 0)
                    Positioned(
                      top: 4,
                      right: 5,
                      child: Container(
                        constraints: const BoxConstraints(minWidth: 15),
                        height: 15,
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        decoration: BoxDecoration(
                          color: plannerRed,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: plannerCard, width: 1.5),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          count > 9 ? '9+' : '$count',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _NotificationPanel extends StatefulWidget {
  const _NotificationPanel({
    required this.invites,
    required this.notifications,
    required this.unread,
    required this.onAccept,
    required this.onDecline,
    required this.onOpen,
    required this.onMarkAllRead,
  });

  final List<PendingInvite> invites;
  final List<AppNotification> notifications;
  final int unread;
  final ValueChanged<PendingInvite> onAccept;
  final ValueChanged<PendingInvite> onDecline;
  final ValueChanged<AppNotification> onOpen;
  final VoidCallback onMarkAllRead;

  @override
  State<_NotificationPanel> createState() => _NotificationPanelState();
}

class _NotificationPanelState extends State<_NotificationPanel> {
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  List<PendingInvite> get invites => widget.invites;
  List<AppNotification> get notifications => widget.notifications;
  int get unread => widget.unread;
  ValueChanged<PendingInvite> get onAccept => widget.onAccept;
  ValueChanged<PendingInvite> get onDecline => widget.onDecline;
  ValueChanged<AppNotification> get onOpen => widget.onOpen;
  VoidCallback get onMarkAllRead => widget.onMarkAllRead;

  /// The feed minus anything already shown as an invitation card.
  ///
  /// An invitation produces two records — the `workspace_invites` row that
  /// carries Accept and Decline, and a `notifications` row announcing it. Both
  /// belong in the panel, but not as two separate entries for the same event,
  /// so the card wins and its announcement is dropped.
  ///
  /// Once answered the invitation leaves `invites`, and its notification
  /// reappears in the feed as the record that it happened.
  List<AppNotification> get _feed {
    if (invites.isEmpty) {
      return notifications;
    }
    final pending = {for (final invite in invites) invite.id};
    return notifications
        .where(
          (n) =>
              n.kind != NotificationKind.workspaceInvite ||
              !pending.contains(n.inviteId),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final feed = _feed;

    return Container(
      width: _panelWidth,
      // Capped so a long history scrolls inside the panel instead of growing
      // past the bottom of the window.
      constraints: const BoxConstraints(maxHeight: _panelMaxHeight),
      decoration: BoxDecoration(
        color: plannerCard,
        borderRadius: BorderRadius.circular(radiusLg),
        border: Border.all(color: plannerBorder),
        boxShadow: shadowLg,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _PanelHeader(unread: unread, onMarkAllRead: onMarkAllRead),
          if (invites.isEmpty && feed.isEmpty)
            const _EmptyState()
          else
            // SingleChildScrollView over a Column, not a ListView.
            //
            // MenuAnchor wraps its children in IntrinsicWidth, which asks each
            // descendant how wide it wants to be. A lazy viewport refuses that
            // question — answering it would mean building every child, which is
            // the opposite of being lazy — so a ListView here threw
            // "RenderShrinkWrappingViewport does not support returning
            // intrinsic dimensions" and the panel failed to lay out at all.
            //
            // This scrollable builds its children eagerly, so it can answer.
            // The list is capped at 50 by the query behind it, which is well
            // within what eager layout handles comfortably.
            Flexible(
              child: SingleChildScrollView(
                // MenuAnchor already puts a scrollable around its children and
                // claims the PrimaryScrollController. Without its own, this one
                // claims it too, and a Scrollbar cannot paint against two
                // attached positions.
                controller: _scroll,
                padding: const EdgeInsets.only(bottom: 6),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Invitations first and visually distinct: they are the
                    // only entries asking for a decision rather than a glance.
                    for (final invite in invites)
                      _InviteCard(
                        invite: invite,
                        onAccept: () => onAccept(invite),
                        onDecline: () => onDecline(invite),
                      ),
                    for (final entry in _groupedByAge(feed).entries) ...[
                      _TimeHeading(entry.key),
                      for (final notification in entry.value)
                        _NotificationRow(
                          notification: notification,
                          onTap: () => onOpen(notification),
                        ),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Buckets the feed by recency, preserving order within each bucket.
  ///
  /// "3d" alone says little; under a "This week" heading it reads as a position
  /// in a sequence. Insertion order is kept, and the source list is already
  /// newest-first, so the buckets come out in order too.
  Map<String, List<AppNotification>> _groupedByAge(
    List<AppNotification> items,
  ) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final grouped = <String, List<AppNotification>>{};

    for (final item in items) {
      final when = item.createdAt;
      final days = today
          .difference(DateTime(when.year, when.month, when.day))
          .inDays;
      final label = switch (days) {
        <= 0 => 'Today',
        1 => 'Yesterday',
        < 7 => 'This week',
        < 30 => 'This month',
        _ => 'Earlier',
      };
      grouped.putIfAbsent(label, () => []).add(item);
    }
    return grouped;
  }
}

class _PanelHeader extends StatelessWidget {
  const _PanelHeader({required this.unread, required this.onMarkAllRead});

  final int unread;
  final VoidCallback onMarkAllRead;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 13, 10, 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: plannerDivider)),
      ),
      child: Row(
        children: [
          // Flexible, not fixed: the title yields before the count and the
          // action do, since those two carry state and this does not.
          const Flexible(
            child: Text(
              'Notifications',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: plannerInk,
                fontSize: 14,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
              ),
            ),
          ),
          if (unread > 0) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: tint(plannerBlue, 0.12),
                borderRadius: BorderRadius.circular(radiusXs),
              ),
              child: Text(
                '$unread new',
                style: const TextStyle(
                  color: plannerBlue,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
          const Spacer(),
          if (unread > 0)
            TextButton(
              onPressed: onMarkAllRead,
              style: TextButton.styleFrom(
                minimumSize: Size.zero,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                foregroundColor: plannerMuted,
                textStyle: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              child: const Text('Mark all read'),
            ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 34, horizontal: 24),
      child: Column(
        children: [
          _EmptyMark(),
          SizedBox(height: 12),
          Text(
            'You are all caught up',
            style: TextStyle(
              color: plannerText,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: 3),
          Text(
            'Assignments, mentions and due dates land here.',
            textAlign: TextAlign.center,
            style: TextStyle(color: plannerFaint, fontSize: 11.5),
          ),
        ],
      ),
    );
  }
}

class _EmptyMark extends StatelessWidget {
  const _EmptyMark();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: const BoxDecoration(
        color: plannerSurface,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: const Icon(Icons.check_rounded, size: 20, color: plannerFaint),
    );
  }
}

class _TimeHeading extends StatelessWidget {
  const _TimeHeading(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: plannerSurface,
      padding: const EdgeInsets.fromLTRB(16, 7, 16, 6),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
          color: plannerFaint,
          fontSize: 9.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

/// One entry in the feed.
///
/// Unread is carried by a left rail rather than a tinted background: the rail
/// survives the hover highlight, where a wash would be overwritten by it.
class _NotificationRow extends StatefulWidget {
  const _NotificationRow({required this.notification, required this.onTap});

  final AppNotification notification;
  final VoidCallback onTap;

  @override
  State<_NotificationRow> createState() => _NotificationRowState();
}

class _NotificationRowState extends State<_NotificationRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final notification = widget.notification;
    final unread = notification.isUnread;
    final tone = notification.kind.isUrgent ? plannerRed : plannerBlue;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          color: _hovered ? plannerHover : plannerCard,
          // The rail stretches to whatever the text beside it needs, and a Row
          // inside a scroll view has no height of its own to stretch to.
          // IntrinsicHeight measures the content and gives the Row that.
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 3px of colour, full height. Reads as a block of unread items
                // rather than a column of dots to count.
                Container(width: 3, color: unread ? tone : Colors.transparent),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(13, 10, 14, 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: tint(tone, unread ? 0.14 : 0.07),
                            borderRadius: BorderRadius.circular(radiusSm),
                          ),
                          alignment: Alignment.center,
                          child: Icon(
                            notification.kind.icon,
                            size: 14,
                            color: unread ? tone : plannerMuted,
                          ),
                        ),
                        const SizedBox(width: 11),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                notification.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: unread ? plannerInk : plannerText,
                                  fontSize: 12.5,
                                  height: 1.3,
                                  fontWeight: unread
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                ),
                              ),
                              if (notification.body.trim().isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  notification.body,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: plannerMuted,
                                    fontSize: 11.5,
                                    height: 1.25,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 3),
                              Text(
                                notification.age,
                                style: const TextStyle(
                                  color: plannerFaint,
                                  fontSize: 10.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// An invitation, given a card of its own.
///
/// Tinted and bordered so it does not read as another feed row — this is the
/// one thing in the panel that needs an answer before it will go away.
class _InviteCard extends StatelessWidget {
  const _InviteCard({
    required this.invite,
    required this.onAccept,
    required this.onDecline,
  });

  final PendingInvite invite;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tint(plannerBlue, 0.04),
        borderRadius: BorderRadius.circular(radiusMd),
        border: Border.all(color: tint(plannerBlue, 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              // The workspace tile, with the inviter's avatar overlapping it.
              // Two identities in one mark: where you are being asked to go,
              // and who is asking.
              SizedBox(
                width: 40,
                height: 38,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: invite.workspaceColor,
                        borderRadius: BorderRadius.circular(radiusSm),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        invite.workspaceName.trim().isEmpty
                            ? 'W'
                            : invite.workspaceName
                                  .trim()
                                  .characters
                                  .first
                                  .toUpperCase(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (invite.invitedBy != null)
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          padding: const EdgeInsets.all(1.5),
                          decoration: const BoxDecoration(
                            color: plannerCard,
                            shape: BoxShape.circle,
                          ),
                          child: UserAvatar(
                            profile: invite.invitedBy!,
                            size: 17,
                            showTooltip: false,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Who invited you leads, not the label: it is the fact that
                    // decides whether this is expected or came out of nowhere.
                    Text(
                      invite.inviterLine,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: plannerBlue,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      invite.workspaceName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: plannerInk,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                      ),
                    ),
                    Text(
                      invite.contextLine,
                      style: const TextStyle(
                        color: plannerMuted,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // What the role lets you do, spelled out. "Member" alone means
          // nothing to someone who has never used the app.
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
            decoration: BoxDecoration(
              color: plannerCard,
              borderRadius: BorderRadius.circular(radiusSm),
              border: Border.all(color: plannerBorder),
            ),
            child: Row(
              children: [
                Icon(
                  invite.role.canEdit
                      ? Icons.edit_outlined
                      : Icons.visibility_outlined,
                  size: 13,
                  color: plannerMuted,
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: RichText(
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    text: TextSpan(
                      style: const TextStyle(
                        color: plannerMuted,
                        fontSize: 11,
                        height: 1.3,
                      ),
                      children: [
                        TextSpan(
                          text: '${invite.role.label} · ',
                          style: const TextStyle(
                            color: plannerText,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        TextSpan(text: invite.roleSummary),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 11),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 32,
                  child: FilledButton(
                    onPressed: onAccept,
                    style: FilledButton.styleFrom(
                      padding: EdgeInsets.zero,
                      textStyle: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    child: const Text('Accept'),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SizedBox(
                  height: 32,
                  child: OutlinedButton(
                    onPressed: onDecline,
                    style: OutlinedButton.styleFrom(
                      padding: EdgeInsets.zero,
                      foregroundColor: plannerText,
                      side: const BorderSide(color: plannerBorder),
                      textStyle: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    child: const Text('Decline'),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
