// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'file_item_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

FileItemModel _$FileItemModelFromJson(Map<String, dynamic> json) =>
    FileItemModel(
      sName: json['name'],
      sSize: json['size'],
      sUploadTime: json['uploadTime'],
    );

Map<String, dynamic> _$FileItemModelToJson(FileItemModel instance) =>
    <String, dynamic>{
      'name': instance.sName,
      'size': instance.sSize,
      'uploadTime': instance.sUploadTime,
    };
