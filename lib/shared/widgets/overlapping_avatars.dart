import 'package:flutter/material.dart';
import 'package:eigen_flutter/shared/widgets/player_avatar.dart';

/// An avatar to render: the player's stored avatar URL plus whether it is a
/// bot. A URL rather than an identity model, so callers can build one from any
/// of the identity-carrying wire types without converting between them.
typedef AvatarEntry = ({String? avatarUrl, bool isBot});

/// Displays a row of [PlayerAvatar]s that partially overlap horizontally.
///
/// Used in home screen game cards and lobby cards to show the players
/// in a game. When more than [maxVisible] players exist, the excess
/// count is shown as a "+N" badge.
class OverlappingAvatars extends StatelessWidget {
  const OverlappingAvatars({
    super.key,
    required this.players,
    this.radius = 16,
    this.overlapFraction = 0.3,
    this.maxVisible = 4,
  });

  /// The players to display as overlapping avatars.
  final List<AvatarEntry> players;

  /// Radius of each avatar circle.
  final double radius;

  /// Fraction of the diameter that each subsequent avatar overlaps
  /// the previous one. 0.3 means 30% overlap.
  final double overlapFraction;

  /// Max avatars to show before displaying a "+N" overflow badge.
  final int maxVisible;

  @override
  Widget build(BuildContext context) {
    if (players.isEmpty) return const SizedBox.shrink();

    final colorScheme = Theme.of(context).colorScheme;
    final diameter = radius * 2;
    final step = diameter * (1 - overlapFraction);
    final visible = players.take(maxVisible).toList();
    final overflow = players.length - maxVisible;
    final totalItems = visible.length + (overflow > 0 ? 1 : 0);
    final totalWidth = diameter + (totalItems - 1) * step;

    return SizedBox(
      width: totalWidth,
      height: diameter,
      child: Stack(
        children: [
          for (var i = 0; i < visible.length; i++)
            Positioned(
              left: i * step,
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: colorScheme.surface, width: 2),
                ),
                child: PlayerAvatar(
                  avatarUrl: visible[i].avatarUrl,
                  radius: radius - 2,
                  isBot: visible[i].isBot,
                ),
              ),
            ),
          if (overflow > 0)
            Positioned(
              left: visible.length * step,
              child: Container(
                width: diameter,
                height: diameter,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colorScheme.surfaceContainerHighest,
                  border: Border.all(color: colorScheme.surface, width: 2),
                ),
                alignment: Alignment.center,
                child: Text(
                  '+$overflow',
                  style: TextStyle(
                    fontSize: radius * 0.6,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
