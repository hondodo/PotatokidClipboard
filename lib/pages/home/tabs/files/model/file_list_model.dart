import 'package:json_annotation/json_annotation.dart';
import 'package:potatokid_clipboard/pages/home/tabs/files/model/file_item_model.dart';

part 'file_list_model.g.dart';

@JsonSerializable()
class FileListModel {
  @JsonKey(name: 'files')
  List<FileItemModel>? files;

  FileListModel({this.files});

  factory FileListModel.fromJson(Map<String, dynamic> json) =>
      _$FileListModelFromJson(json);
  Map<String, dynamic> toJson() => _$FileListModelToJson(this);
}
