import 'package:intl/intl.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:potatokid_clipboard/utils/file_size_utils.dart';

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

  String get fileSizeFormatted {
    if (size == 0) {
      return '';
    }
    return FileSizeUtils.formatSize(size);
  }

  // 本地字段，下载进度数（一般为已下载文件大小）
  int count = 0;
  // 本地字段，下载总数（一般为文件大小）
  int total = 0;
  // 本地字段，是否已下载
  bool isDownloaded = false;
  // 本地字段，本地文件名
  String? localFilename;
  // 本地字段，是否下载失败
  bool isDownloadFailed = false;

  // 本地字段，是否正在上传
  bool isUploading = false;
  // 本地字段，上传进度数（一般为已上传文件大小）
  int uploadCount = 0;
  // 本地字段，上传总数（一般为文件大小）
  int uploadTotal = 0;
  // 本地字段，是否上传失败
  bool isUploadFailed = false;
  // 本地字段，是否上传完成
  bool isUploadCompleted = false;

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
