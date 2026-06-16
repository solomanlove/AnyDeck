import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 子窗口方法调用分发器
///
/// 解决多个 Provider/Service 独立调用 `WindowController.setWindowMethodHandler` 时的覆盖冲突问题。
class SubWindowMethodDispatcher {
  static final List<Future<dynamic> Function(MethodCall)> _handlers = [];
  static bool _initialized = false;

  /// 注册一个方法调用处理器
  static void registerHandler(Future<dynamic> Function(MethodCall) handler) {
    if (!_handlers.contains(handler)) {
      _handlers.add(handler);
    }
    _ensureInitialized();
  }

  /// 移除一个方法调用处理器
  static void removeHandler(Future<dynamic> Function(MethodCall) handler) {
    _handlers.remove(handler);
  }

  /// 确保已初始化 WindowController 的全局 methodHandler 监听
  static void _ensureInitialized() {
    if (_initialized) return;
    _initialized = true;
    
    WindowController.fromCurrentEngine().then((controller) {
      controller.setWindowMethodHandler((call) async {
        dynamic lastResult;
        // 使用副本遍历，防止遍历中修改列表
        for (final handler in List.from(_handlers)) {
          try {
            final res = await handler(call);
            if (res != null) {
              lastResult = res;
            }
          } catch (e) {
            debugPrint('Error in sub-window method handler: $e');
          }
        }
        return lastResult;
      });
    }).catchError((e) {
      debugPrint('Failed to initialize SubWindowMethodDispatcher: $e');
    });
  }
}
