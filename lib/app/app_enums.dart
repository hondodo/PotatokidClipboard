enum AppPage {
  clipboard,
  me,
  settings,
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
