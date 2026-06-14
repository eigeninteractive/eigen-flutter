import 'package:freezed_annotation/freezed_annotation.dart';

part 'friendship.freezed.dart';
part 'friendship.g.dart';

enum RelationshipStatus { pending, accepted, blocked }

/// A relationship record from `friends_view`.
@freezed
abstract class Friendship with _$Friendship {
  const factory Friendship({
    required String userId,
    required String friendId,
    required RelationshipStatus status,
    required String initiatedBy,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) = _Friendship;

  factory Friendship.fromJson(Map<String, dynamic> json) =>
      _$FriendshipFromJson(json);
}
