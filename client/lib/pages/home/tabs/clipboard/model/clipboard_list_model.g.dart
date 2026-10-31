// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'clipboard_list_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ClipboardListModel _$ClipboardListModelFromJson(Map<String, dynamic> json) =>
    ClipboardListModel(
      clipboards: (json['clipboards'] as List<dynamic>?)
          ?.map((e) => ClipboardItemModel.fromJson(e as Map<String, dynamic>))
          .toList(),
    );

Map<String, dynamic> _$ClipboardListModelToJson(ClipboardListModel instance) =>
    <String, dynamic>{
      'clipboards': instance.clipboards,
    };
