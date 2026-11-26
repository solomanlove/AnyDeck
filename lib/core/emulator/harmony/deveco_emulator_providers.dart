import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'deveco_emulator.dart';
import 'deveco_emulator_service.dart';

/// DevEco 模拟器服务 Provider
final devecoEmulatorServiceProvider = Provider<DevEcoEmulatorService>((ref) {
  return const DevEcoEmulatorService();
});

/// DevEco 模拟器列表异步状态 Provider
final devecoEmulatorsProvider =
    FutureProvider.autoDispose<List<DevEcoEmulator>>((ref) async {
  final service = ref.watch(devecoEmulatorServiceProvider);
  return service.fetchEmulators();
});

/// 仅在模拟器空态订阅，离开 HarmonyOS 标签后释放探测结果。
final devecoStudioAppPathProvider = FutureProvider.autoDispose<String?>((ref) {
  return ref.watch(devecoEmulatorServiceProvider).findDevEcoStudio();
});
