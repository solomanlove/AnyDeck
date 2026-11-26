import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'emulator_ide_service.dart';

/// Android Studio 与 Xcode 的宿主机探测和打开服务。
final emulatorIdeServiceProvider = Provider<EmulatorIdeService>((ref) {
  return const EmulatorIdeService();
});

/// 只在 Android 模拟器空态订阅，离开标签后释放结果。
final androidStudioAppPathProvider = FutureProvider.autoDispose<String?>((ref) {
  return ref.watch(emulatorIdeServiceProvider).findAndroidStudio();
});

/// 只在 macOS 的 iOS 模拟器空态订阅，离开标签后释放结果。
final xcodeAppPathProvider = FutureProvider.autoDispose<String?>((ref) {
  return ref.watch(emulatorIdeServiceProvider).findXcode();
});
