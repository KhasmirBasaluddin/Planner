import 'package:flutter/material.dart';

import '../../models/planner_models.dart';
import '../utils/planner_colors.dart';

/// A person's avatar: their picture when they have one, otherwise initials on a
/// color derived from their id, so the same teammate is always the same color.
class UserAvatar extends StatelessWidget {
  const UserAvatar({
    super.key,
    required this.profile,
    this.size = 26,
    this.showTooltip = true,
    this.border,
  });

  final UserProfile profile;
  final double size;
  final bool showTooltip;
  final Color? border;

  @override
  Widget build(BuildContext context) {
    final color = avatarColor(profile.id);
    final avatar = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: border == null ? null : Border.all(color: border!, width: 2),
        image: profile.avatarUrl.isEmpty
            ? null
            : DecorationImage(
                image: NetworkImage(profile.avatarUrl),
                fit: BoxFit.cover,
              ),
      ),
      alignment: Alignment.center,
      child: profile.avatarUrl.isNotEmpty
          ? null
          : Text(
              profile.initials,
              style: TextStyle(
                color: Colors.white,
                // Track the container so initials stay optically centered at
                // any size.
                fontSize: size * 0.38,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
              ),
            ),
    );

    if (!showTooltip) {
      return avatar;
    }
    return Tooltip(message: profile.displayName, child: avatar);
  }
}

/// A row of overlapping avatars with a "+N" chip once the list runs long.
class AvatarStack extends StatelessWidget {
  const AvatarStack({
    super.key,
    required this.profiles,
    this.size = 26,
    this.maxVisible = 4,
  });

  final List<UserProfile> profiles;
  final double size;
  final int maxVisible;

  @override
  Widget build(BuildContext context) {
    if (profiles.isEmpty) {
      return const SizedBox.shrink();
    }

    final visible = profiles.take(maxVisible).toList();
    final overflow = profiles.length - visible.length;
    final overlap = size * 0.32;

    return SizedBox(
      height: size,
      width:
          size +
          (visible.length - 1) * (size - overlap) +
          (overflow > 0 ? size - overlap : 0),
      child: Stack(
        children: [
          for (var i = 0; i < visible.length; i++)
            Positioned(
              left: i * (size - overlap),
              child: UserAvatar(
                profile: visible[i],
                size: size,
                border: Colors.white,
              ),
            ),
          if (overflow > 0)
            Positioned(
              left: visible.length * (size - overlap),
              child: Tooltip(
                message: profiles
                    .skip(maxVisible)
                    .map((p) => p.displayName)
                    .join(', '),
                child: Container(
                  width: size,
                  height: size,
                  decoration: BoxDecoration(
                    color: plannerDivider,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '+$overflow',
                    style: TextStyle(
                      color: plannerMuted,
                      fontSize: size * 0.32,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
