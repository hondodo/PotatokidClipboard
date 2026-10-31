import 'package:intl/intl.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:potatokid_clipboard/app/app_enums.dart';

part 'clipboard_item_model.g.dart';

@JsonSerializable()
class ClipboardItemModel {
  int get id {
    if (sId == null) {
      return 0;
    }
    return int.tryParse('$sId') ?? 0;
  }

  OsType get os {
    if (sOs == null) {
      return OsType.unknown;
    }
    return OsType.fromValue(int.tryParse('$sOs') ?? 0);
  }

  int get createdAtTimestamp {
    if (createdAt == null) {
      return 0;
    }
    return DateTime.parse(createdAt!).millisecondsSinceEpoch;
  }

  String get createdAtFormatted {
    if (createdAt == null) {
      return '';
    }
    return DateFormat('yyyy-MM-dd HH:mm:ss')
        .format(DateTime.parse(createdAt!).toLocal());
  }

  @JsonKey(name: 'id')
  dynamic sId;
  @JsonKey(name: 'username')
  String? username;
  @JsonKey(name: 'content')
  String? content;
  @JsonKey(name: 'os')
  dynamic sOs;
  @JsonKey(name: 'deviceId')
  String? deviceId;
  @JsonKey(name: 'createdAt')
  String? createdAt;

  ClipboardItemModel(
      {this.sId,
      this.username,
      this.content,
      this.sOs,
      this.deviceId,
      this.createdAt});

  factory ClipboardItemModel.fromJson(Map<String, dynamic> json) =>
      _$ClipboardItemModelFromJson(json);
  Map<String, dynamic> toJson() => _$ClipboardItemModelToJson(this);
}
