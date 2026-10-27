import 'package:flutter/material.dart';

import '../../app/widget/app_toast.dart';

/// Dashboard 旧轻提示兼容入口；实际渲染统一委托给 [AppToast]。
class DashboardSnack {
  const DashboardSnack._();

  static void show(
    BuildContext context,
    String message, {
    bool isError = false,
  }) {
    AppToast.show(
      context,
      message,
      type: isError ? AppToastType.error : AppToastType.success,
    );
  }
}
