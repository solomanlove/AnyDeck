#include "include/scrcpy_flutter/scrcpy_flutter_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "scrcpy_flutter_plugin.h"

void ScrcpyFlutterPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  scrcpy_flutter::ScrcpyFlutterPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
