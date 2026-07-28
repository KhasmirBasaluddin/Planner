import 'package:flutter/material.dart';

import '../../../models/planner_models.dart';
import '../../../shared/utils/planner_colors.dart';

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
    required this.onAcceptInvite,
    required this.onDeclineInvite,
  });

  final String fullName;
  final String email;
  final List<PendingInvite> invites;
  final ValueChanged<PendingInvite> onAcceptInvite;
  final ValueChanged<PendingInvite> onDeclineInvite;

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
            onAccept: onAcceptInvite,
            onDecline: onDeclineInvite,
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

/// A bell with a count, opening the list of pending invitations.
///
/// This is what makes invites visible at all: previously one was only claimed
/// silently on the next sign-in, so the invited person had no idea it existed.
class _NotificationBell extends StatelessWidget {
  const _NotificationBell({
    required this.invites,
    required this.onAccept,
    required this.onDecline,
  });

  final List<PendingInvite> invites;
  final ValueChanged<PendingInvite> onAccept;
  final ValueChanged<PendingInvite> onDecline;

  @override
  Widget build(BuildContext context) {
    final count = invites.length;

    return PopupMenuButton<void>(
      tooltip: count == 0
          ? 'No notifications'
          : '$count pending invitation${count == 1 ? '' : 's'}',
      offset: const Offset(0, 42),
      constraints: const BoxConstraints(minWidth: 320, maxWidth: 380),
      itemBuilder: (context) {
        if (invites.isEmpty) {
          return [
            const PopupMenuItem<void>(
              enabled: false,
              height: 76,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.notifications_none_rounded,
                      size: 20,
                      color: plannerFaint,
                    ),
                    SizedBox(height: 6),
                    Text(
                      'Nothing new',
                      style: TextStyle(color: plannerMuted, fontSize: 12.5),
                    ),
                  ],
                ),
              ),
            ),
          ];
        }

        return [
          const PopupMenuItem<void>(
            enabled: false,
            height: 32,
            child: Text(
              'INVITATIONS',
              style: TextStyle(
                color: plannerFaint,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.7,
              ),
            ),
          ),
          for (final invite in invites)
            PopupMenuItem<void>(
              enabled: false,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              height: 96,
              child: _InviteTile(
                invite: invite,
                onAccept: () {
                  Navigator.of(context).pop();
                  onAccept(invite);
                },
                onDecline: () {
                  Navigator.of(context).pop();
                  onDecline(invite);
                },
              ),
            ),
        ];
      },
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
                    '$count',
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
    );
  }
}

class _InviteTile extends StatelessWidget {
  const _InviteTile({
    required this.invite,
    required this.onAccept,
    required this.onDecline,
  });

  final PendingInvite invite;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: invite.workspaceColor,
                borderRadius: BorderRadius.circular(radiusSm),
              ),
              alignment: Alignment.center,
              child: Text(
                invite.workspaceName.trim().isEmpty
                    ? 'W'
                    : invite.workspaceName.trim().characters.first
                          .toUpperCase(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    invite.workspaceName,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: plannerInk,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    'Invited as ${invite.role.label.toLowerCase()}',
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
        Row(
          children: [
            SizedBox(
              height: 30,
              child: FilledButton(
                onPressed: onAccept,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  textStyle: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                child: const Text('Accept'),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              height: 30,
              child: OutlinedButton(
                onPressed: onDecline,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  textStyle: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                child: const Text('Decline'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
