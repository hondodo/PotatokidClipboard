//
//  Generated file. Do not edit.
//

// clang-format off

#include "generated_plugin_registrant.h"

#include <alog_windows/alog_windows_plugin_c_api.h>
#include <nim_core_v2_windows/nim_core_windows.h>

void RegisterPlugins(flutter::PluginRegistry* registry) {
  AlogWindowsPluginCApiRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("AlogWindowsPluginCApi"));
  NimCoreWindowsRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("NimCoreWindows"));
}
