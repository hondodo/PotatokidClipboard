#include "flutter_window.h"

#include <endpointvolume.h>
#include <mmdeviceapi.h>

#include <flutter/encodable_value.h>
#include <flutter/standard_method_codec.h>

#include <algorithm>
#include <cmath>
#include <optional>

#include "flutter/generated_plugin_registrant.h"

namespace {

constexpr char kVolumeChannelName[] = "potatokid/volume";
constexpr float kVolumeStep = 0.02f;  // 每次 ±2%（对齐 Windows 默认 50 级音量条）

// 取默认播放设备的主音量接口（调用方负责 Release）。
bool GetEndpointVolume(IAudioEndpointVolume** out_volume) {
  IMMDeviceEnumerator* enumerator = nullptr;
  HRESULT hr = CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr,
                                CLSCTX_ALL, IID_PPV_ARGS(&enumerator));
  if (FAILED(hr)) return false;

  IMMDevice* device = nullptr;
  hr = enumerator->GetDefaultAudioEndpoint(eRender, eMultimedia, &device);
  enumerator->Release();
  if (FAILED(hr)) return false;

  hr = device->Activate(__uuidof(IAudioEndpointVolume), CLSCTX_ALL, nullptr,
                        reinterpret_cast<void**>(out_volume));
  device->Release();
  return SUCCEEDED(hr);
}

// volumeUp / volumeDown：读-改-写主音量标量（0.0~1.0），夹紧到边界。
void AdjustVolume(float delta) {
  IAudioEndpointVolume* volume = nullptr;
  if (!GetEndpointVolume(&volume)) return;
  float level = 0.0f;
  volume->GetMasterVolumeLevelScalar(&level);
  level = std::clamp(level + delta, 0.0f, 1.0f);
  volume->SetMasterVolumeLevelScalar(level, nullptr);
  volume->Release();
}

void ToggleMute() {
  IAudioEndpointVolume* volume = nullptr;
  if (!GetEndpointVolume(&volume)) return;
  BOOL muted = FALSE;
  volume->GetMute(&muted);
  volume->SetMute(!muted, nullptr);
  volume->Release();
}

// 当前主音量 0-100 整数（与 Android getStreamVolume/getStreamMaxVolume*100 对齐）。
std::optional<int> GetVolumePercent() {
  IAudioEndpointVolume* volume = nullptr;
  if (!GetEndpointVolume(&volume)) return std::nullopt;
  float level = 0.0f;
  volume->GetMasterVolumeLevelScalar(&level);
  volume->Release();
  return static_cast<int>(
      std::lround(std::clamp(level, 0.0f, 1.0f) * 100.0f));
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());

  // 注册系统音量通道（方法名与 Android 宿主完全一致）。
  volume_channel_ = std::make_unique<
      flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), kVolumeChannelName,
      &flutter::StandardMethodCodec::GetInstance());
  volume_channel_->SetMethodCallHandler(
      [](const flutter::MethodCall<flutter::EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
             result) {
        const std::string& method = call.method_name();
        if (method == "volumeUp") {
          AdjustVolume(+kVolumeStep);
          result->Success();
        } else if (method == "volumeDown") {
          AdjustVolume(-kVolumeStep);
          result->Success();
        } else if (method == "toggleMute") {
          ToggleMute();
          result->Success();
        } else if (method == "getVolume") {
          std::optional<int> percent = GetVolumePercent();
          if (percent.has_value()) {
            result->Success(flutter::EncodableValue(*percent));
          } else {
            result->Error("NO_AUDIO", "No default audio endpoint.");
          }
        } else {
          // getDeviceModel / getAndroidId 等交回 Dart 兜底（与 Android 的
          // notImplemented 行为一致，Dart 侧 catch 后走默认值）。
          result->NotImplemented();
        }
      });

  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  volume_channel_.reset();
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
