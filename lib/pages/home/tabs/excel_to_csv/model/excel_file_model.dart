import 'package:file_picker/file_picker.dart';
import 'package:get/get.dart';
import 'package:potatokid_clipboard/app/app_enums.dart';

class ExcelFileModel {
  final PlatformFile file;
  final Rx<ExcelToCsvConvertStatus> convertStatus =
      ExcelToCsvConvertStatus.pending.obs;

  ExcelFileModel({required this.file, ExcelToCsvConvertStatus? status}) {
    convertStatus.value = status ?? ExcelToCsvConvertStatus.pending;
  }

  String get name {
    return file.name;
  }
}
