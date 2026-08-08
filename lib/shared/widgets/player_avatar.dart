import 'package:cached_network_image/cached_network_image.dart';
import 'package:eigen_flutter/core/api/avatar_url.dart';
import 'package:eigen_flutter/core/config/app_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Circular avatar for a player, with customizable size.
///
/// Shows a cached network image when [avatarUrl] is set, otherwise a generic
/// person icon. The same icon is used as placeholder while the image loads and
/// as fallback on error.
///
/// Takes the raw URL rather than an identity model because the three shapes
/// that carry one - a player, a friend, and a friend request - are distinct
/// generated types with no common supertype. Passing the field keeps this
/// usable from all three without conversion.
///
/// This is also where a stored avatar URL is resolved: the server may hand back
/// a path relative to the API host rather than an absolute URL, so every
/// avatar in the app is routed through `resolveAvatarUrl` here rather than at
/// each call site.
///
/// When [isBot] is true the avatar is marked as a bot: a small robot badge is
/// overlaid in the bottom-right corner, and the no-photo fallback uses a robot
/// glyph instead of the person glyph. This is the single place bots are made
/// visually distinct from humans, so every surface that renders a [PlayerAvatar]
/// gets the marker for free; pass [isBot] wherever the participant type is known.
class PlayerAvatar extends ConsumerWidget {
  const PlayerAvatar({
    super.key,
    required this.avatarUrl,
    this.radius = 20,
    this.isBot = false,
    this.showBorder = false,
    this.borderColor,
    this.onTap,
  });

  /// The player's stored avatar URL, absolute or relative. Null renders the
  /// fallback icon.
  final String? avatarUrl;

  /// Radius of the circle avatar. Default is 20 (40px diameter).
  final double radius;

  /// Whether this avatar represents a bot rather than a human player.
  final bool isBot;

  /// Whether to show a border ring around the avatar.
  final bool showBorder;

  /// Color of the border ring. Defaults to the theme's primary color.
  final Color? borderColor;

  /// Optional tap callback. If null, the avatar is non-interactive.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final avatar = _AvatarCircle(
      avatarUrl: resolveAvatarUrl(
        avatarUrl,
        ref.watch(appConfigProvider).engine.apiBaseUrl,
      ),
      radius: radius,
      isBot: isBot,
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
    required this.avatarUrl,
    required this.radius,
    required this.isBot,
    required this.showBorder,
    required this.borderColor,
  });

  /// Already resolved to an absolute URL.
  final String? avatarUrl;
  final double radius;
  final bool isBot;
  final bool showBorder;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final icon = Icon(
      isBot ? Icons.smart_toy_outlined : Icons.person_outline,
      size: radius,
      color: colorScheme.onSurfaceVariant,
    );

    Widget circle = CircleAvatar(
      radius: radius,
      backgroundColor: colorScheme.surfaceContainerHighest,
      child: avatarUrl != null
          ? ClipOval(
              child: CachedNetworkImage(
                imageUrl: avatarUrl!,
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

    if (isBot) {
      circle = Stack(
        clipBehavior: Clip.none,
        children: [
          circle,
          _BotBadge(radius: radius),
        ],
      );
    }

    return circle;
  }
}

/// Small robot badge overlaid on the bottom-right of a bot's avatar.
class _BotBadge extends StatelessWidget {
  const _BotBadge({required this.radius});

  final double radius;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final badgeRadius = (radius * 0.42).clamp(7.0, 14.0);

    return Positioned(
      right: -1,
      bottom: -1,
      child: Container(
        width: badgeRadius * 2,
        height: badgeRadius * 2,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: colorScheme.secondaryContainer,
          border: Border.all(color: colorScheme.surface, width: 1.5),
        ),
        alignment: Alignment.center,
        child: Icon(
          Icons.smart_toy,
          size: badgeRadius,
          color: colorScheme.onSecondaryContainer,
        ),
      ),
    );
  }
}
