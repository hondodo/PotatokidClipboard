// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'clipboard_item_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ClipboardItemModel _$ClipboardItemModelFromJson(Map<String, dynamic> json) =>
    ClipboardItemModel(
      sId: json['id'],
      username: json['username'] as String?,
      content: json['content'] as String?,
      sOs: json['os'],
      deviceId: json['deviceId'] as String?,
      createdAt: json['createdAt'] as String?,
    );

Map<String, dynamic> _$ClipboardItemModelToJson(ClipboardItemModel instance) =>
    <String, dynamic>{
      'id': instance.sId,
      'username': instance.username,
      'content': instance.content,
      'os': instance.sOs,
      'deviceId': instance.deviceId,
      'createdAt': instance.createdAt,
    };
