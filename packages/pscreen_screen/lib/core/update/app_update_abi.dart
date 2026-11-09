// 当前设备 ABI（如 `armeabi-v7a` / `arm64-v8a`），供更新检查（check）按
// 架构下发对应分包，避免设备下到装不了的包，也把下载体积压到三分之一。
//
// - io 平台（Android/桌面）：用 `dart:ffi` 的 `Abi.current()` 取值；
// - web / 不支持的平台：走 stub 返回空串，check 不带 abi，服务端回落
//   通用（universal）包——与"老客户端不传 abi"同一兜底语义。
//
// 条件导入（conditional import）而非直接 import dart:ffi，是为了不让
// web 编译因 dart:ffi 失败。
import 'app_update_abi_stub.dart'
    if (dart.library.io) 'app_update_abi_io.dart' as impl;

/// 设备 ABI 字符串；无法确定时返回 `''`（check 将不携带该参数）。
String get currentUpdateAbi => impl.currentAbi();
