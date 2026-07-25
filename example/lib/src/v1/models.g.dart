// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'models.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_RpsRound _$RpsRoundFromJson(Map<String, dynamic> json) =>
    $checkedCreate('_RpsRound', json, ($checkedConvert) {
      final val = _RpsRound(
        moves: $checkedConvert(
          'moves',
          (v) => (v as List<dynamic>)
              .map((e) => $enumDecode(_$RpsMoveEnumMap, e))
              .toList(),
        ),
        winner: $checkedConvert('winner', (v) => (v as num?)?.toInt()),
      );
      return val;
    });

Map<String, dynamic> _$RpsRoundToJson(_RpsRound instance) => <String, dynamic>{
  'moves': instance.moves.map((e) => _$RpsMoveEnumMap[e]!).toList(),
  'winner': instance.winner,
};

const _$RpsMoveEnumMap = {
  RpsMove.rock: 'rock',
  RpsMove.paper: 'paper',
  RpsMove.scissors: 'scissors',
};

_RpsObservation _$RpsObservationFromJson(Map<String, dynamic> json) =>
    $checkedCreate('_RpsObservation', json, ($checkedConvert) {
      final val = _RpsObservation(
        round: $checkedConvert('round', (v) => (v as num).toInt()),
        wins: $checkedConvert(
          'wins',
          (v) => (v as List<dynamic>).map((e) => (e as num).toInt()).toList(),
        ),
        lastRound: $checkedConvert(
          'lastRound',
          (v) =>
              v == null ? null : RpsRound.fromJson(v as Map<String, dynamic>),
        ),
        yourMove: $checkedConvert(
          'yourMove',
          (v) => $enumDecodeNullable(_$RpsMoveEnumMap, v),
        ),
        commits: $checkedConvert(
          'commits',
          (v) => (v as List<dynamic>?)
              ?.map((e) => $enumDecodeNullable(_$RpsMoveEnumMap, e))
              .toList(),
        ),
      );
      return val;
    });

Map<String, dynamic> _$RpsObservationToJson(_RpsObservation instance) =>
    <String, dynamic>{
      'round': instance.round,
      'wins': instance.wins,
      'lastRound': instance.lastRound?.toJson(),
      'yourMove': _$RpsMoveEnumMap[instance.yourMove],
      'commits': instance.commits?.map((e) => _$RpsMoveEnumMap[e]).toList(),
    };

_RpsAction _$RpsActionFromJson(Map<String, dynamic> json) =>
    $checkedCreate('_RpsAction', json, ($checkedConvert) {
      final val = _RpsAction(
        move: $checkedConvert('move', (v) => $enumDecode(_$RpsMoveEnumMap, v)),
      );
      return val;
    });

Map<String, dynamic> _$RpsActionToJson(_RpsAction instance) =>
    <String, dynamic>{'move': _$RpsMoveEnumMap[instance.move]!};

_RpsConfig _$RpsConfigFromJson(Map<String, dynamic> json) =>
    $checkedCreate('_RpsConfig', json, ($checkedConvert) {
      final val = _RpsConfig(
        targetWins: $checkedConvert('targetWins', (v) => (v as num).toInt()),
      );
      return val;
    });

Map<String, dynamic> _$RpsConfigToJson(_RpsConfig instance) =>
    <String, dynamic>{'targetWins': instance.targetWins};
