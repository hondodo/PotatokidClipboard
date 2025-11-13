import 'package:intl/intl.dart';
import 'package:json_annotation/json_annotation.dart';

part 'file_item_model.g.dart';

@JsonSerializable()
class FileItemModel {
  String get name {
    if (sName == null) {
      return '';
    }
    return '$sName';
  }

  int get size {
    if (sSize == null) {
      return 0;
    }
    return int.tryParse('$sSize') ?? 0;
  }

  String get uploadTime {
    if (sUploadTime == null) {
      return '';
    }
    return '$sUploadTime';
  }

  DateTime? get uploadTimeDate {
    if (sUploadTime == null) {
      return null;
    }
    return DateTime.parse('$sUploadTime');
  }

  String get uploadTimeFormatted {
    if (uploadTimeDate == null) {
      return '';
    }
    return DateFormat('yyyy-MM-dd HH:mm:ss').format(uploadTimeDate!);
  }

  @JsonKey(name: 'name')
  dynamic sName;
  @JsonKey(name: 'size')
  dynamic sSize;
  @JsonKey(name: 'uploadTime')
  dynamic sUploadTime;

  FileItemModel({this.sName, this.sSize, this.sUploadTime});

  factory FileItemModel.fromJson(Map<String, dynamic> json) =>
      _$FileItemModelFromJson(json);
  Map<String, dynamic> toJson() => _$FileItemModelToJson(this);
}
