// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'file_list_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

FileListModel _$FileListModelFromJson(Map<String, dynamic> json) =>
    FileListModel(
      files: (json['files'] as List<dynamic>?)
          ?.map((e) => FileItemModel.fromJson(e as Map<String, dynamic>))
          .toList(),
    );

Map<String, dynamic> _$FileListModelToJson(FileListModel instance) =>
    <String, dynamic>{
      'files': instance.files,
    };
