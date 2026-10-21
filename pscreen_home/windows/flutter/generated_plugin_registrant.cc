//
//  Generated file. Do not edit.
//

// clang-format off

#include "generated_plugin_registrant.h"

#include <alog_windows/alog_windows_plugin_c_api.h>
#include <connectivity_plus/connectivity_plus_windows_plugin.h>
#include <media_kit_libs_windows_video/media_kit_libs_windows_video_plugin_c_api.h>
#include <media_kit_video/media_kit_video_plugin_c_api.h>
#include <nim_core_v2_windows/nim_core_windows.h>

void RegisterPlugins(flutter::PluginRegistry* registry) {
  AlogWindowsPluginCApiRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("AlogWindowsPluginCApi"));
  ConnectivityPlusWindowsPluginRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("ConnectivityPlusWindowsPlugin"));
  MediaKitLibsWindowsVideoPluginCApiRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("MediaKitLibsWindowsVideoPluginCApi"));
  MediaKitVideoPluginCApiRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("MediaKitVideoPluginCApi"));
  NimCoreWindowsRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("NimCoreWindows"));
}
