import 'package:get/get.dart';

enum AppPage {
  clipboard,
  files,
  me,
  settings,
  excelToCsv,
}

enum OsType {
  unknown(0),
  ios(1),
  android(2),
  windows(3),
  linux(4),
  macos(5);

  final int value;
  const OsType(this.value);

  static OsType fromValue(int value) {
    // 慢
    return OsType.values.firstWhere((element) => element.value == value,
        orElse: () => OsType.unknown);
  }
}

enum FileTab {
  upload(0),
  download(1);

  final int value;
  const FileTab(this.value);

  static FileTab fromValue(int value) {
    return FileTab.values.firstWhere((element) => element.value == value,
        orElse: () => FileTab.upload);
  }

  String get name {
    switch (this) {
      case FileTab.upload:
        return '上传'.tr;
      case FileTab.download:
        return '下载'.tr;
    }
  }
}

enum TrayIconState {
  on,
  off,
}

enum ExcelToCsvConvertStatus {
  pending,
  converting,
  completed,
  failed,
}

extension ExcelToCsvConvertStatusExtension on ExcelToCsvConvertStatus {
  String get text {
    switch (this) {
      case ExcelToCsvConvertStatus.pending:
        return '待转换'.tr;
      case ExcelToCsvConvertStatus.converting:
        return '转换中'.tr;
      case ExcelToCsvConvertStatus.completed:
        return '转换完成'.tr;
      case ExcelToCsvConvertStatus.failed:
        return '转换失败'.tr;
    }
  }
}
