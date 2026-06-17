import 'package:freezed_annotation/freezed_annotation.dart';

part 'friendship.freezed.dart';
part 'friendship.g.dart';

/// [unknown] is a forward-compatibility sentinel for values a newer server may
/// introduce.
enum RelationshipStatus { pending, accepted, blocked, unknown }

/// A relationship record from `friends_view`.
@freezed
abstract class Friendship with _$Friendship {
  const factory Friendship({
    required String userId,
    required String friendId,
    @JsonKey(unknownEnumValue: RelationshipStatus.unknown)
    required RelationshipStatus status,
    required String initiatedBy,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) = _Friendship;

  factory Friendship.fromJson(Map<String, dynamic> json) =>
      _$FriendshipFromJson(json);
}
