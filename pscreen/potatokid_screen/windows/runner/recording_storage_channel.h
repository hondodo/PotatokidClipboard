#ifndef RUNNER_RECORDING_STORAGE_CHANNEL_H_
#define RUNNER_RECORDING_STORAGE_CHANNEL_H_

#include <flutter/method_channel.h>

#include <cstdint>
#include <fstream>
#include <map>
#include <memory>
#include <mutex>
#include <string>

// Windows 录制存储通道：与 Android RecordingStorageChannel.kt 的方法名、
// 参数、返回结构完全一致，让 Dart 层 recording_platform.dart 零改动。
//
// 与 Android SAF 的差异：Windows 没有 content:// 与持久化授权，pickDirectory
// 直接返回用户选中的本地目录路径；customUri 就是该路径，write/list/delete
// 全部落在普通文件系统。uri 不以 content:// 开头，Dart 侧 RecordedFile.isSaf
// 自然为 false，回放走 dart:io 本地文件。
//
// 方法：
//  - pickDirectory()                      -> {uri, displayName} 或 null(取消)
//  - freeBytes{location,customUri}        -> int64 可用字节（失败 -1）
//  - openOutputStream{uri,name}           -> int 句柄
//  - appendBytes{handle,bytes:Uint8List}  -> null
//  - closeStream{handle}                  -> null
//  - listFiles{location,customUri}        -> List<{uri,name,size,modified}>
//  - deleteFile{uri,location}             -> bool
class RecordingStorageChannel {
 public:
  // 注册到给定 engine 的 messenger；内部持有 channel 生命周期。
  static void Register(flutter::BinaryMessenger* messenger);

 private:
  RecordingStorageChannel() = default;

  // 打开系统目录选择对话框（IFileDialog / FOS_PICKFOLDERS）。
  // 返回 false 表示取消或失败；成功时填充 out_path（UTF-8）。
  static bool PickDirectory(std::string* out_path);

  // 目标位置可用字节。location=custom 用 custom_path 所在卷；
  // internal 用 Documents 目录所在卷；失败返回 -1。
  static int64_t FreeBytes(const std::string& location,
                           const std::string& custom_path);

  // Documents 目录（对齐 Dart path_provider 的 FOLDERID_Documents）。
  static bool DocumentsPath(std::string* out_path);

  // 写流句柄表：句柄 id -> 打开的输出流（独占访问，回调可能跨平台线程）。
  struct OpenStream {
    std::ofstream stream;
    std::string path;
  };
  static std::mutex streams_mutex_;
  static std::map<int32_t, std::unique_ptr<OpenStream>> streams_;
  static int32_t next_handle_;
};

#endif  // RUNNER_RECORDING_STORAGE_CHANNEL_H_
