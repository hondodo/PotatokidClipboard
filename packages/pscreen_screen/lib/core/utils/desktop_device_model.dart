/// 桌面端设备型号采集入口（Windows / Ubuntu / macOS）。
///
/// 型号只在客户端建立连接时读取一次，随 ws 握手上报；心跳与 report 不携带。
/// Web 平台没有 `dart:io`，编译期切到 stub 返回空串；其余平台走
/// `desktop_device_model_io.dart`，全部是进程内注册表 / sysfs / 插件读取，
/// **不启动任何子进程**（因此打包后的 GUI 应用不会闪出控制台窗口）。
///
/// 返回空串时服务端 `setCommInfo` 会判空跳过，保留设备表里已有的型号。
library;

export 'desktop_device_model_stub.dart'
    if (dart.library.io) 'desktop_device_model_io.dart';
