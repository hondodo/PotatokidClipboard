import 'package:get/get.dart';

enum AppPage {
  clipboard,
  files,
  me,
  settings,
  tools,
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

enum ToolsTab {
  /// 无
  none(0),

  /// Excel转CSV
  excelToCsv(1),

  /// 时间戳转换
  timeStamp(2),

  /// 搜索
  searchWeb(3),

  /// 计算器
  calc(4),
  ;

  final int value;
  const ToolsTab(this.value);

  static ToolsTab fromValue(int value) {
    return ToolsTab.values.firstWhere((element) => element.value == value,
        orElse: () => ToolsTab.none);
  }

  String get text {
    switch (this) {
      case ToolsTab.none:
        return '无'.tr;
      case ToolsTab.excelToCsv:
        return 'Excel转CSV'.tr;
      case ToolsTab.timeStamp:
        return '时间戳转换'.tr;
      case ToolsTab.searchWeb:
        return '浏览器搜索'.tr;
      case ToolsTab.calc:
        return '计算器'.tr;
    }
  }
}

enum TimeStampUnit {
  second(0),
  millisecond(1);

  final int value;
  const TimeStampUnit(this.value);

  static TimeStampUnit fromValue(int value) {
    return TimeStampUnit.values.firstWhere((element) => element.value == value,
        orElse: () => TimeStampUnit.second);
  }

  String get text {
    switch (this) {
      case TimeStampUnit.second:
        return '秒'.tr;
      case TimeStampUnit.millisecond:
        return '毫秒'.tr;
    }
  }

  String get textWithUnit {
    switch (this) {
      case TimeStampUnit.second:
        return '秒(s)'.tr;
      case TimeStampUnit.millisecond:
        return '毫秒(ms)'.tr;
    }
  }
}

enum SearchWebProvider {
  baidu(0),
  google(1),
  bing(2);

  final int value;
  const SearchWebProvider(this.value);

  static SearchWebProvider fromValue(int value) {
    return SearchWebProvider.values.firstWhere(
        (element) => element.value == value,
        orElse: () => SearchWebProvider.baidu);
  }

  String get text {
    switch (this) {
      case SearchWebProvider.baidu:
        return '百度'.tr;
      case SearchWebProvider.google:
        return '谷歌'.tr;
      case SearchWebProvider.bing:
        return '必应'.tr;
    }
  }
}

extension SearchWebProviderExtension on SearchWebProvider {
  String get text {
    switch (this) {
      case SearchWebProvider.baidu:
        return '百度'.tr;
      case SearchWebProvider.google:
        return '谷歌'.tr;
      case SearchWebProvider.bing:
        return '必应'.tr;
    }
  }
}
