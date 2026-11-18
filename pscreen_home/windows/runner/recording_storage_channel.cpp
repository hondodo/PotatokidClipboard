#include "recording_storage_channel.h"

#include <flutter/encodable_value.h>
#include <flutter/standard_method_codec.h>

#include <objbase.h>
#include <shlobj.h>
#include <shobjidl.h>
#include <windows.h>

#include <algorithm>
#include <cctype>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <map>
#include <memory>
#include <mutex>
#include <string>

namespace {

constexpr char kChannelName[] = "potatokid/recording";

// 进程级持有 channel（MethodChannel 析构不注销 handler，但保住对象更规范）。
std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> g_channel;

// ---------- UTF-8 <-> UTF-16 ----------
std::wstring Utf8ToWide(const std::string& text) {
  if (text.empty()) return std::wstring();
  const int size = MultiByteToWideChar(CP_UTF8, 0, text.c_str(), -1, nullptr, 0);
  if (size <= 0) return std::wstring();
  std::wstring out(static_cast<size_t>(size), L'\0');
  MultiByteToWideChar(CP_UTF8, 0, text.c_str(), -1, out.data(), size);
  out.resize(static_cast<size_t>(size - 1));  // 去掉结尾 \0
  return out;
}

std::string WideToUtf8(const std::wstring& text) {
  if (text.empty()) return std::string();
  const int size =
      WideCharToMultiByte(CP_UTF8, 0, text.c_str(), -1, nullptr, 0, nullptr, nullptr);
  if (size <= 0) return std::string();
  std::string out(static_cast<size_t>(size), '\0');
  WideCharToMultiByte(CP_UTF8, 0, text.c_str(), -1, out.data(), size, nullptr, nullptr);
  out.resize(static_cast<size_t>(size - 1));
  return out;
}

// 把路径末尾的 / 或 \ 去掉（root 如 C:\ 保留）。
std::wstring TrimTrailingSep(std::wstring path) {
  while (path.size() > 3 &&
         (path.back() == L'\\' || path.back() == L'/')) {
    path.pop_back();
  }
  return path;
}

// 取路径最后一段作为展示名。
std::string BaseNameUtf8(const std::wstring& path) {
  const std::wstring trimmed = TrimTrailingSep(path);
  const size_t pos = trimmed.find_last_of(L"\\/");
  const std::wstring name =
      pos == std::wstring::npos ? trimmed : trimmed.substr(pos + 1);
  return WideToUtf8(name.empty() ? trimmed : name);
}

// 从 MethodCall 参数里安全取字符串；缺失返回空串。
std::string ArgString(
    const flutter::EncodableValue* args,
    const std::string& key) {
  if (args == nullptr) return std::string();
  if (const auto* map = std::get_if<flutter::EncodableMap>(args)) {
    const auto it = map->find(flutter::EncodableValue(key));
    if (it != map->end()) {
      if (const auto* s = std::get_if<std::string>(&it->second)) {
        return *s;
      }
    }
  }
  return std::string();
}

int32_t ArgInt(const flutter::EncodableValue* args, const std::string& key) {
  if (args == nullptr) return 0;
  if (const auto* map = std::get_if<flutter::EncodableMap>(args)) {
    const auto it = map->find(flutter::EncodableValue(key));
    if (it != map->end()) {
      if (const auto* v = std::get_if<int32_t>(&it->second)) return *v;
      if (const auto* v = std::get_if<int64_t>(&it->second)) {
        return static_cast<int32_t>(*v);
      }
    }
  }
  return 0;
}

std::vector<uint8_t> ArgBytes(
    const flutter::EncodableValue* args,
    const std::string& key) {
  if (args == nullptr) return {};
  if (const auto* map = std::get_if<flutter::EncodableMap>(args)) {
    const auto it = map->find(flutter::EncodableValue(key));
    if (it != map->end()) {
      if (const auto* v = std::get_if<std::vector<uint8_t>>(&it->second)) {
        return *v;
      }
    }
  }
  return {};
}

}  // namespace

// 静态成员定义
std::mutex RecordingStorageChannel::streams_mutex_;
std::map<int32_t, std::unique_ptr<RecordingStorageChannel::OpenStream>>
    RecordingStorageChannel::streams_;
int32_t RecordingStorageChannel::next_handle_ = 1;

bool RecordingStorageChannel::DocumentsPath(std::string* out_path) {
  PWSTR wide = nullptr;
  const HRESULT hr = SHGetKnownFolderPath(FOLDERID_Documents, 0, nullptr, &wide);
  if (FAILED(hr) || wide == nullptr) return false;
  *out_path = WideToUtf8(std::wstring(wide));
  CoTaskMemFree(wide);
  return !out_path->empty();
}

bool RecordingStorageChannel::PickDirectory(std::string* out_path) {
  // IFileDialog 要求调用线程处于 STA。Flutter Windows 主线程默认初始化为
  // STA，但保险起见显式初始化；S_FALSE 表示已是 STA（视为成功）。
  const HRESULT co = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
  const bool need_uninit = SUCCEEDED(co);
  bool ok = false;
  IFileDialog* dialog = nullptr;
  do {
    const HRESULT hr = CoCreateInstance(CLSID_FileOpenDialog, nullptr,
                                        CLSCTX_INPROC_SERVER,
                                        IID_PPV_ARGS(&dialog));
    if (FAILED(hr)) break;

    FILEOPENDIALOGOPTIONS options = 0;
    dialog->GetOptions(&options);
    dialog->SetOptions(options | FOS_PICKFOLDERS | FOS_PATHMUSTEXIST);

    if (FAILED(dialog->Show(nullptr))) break;

    IShellItem* item = nullptr;
    if (FAILED(dialog->GetResult(&item)) || item == nullptr) break;
    PWSTR wide = nullptr;
    const HRESULT path_hr =
        item->GetDisplayName(SIGDN_FILESYSPATH, &wide);
    if (SUCCEEDED(path_hr) && wide != nullptr) {
      *out_path = WideToUtf8(std::wstring(wide));
      CoTaskMemFree(wide);
      ok = !out_path->empty();
    }
    item->Release();
  } while (false);

  if (dialog != nullptr) dialog->Release();
  if (need_uninit) CoUninitialize();
  return ok;
}

int64_t RecordingStorageChannel::FreeBytes(const std::string& location,
                                           const std::string& custom_path) {
  std::string target = custom_path;
  if (location != "custom" || target.empty()) {
    if (!DocumentsPath(&target)) return -1;
  }
  const std::wstring path = TrimTrailingSep(Utf8ToWide(target));
  ULARGE_INTEGER free_bytes = {{0, 0}};
  if (!GetDiskFreeSpaceExW(path.c_str(), &free_bytes, nullptr, nullptr)) {
    return -1;
  }
  return static_cast<int64_t>(free_bytes.QuadPart);
}

void RecordingStorageChannel::Register(flutter::BinaryMessenger* messenger) {
  g_channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, kChannelName, &flutter::StandardMethodCodec::GetInstance());

  g_channel->SetMethodCallHandler(
      [](const flutter::MethodCall<flutter::EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        const std::string& method = call.method_name();
        const flutter::EncodableValue* args = call.arguments();

        // ---- pickDirectory -> {uri, displayName} | null ----
        if (method == "pickDirectory") {
          std::string path;
          if (!PickDirectory(&path)) {
            result->Success();  // null：用户取消
            return;
          }
          result->Success(flutter::EncodableValue(flutter::EncodableMap{
              {flutter::EncodableValue("uri"), flutter::EncodableValue(path)},
              {flutter::EncodableValue("displayName"),
               flutter::EncodableValue(BaseNameUtf8(Utf8ToWide(path)))},
          }));
          return;
        }

        // ---- freeBytes -> int64 ----
        if (method == "freeBytes") {
          const std::string location = ArgString(args, "location");
          const std::string custom_uri = ArgString(args, "customUri");
          result->Success(flutter::EncodableValue(
              FreeBytes(location, custom_uri)));
          return;
        }

        // ---- openOutputStream{uri,name} -> int handle ----
        if (method == "openOutputStream") {
          const std::string uri = ArgString(args, "uri");
          const std::string name = ArgString(args, "name");
          if (uri.empty() || name.empty()) {
            result->Error("invalid_arguments", "uri/name 为空");
            return;
          }
          std::error_code ec;
          std::filesystem::path file =
              std::filesystem::path(Utf8ToWide(uri)) / Utf8ToWide(name);
          std::filesystem::create_directories(file.parent_path(), ec);
          auto stream = std::make_unique<OpenStream>();
          stream->path = WideToUtf8(file.wstring());
          stream->stream.open(file, std::ios::binary | std::ios::trunc);
          if (!stream->stream.is_open()) {
            result->Error("open_failed", "无法创建文件");
            return;
          }
          std::lock_guard<std::mutex> lock(streams_mutex_);
          const int32_t handle = next_handle_++;
          streams_[handle] = std::move(stream);
          result->Success(flutter::EncodableValue(handle));
          return;
        }

        // ---- appendBytes{handle,bytes} -> null ----
        if (method == "appendBytes") {
          const int32_t handle = ArgInt(args, "handle");
          const std::vector<uint8_t> bytes = ArgBytes(args, "bytes");
          std::lock_guard<std::mutex> lock(streams_mutex_);
          const auto it = streams_.find(handle);
          if (it == streams_.end() || !it->second->stream.is_open()) {
            result->Error("write_failed", "句柄无效");
            return;
          }
          it->second->stream.write(
              reinterpret_cast<const char*>(bytes.data()),
              static_cast<std::streamsize>(bytes.size()));
          if (!it->second->stream.good()) {
            result->Error("write_failed", "写入失败");
            return;
          }
          result->Success();
          return;
        }

        // ---- closeStream{handle} -> null ----
        if (method == "closeStream") {
          const int32_t handle = ArgInt(args, "handle");
          std::lock_guard<std::mutex> lock(streams_mutex_);
          const auto it = streams_.find(handle);
          if (it == streams_.end()) {
            result->Error("close_failed", "句柄无效");
            return;
          }
          it->second->stream.close();
          streams_.erase(it);
          result->Success();
          return;
        }

        // ---- listFiles{location,customUri} -> List<map> ----
        if (method == "listFiles") {
          const std::string location = ArgString(args, "location");
          const std::string custom_uri = ArgString(args, "customUri");
          std::string dir_path = custom_uri;
          if (location != "custom" || dir_path.empty()) {
            if (!DocumentsPath(&dir_path)) {
              result->Success(flutter::EncodableValue(flutter::EncodableList{}));
              return;
            }
            dir_path += "\\recordings";
          }
          flutter::EncodableList files;
          std::error_code ec;
          const std::filesystem::path dir(Utf8ToWide(dir_path));
          if (std::filesystem::exists(dir, ec)) {
            for (std::filesystem::directory_iterator it(dir, ec), end;
                 !ec && it != end; it.increment(ec)) {
              const auto& entry = *it;
              std::error_code file_ec;
              if (!entry.is_regular_file(file_ec)) continue;
              const std::string ext = entry.path().extension().wstring().empty()
                                          ? std::string()
                                          : WideToUtf8(entry.path().extension().wstring());
              std::string lower = ext;
              std::transform(lower.begin(), lower.end(), lower.begin(),
                             [](unsigned char c) { return static_cast<char>(::tolower(c)); });
              if (lower != ".ts") continue;
              // FILETIME(1601 起 100ns) -> Unix 毫秒(1970 起)，避免 C++20
              // clock_cast（Flutter Windows 默认 C++17）。
              int64_t modified_ms = 0;
              WIN32_FILE_ATTRIBUTE_DATA attr = {};
              if (GetFileAttributesExW(entry.path().c_str(),
                                       GetFileExInfoStandard, &attr)) {
                ULARGE_INTEGER ft = {};
                ft.LowPart = attr.ftLastWriteTime.dwLowDateTime;
                ft.HighPart = attr.ftLastWriteTime.dwHighDateTime;
                constexpr int64_t kEpochDiff100ns = 116444736000000000LL;
                const int64_t ticks =
                    static_cast<int64_t>(ft.QuadPart) - kEpochDiff100ns;
                modified_ms = ticks > 0 ? ticks / 10000 : 0;
              }
              files.push_back(flutter::EncodableValue(flutter::EncodableMap{
                  {flutter::EncodableValue("uri"),
                   flutter::EncodableValue(WideToUtf8(entry.path().wstring()))},
                  {flutter::EncodableValue("name"),
                   flutter::EncodableValue(WideToUtf8(entry.path().filename().wstring()))},
                  {flutter::EncodableValue("size"),
                   flutter::EncodableValue(static_cast<int64_t>(entry.file_size(file_ec)))},
                  {flutter::EncodableValue("modified"),
                   flutter::EncodableValue(modified_ms)},
              }));
            }
          }
          result->Success(flutter::EncodableValue(std::move(files)));
          return;
        }

        // ---- deleteFile{uri,location} -> bool ----
        if (method == "deleteFile") {
          const std::string uri = ArgString(args, "uri");
          if (uri.empty()) {
            result->Error("invalid_arguments", "uri 为空");
            return;
          }
          std::error_code ec;
          const std::filesystem::path file(Utf8ToWide(uri));
          if (!std::filesystem::exists(file, ec)) {
            result->Success(flutter::EncodableValue(true));
            return;
          }
          const bool ok = std::filesystem::remove(file, ec) && !ec;
          result->Success(flutter::EncodableValue(ok));
          return;
        }

        result->NotImplemented();
      });
}
