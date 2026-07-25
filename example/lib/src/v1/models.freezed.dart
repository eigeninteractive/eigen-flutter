// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'models.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$RpsRound {

/// Both seats' throws, indexed by seat.
 List<RpsMove> get moves;/// The winning seat, or null when the round was drawn.
 int? get winner;
/// Create a copy of RpsRound
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RpsRoundCopyWith<RpsRound> get copyWith => _$RpsRoundCopyWithImpl<RpsRound>(this as RpsRound, _$identity);

  /// Serializes this RpsRound to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RpsRound&&const DeepCollectionEquality().equals(other.moves, moves)&&(identical(other.winner, winner) || other.winner == winner));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(moves),winner);

@override
String toString() {
  return 'RpsRound(moves: $moves, winner: $winner)';
}


}

/// @nodoc
abstract mixin class $RpsRoundCopyWith<$Res>  {
  factory $RpsRoundCopyWith(RpsRound value, $Res Function(RpsRound) _then) = _$RpsRoundCopyWithImpl;
@useResult
$Res call({
 List<RpsMove> moves, int? winner
});




}
/// @nodoc
class _$RpsRoundCopyWithImpl<$Res>
    implements $RpsRoundCopyWith<$Res> {
  _$RpsRoundCopyWithImpl(this._self, this._then);

  final RpsRound _self;
  final $Res Function(RpsRound) _then;

/// Create a copy of RpsRound
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? moves = null,Object? winner = freezed,}) {
  return _then(_self.copyWith(
moves: null == moves ? _self.moves : moves // ignore: cast_nullable_to_non_nullable
as List<RpsMove>,winner: freezed == winner ? _self.winner : winner // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}

}


/// Adds pattern-matching-related methods to [RpsRound].
extension RpsRoundPatterns on RpsRound {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _RpsRound value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _RpsRound() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _RpsRound value)  $default,){
final _that = this;
switch (_that) {
case _RpsRound():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _RpsRound value)?  $default,){
final _that = this;
switch (_that) {
case _RpsRound() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( List<RpsMove> moves,  int? winner)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _RpsRound() when $default != null:
return $default(_that.moves,_that.winner);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( List<RpsMove> moves,  int? winner)  $default,) {final _that = this;
switch (_that) {
case _RpsRound():
return $default(_that.moves,_that.winner);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( List<RpsMove> moves,  int? winner)?  $default,) {final _that = this;
switch (_that) {
case _RpsRound() when $default != null:
return $default(_that.moves,_that.winner);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _RpsRound implements RpsRound {
  const _RpsRound({required final  List<RpsMove> moves, required this.winner}): _moves = moves;
  factory _RpsRound.fromJson(Map<String, dynamic> json) => _$RpsRoundFromJson(json);

/// Both seats' throws, indexed by seat.
 final  List<RpsMove> _moves;
/// Both seats' throws, indexed by seat.
@override List<RpsMove> get moves {
  if (_moves is EqualUnmodifiableListView) return _moves;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_moves);
}

/// The winning seat, or null when the round was drawn.
@override final  int? winner;

/// Create a copy of RpsRound
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$RpsRoundCopyWith<_RpsRound> get copyWith => __$RpsRoundCopyWithImpl<_RpsRound>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$RpsRoundToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _RpsRound&&const DeepCollectionEquality().equals(other._moves, _moves)&&(identical(other.winner, winner) || other.winner == winner));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(_moves),winner);

@override
String toString() {
  return 'RpsRound(moves: $moves, winner: $winner)';
}


}

/// @nodoc
abstract mixin class _$RpsRoundCopyWith<$Res> implements $RpsRoundCopyWith<$Res> {
  factory _$RpsRoundCopyWith(_RpsRound value, $Res Function(_RpsRound) _then) = __$RpsRoundCopyWithImpl;
@override @useResult
$Res call({
 List<RpsMove> moves, int? winner
});




}
/// @nodoc
class __$RpsRoundCopyWithImpl<$Res>
    implements _$RpsRoundCopyWith<$Res> {
  __$RpsRoundCopyWithImpl(this._self, this._then);

  final _RpsRound _self;
  final $Res Function(_RpsRound) _then;

/// Create a copy of RpsRound
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? moves = null,Object? winner = freezed,}) {
  return _then(_RpsRound(
moves: null == moves ? _self._moves : moves // ignore: cast_nullable_to_non_nullable
as List<RpsMove>,winner: freezed == winner ? _self.winner : winner // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}


}


/// @nodoc
mixin _$RpsObservation {

/// 1-based; increments when a resolved round leaves the match undecided.
 int get round;/// Rounds won, indexed by seat.
 List<int> get wins;/// The previous round's reveal, or null before the first round resolves.
 RpsRound? get lastRound;/// This seat's own commit for the current round, or null if it has not
/// thrown yet. Live play only.
 RpsMove? get yourMove;/// Both seats' commits for the current round. Replay and public viewing
/// only — null during live play, which is exactly the point.
 List<RpsMove?>? get commits;
/// Create a copy of RpsObservation
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RpsObservationCopyWith<RpsObservation> get copyWith => _$RpsObservationCopyWithImpl<RpsObservation>(this as RpsObservation, _$identity);

  /// Serializes this RpsObservation to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RpsObservation&&(identical(other.round, round) || other.round == round)&&const DeepCollectionEquality().equals(other.wins, wins)&&(identical(other.lastRound, lastRound) || other.lastRound == lastRound)&&(identical(other.yourMove, yourMove) || other.yourMove == yourMove)&&const DeepCollectionEquality().equals(other.commits, commits));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,round,const DeepCollectionEquality().hash(wins),lastRound,yourMove,const DeepCollectionEquality().hash(commits));

@override
String toString() {
  return 'RpsObservation(round: $round, wins: $wins, lastRound: $lastRound, yourMove: $yourMove, commits: $commits)';
}


}

/// @nodoc
abstract mixin class $RpsObservationCopyWith<$Res>  {
  factory $RpsObservationCopyWith(RpsObservation value, $Res Function(RpsObservation) _then) = _$RpsObservationCopyWithImpl;
@useResult
$Res call({
 int round, List<int> wins, RpsRound? lastRound, RpsMove? yourMove, List<RpsMove?>? commits
});


$RpsRoundCopyWith<$Res>? get lastRound;

}
/// @nodoc
class _$RpsObservationCopyWithImpl<$Res>
    implements $RpsObservationCopyWith<$Res> {
  _$RpsObservationCopyWithImpl(this._self, this._then);

  final RpsObservation _self;
  final $Res Function(RpsObservation) _then;

/// Create a copy of RpsObservation
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? round = null,Object? wins = null,Object? lastRound = freezed,Object? yourMove = freezed,Object? commits = freezed,}) {
  return _then(_self.copyWith(
round: null == round ? _self.round : round // ignore: cast_nullable_to_non_nullable
as int,wins: null == wins ? _self.wins : wins // ignore: cast_nullable_to_non_nullable
as List<int>,lastRound: freezed == lastRound ? _self.lastRound : lastRound // ignore: cast_nullable_to_non_nullable
as RpsRound?,yourMove: freezed == yourMove ? _self.yourMove : yourMove // ignore: cast_nullable_to_non_nullable
as RpsMove?,commits: freezed == commits ? _self.commits : commits // ignore: cast_nullable_to_non_nullable
as List<RpsMove?>?,
  ));
}
/// Create a copy of RpsObservation
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$RpsRoundCopyWith<$Res>? get lastRound {
    if (_self.lastRound == null) {
    return null;
  }

  return $RpsRoundCopyWith<$Res>(_self.lastRound!, (value) {
    return _then(_self.copyWith(lastRound: value));
  });
}
}


/// Adds pattern-matching-related methods to [RpsObservation].
extension RpsObservationPatterns on RpsObservation {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _RpsObservation value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _RpsObservation() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _RpsObservation value)  $default,){
final _that = this;
switch (_that) {
case _RpsObservation():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _RpsObservation value)?  $default,){
final _that = this;
switch (_that) {
case _RpsObservation() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int round,  List<int> wins,  RpsRound? lastRound,  RpsMove? yourMove,  List<RpsMove?>? commits)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _RpsObservation() when $default != null:
return $default(_that.round,_that.wins,_that.lastRound,_that.yourMove,_that.commits);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int round,  List<int> wins,  RpsRound? lastRound,  RpsMove? yourMove,  List<RpsMove?>? commits)  $default,) {final _that = this;
switch (_that) {
case _RpsObservation():
return $default(_that.round,_that.wins,_that.lastRound,_that.yourMove,_that.commits);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int round,  List<int> wins,  RpsRound? lastRound,  RpsMove? yourMove,  List<RpsMove?>? commits)?  $default,) {final _that = this;
switch (_that) {
case _RpsObservation() when $default != null:
return $default(_that.round,_that.wins,_that.lastRound,_that.yourMove,_that.commits);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _RpsObservation extends RpsObservation {
  const _RpsObservation({required this.round, required final  List<int> wins, required this.lastRound, this.yourMove, final  List<RpsMove?>? commits}): _wins = wins,_commits = commits,super._();
  factory _RpsObservation.fromJson(Map<String, dynamic> json) => _$RpsObservationFromJson(json);

/// 1-based; increments when a resolved round leaves the match undecided.
@override final  int round;
/// Rounds won, indexed by seat.
 final  List<int> _wins;
/// Rounds won, indexed by seat.
@override List<int> get wins {
  if (_wins is EqualUnmodifiableListView) return _wins;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_wins);
}

/// The previous round's reveal, or null before the first round resolves.
@override final  RpsRound? lastRound;
/// This seat's own commit for the current round, or null if it has not
/// thrown yet. Live play only.
@override final  RpsMove? yourMove;
/// Both seats' commits for the current round. Replay and public viewing
/// only — null during live play, which is exactly the point.
 final  List<RpsMove?>? _commits;
/// Both seats' commits for the current round. Replay and public viewing
/// only — null during live play, which is exactly the point.
@override List<RpsMove?>? get commits {
  final value = _commits;
  if (value == null) return null;
  if (_commits is EqualUnmodifiableListView) return _commits;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(value);
}


/// Create a copy of RpsObservation
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$RpsObservationCopyWith<_RpsObservation> get copyWith => __$RpsObservationCopyWithImpl<_RpsObservation>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$RpsObservationToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _RpsObservation&&(identical(other.round, round) || other.round == round)&&const DeepCollectionEquality().equals(other._wins, _wins)&&(identical(other.lastRound, lastRound) || other.lastRound == lastRound)&&(identical(other.yourMove, yourMove) || other.yourMove == yourMove)&&const DeepCollectionEquality().equals(other._commits, _commits));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,round,const DeepCollectionEquality().hash(_wins),lastRound,yourMove,const DeepCollectionEquality().hash(_commits));

@override
String toString() {
  return 'RpsObservation(round: $round, wins: $wins, lastRound: $lastRound, yourMove: $yourMove, commits: $commits)';
}


}

/// @nodoc
abstract mixin class _$RpsObservationCopyWith<$Res> implements $RpsObservationCopyWith<$Res> {
  factory _$RpsObservationCopyWith(_RpsObservation value, $Res Function(_RpsObservation) _then) = __$RpsObservationCopyWithImpl;
@override @useResult
$Res call({
 int round, List<int> wins, RpsRound? lastRound, RpsMove? yourMove, List<RpsMove?>? commits
});


@override $RpsRoundCopyWith<$Res>? get lastRound;

}
/// @nodoc
class __$RpsObservationCopyWithImpl<$Res>
    implements _$RpsObservationCopyWith<$Res> {
  __$RpsObservationCopyWithImpl(this._self, this._then);

  final _RpsObservation _self;
  final $Res Function(_RpsObservation) _then;

/// Create a copy of RpsObservation
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? round = null,Object? wins = null,Object? lastRound = freezed,Object? yourMove = freezed,Object? commits = freezed,}) {
  return _then(_RpsObservation(
round: null == round ? _self.round : round // ignore: cast_nullable_to_non_nullable
as int,wins: null == wins ? _self._wins : wins // ignore: cast_nullable_to_non_nullable
as List<int>,lastRound: freezed == lastRound ? _self.lastRound : lastRound // ignore: cast_nullable_to_non_nullable
as RpsRound?,yourMove: freezed == yourMove ? _self.yourMove : yourMove // ignore: cast_nullable_to_non_nullable
as RpsMove?,commits: freezed == commits ? _self._commits : commits // ignore: cast_nullable_to_non_nullable
as List<RpsMove?>?,
  ));
}

/// Create a copy of RpsObservation
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$RpsRoundCopyWith<$Res>? get lastRound {
    if (_self.lastRound == null) {
    return null;
  }

  return $RpsRoundCopyWith<$Res>(_self.lastRound!, (value) {
    return _then(_self.copyWith(lastRound: value));
  });
}
}


/// @nodoc
mixin _$RpsAction {

 RpsMove get move;
/// Create a copy of RpsAction
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RpsActionCopyWith<RpsAction> get copyWith => _$RpsActionCopyWithImpl<RpsAction>(this as RpsAction, _$identity);

  /// Serializes this RpsAction to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RpsAction&&(identical(other.move, move) || other.move == move));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,move);

@override
String toString() {
  return 'RpsAction(move: $move)';
}


}

/// @nodoc
abstract mixin class $RpsActionCopyWith<$Res>  {
  factory $RpsActionCopyWith(RpsAction value, $Res Function(RpsAction) _then) = _$RpsActionCopyWithImpl;
@useResult
$Res call({
 RpsMove move
});




}
/// @nodoc
class _$RpsActionCopyWithImpl<$Res>
    implements $RpsActionCopyWith<$Res> {
  _$RpsActionCopyWithImpl(this._self, this._then);

  final RpsAction _self;
  final $Res Function(RpsAction) _then;

/// Create a copy of RpsAction
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? move = null,}) {
  return _then(_self.copyWith(
move: null == move ? _self.move : move // ignore: cast_nullable_to_non_nullable
as RpsMove,
  ));
}

}


/// Adds pattern-matching-related methods to [RpsAction].
extension RpsActionPatterns on RpsAction {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _RpsAction value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _RpsAction() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _RpsAction value)  $default,){
final _that = this;
switch (_that) {
case _RpsAction():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _RpsAction value)?  $default,){
final _that = this;
switch (_that) {
case _RpsAction() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( RpsMove move)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _RpsAction() when $default != null:
return $default(_that.move);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( RpsMove move)  $default,) {final _that = this;
switch (_that) {
case _RpsAction():
return $default(_that.move);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( RpsMove move)?  $default,) {final _that = this;
switch (_that) {
case _RpsAction() when $default != null:
return $default(_that.move);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _RpsAction implements RpsAction {
  const _RpsAction({required this.move});
  factory _RpsAction.fromJson(Map<String, dynamic> json) => _$RpsActionFromJson(json);

@override final  RpsMove move;

/// Create a copy of RpsAction
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$RpsActionCopyWith<_RpsAction> get copyWith => __$RpsActionCopyWithImpl<_RpsAction>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$RpsActionToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _RpsAction&&(identical(other.move, move) || other.move == move));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,move);

@override
String toString() {
  return 'RpsAction(move: $move)';
}


}

/// @nodoc
abstract mixin class _$RpsActionCopyWith<$Res> implements $RpsActionCopyWith<$Res> {
  factory _$RpsActionCopyWith(_RpsAction value, $Res Function(_RpsAction) _then) = __$RpsActionCopyWithImpl;
@override @useResult
$Res call({
 RpsMove move
});




}
/// @nodoc
class __$RpsActionCopyWithImpl<$Res>
    implements _$RpsActionCopyWith<$Res> {
  __$RpsActionCopyWithImpl(this._self, this._then);

  final _RpsAction _self;
  final $Res Function(_RpsAction) _then;

/// Create a copy of RpsAction
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? move = null,}) {
  return _then(_RpsAction(
move: null == move ? _self.move : move // ignore: cast_nullable_to_non_nullable
as RpsMove,
  ));
}


}


/// @nodoc
mixin _$RpsConfig {

/// First to this many round wins takes the match.
 int get targetWins;
/// Create a copy of RpsConfig
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RpsConfigCopyWith<RpsConfig> get copyWith => _$RpsConfigCopyWithImpl<RpsConfig>(this as RpsConfig, _$identity);

  /// Serializes this RpsConfig to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RpsConfig&&(identical(other.targetWins, targetWins) || other.targetWins == targetWins));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,targetWins);

@override
String toString() {
  return 'RpsConfig(targetWins: $targetWins)';
}


}

/// @nodoc
abstract mixin class $RpsConfigCopyWith<$Res>  {
  factory $RpsConfigCopyWith(RpsConfig value, $Res Function(RpsConfig) _then) = _$RpsConfigCopyWithImpl;
@useResult
$Res call({
 int targetWins
});




}
/// @nodoc
class _$RpsConfigCopyWithImpl<$Res>
    implements $RpsConfigCopyWith<$Res> {
  _$RpsConfigCopyWithImpl(this._self, this._then);

  final RpsConfig _self;
  final $Res Function(RpsConfig) _then;

/// Create a copy of RpsConfig
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? targetWins = null,}) {
  return _then(_self.copyWith(
targetWins: null == targetWins ? _self.targetWins : targetWins // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [RpsConfig].
extension RpsConfigPatterns on RpsConfig {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _RpsConfig value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _RpsConfig() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _RpsConfig value)  $default,){
final _that = this;
switch (_that) {
case _RpsConfig():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _RpsConfig value)?  $default,){
final _that = this;
switch (_that) {
case _RpsConfig() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int targetWins)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _RpsConfig() when $default != null:
return $default(_that.targetWins);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int targetWins)  $default,) {final _that = this;
switch (_that) {
case _RpsConfig():
return $default(_that.targetWins);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int targetWins)?  $default,) {final _that = this;
switch (_that) {
case _RpsConfig() when $default != null:
return $default(_that.targetWins);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _RpsConfig implements RpsConfig {
  const _RpsConfig({required this.targetWins});
  factory _RpsConfig.fromJson(Map<String, dynamic> json) => _$RpsConfigFromJson(json);

/// First to this many round wins takes the match.
@override final  int targetWins;

/// Create a copy of RpsConfig
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$RpsConfigCopyWith<_RpsConfig> get copyWith => __$RpsConfigCopyWithImpl<_RpsConfig>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$RpsConfigToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _RpsConfig&&(identical(other.targetWins, targetWins) || other.targetWins == targetWins));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,targetWins);

@override
String toString() {
  return 'RpsConfig(targetWins: $targetWins)';
}


}

/// @nodoc
abstract mixin class _$RpsConfigCopyWith<$Res> implements $RpsConfigCopyWith<$Res> {
  factory _$RpsConfigCopyWith(_RpsConfig value, $Res Function(_RpsConfig) _then) = __$RpsConfigCopyWithImpl;
@override @useResult
$Res call({
 int targetWins
});




}
/// @nodoc
class __$RpsConfigCopyWithImpl<$Res>
    implements _$RpsConfigCopyWith<$Res> {
  __$RpsConfigCopyWithImpl(this._self, this._then);

  final _RpsConfig _self;
  final $Res Function(_RpsConfig) _then;

/// Create a copy of RpsConfig
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? targetWins = null,}) {
  return _then(_RpsConfig(
targetWins: null == targetWins ? _self.targetWins : targetWins // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

// dart format on
