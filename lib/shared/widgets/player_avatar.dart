import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:eigen_engine/shared/data/models/player_info.dart';

/// Circular avatar for a player, with customizable size.
///
/// Shows a cached network image if [PlayerInfo.avatarUrl] is available,
/// otherwise shows a generic person icon. The same icon is used as placeholder
/// while the image loads and as fallback on error.
class PlayerAvatar extends StatelessWidget {
  const PlayerAvatar({
    super.key,
    required this.playerInfo,
    this.radius = 20,
    this.showBorder = false,
    this.borderColor,
    this.onTap,
  });

  /// The player's public identity data.
  final PlayerInfo playerInfo;

  /// Radius of the circle avatar. Default is 20 (40px diameter).
  final double radius;

  /// Whether to show a border ring around the avatar.
  final bool showBorder;

  /// Color of the border ring. Defaults to the theme's primary color.
  final Color? borderColor;

  /// Optional tap callback. If null, the avatar is non-interactive.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final avatar = _AvatarCircle(
      playerInfo: playerInfo,
      radius: radius,
      showBorder: showBorder,
      borderColor: borderColor ?? Theme.of(context).colorScheme.primary,
    );

    if (onTap != null) {
      return GestureDetector(onTap: onTap, child: avatar);
    }
    return avatar;
  }
}

class _AvatarCircle extends StatelessWidget {
  const _AvatarCircle({
    required this.playerInfo,
    required this.radius,
    required this.showBorder,
    required this.borderColor,
  });

  final PlayerInfo playerInfo;
  final double radius;
  final bool showBorder;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final icon = Icon(
      Icons.person_outline,
      size: radius,
      color: colorScheme.onSurfaceVariant,
    );

    Widget circle = CircleAvatar(
      radius: radius,
      backgroundColor: colorScheme.surfaceContainerHighest,
      child: playerInfo.avatarUrl != null
          ? ClipOval(
              child: CachedNetworkImage(
                imageUrl: playerInfo.avatarUrl!,
                width: radius * 2,
                height: radius * 2,
                fit: BoxFit.cover,
                placeholder: (_, _) => icon,
                errorWidget: (_, _, _) => icon,
              ),
            )
          : icon,
    );

    if (showBorder) {
      circle = Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: borderColor, width: 2.5),
        ),
        padding: const EdgeInsets.all(1.5),
        child: circle,
      );
    }

    return circle;
  }
}
