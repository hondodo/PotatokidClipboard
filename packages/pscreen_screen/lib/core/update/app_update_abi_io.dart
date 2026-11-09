import 'dart:ffi' as ffi;

/// io 平台实现：`Abi.current()` 在 Android 上返回 androidArm /
/// androidArm64 等，映射为 Android 发布惯例的 ABI 名。
String currentAbi() {
  switch (ffi.Abi.current()) {
    case ffi.Abi.androidArm:
      return 'armeabi-v7a';
    case ffi.Abi.androidArm64:
      return 'arm64-v8a';
    case ffi.Abi.androidX64:
      return 'x86_64';
    case ffi.Abi.androidIA32:
      return 'x86';
    default:
      return '';
  }
}
