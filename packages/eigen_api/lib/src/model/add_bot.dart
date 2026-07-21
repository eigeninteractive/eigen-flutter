//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:copy_with_extension/copy_with_extension.dart';
import 'package:json_annotation/json_annotation.dart';

part 'add_bot.g.dart';


@CopyWith()
@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class AddBot {
  /// Returns a new [AddBot] instance.
  AddBot({

    required  this.botId,

     this.commandId,
  });

  @JsonKey(
    
    name: r'bot_id',
    required: true,
    includeIfNull: false,
  )


  final String botId;



  @JsonKey(
    
    name: r'command_id',
    required: false,
    includeIfNull: false,
  )


  final String? commandId;





    @override
    bool operator ==(Object other) => identical(this, other) || other is AddBot &&
      other.botId == botId &&
      other.commandId == commandId;

    @override
    int get hashCode =>
        botId.hashCode +
        commandId.hashCode;

  factory AddBot.fromJson(Map<String, dynamic> json) => _$AddBotFromJson(json);

  Map<String, dynamic> toJson() => _$AddBotToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }

}

