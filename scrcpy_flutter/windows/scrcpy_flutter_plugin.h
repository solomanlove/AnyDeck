#ifndef FLUTTER_PLUGIN_SCRCPY_FLUTTER_PLUGIN_H_
#define FLUTTER_PLUGIN_SCRCPY_FLUTTER_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

#include <memory>

namespace scrcpy_flutter {

class ScrcpyFlutterPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

  ScrcpyFlutterPlugin();

  virtual ~ScrcpyFlutterPlugin();

  // Disallow copy and assign.
  ScrcpyFlutterPlugin(const ScrcpyFlutterPlugin&) = delete;
  ScrcpyFlutterPlugin& operator=(const ScrcpyFlutterPlugin&) = delete;

  // Called when a method is called on this plugin's channel from Dart.
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
};

}  // namespace scrcpy_flutter

#endif  // FLUTTER_PLUGIN_SCRCPY_FLUTTER_PLUGIN_H_
