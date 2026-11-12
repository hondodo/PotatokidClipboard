/// Web 平台没有 `dart:io`，也不存在「本机硬件型号」概念，保持空串。
Future<String> desktopDeviceModel() async => '';
