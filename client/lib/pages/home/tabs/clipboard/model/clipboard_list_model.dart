import 'package:json_annotation/json_annotation.dart';
import 'package:potatokid_clipboard/pages/home/tabs/clipboard/model/clipboard_item_model.dart';

part 'clipboard_list_model.g.dart';

@JsonSerializable()
class ClipboardListModel {
  @JsonKey(name: 'clipboards')
  List<ClipboardItemModel>? clipboards;

  ClipboardListModel({this.clipboards});

  factory ClipboardListModel.fromJson(Map<String, dynamic> json) =>
      _$ClipboardListModelFromJson(json);
  Map<String, dynamic> toJson() => _$ClipboardListModelToJson(this);
}
