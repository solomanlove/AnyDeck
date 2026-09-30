import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'ios_simulator.dart';
import 'ios_simulator_service.dart';

/// iOS 模拟器服务实例 Provider
final iosSimulatorServiceProvider = Provider<IosSimulatorService>((ref) {
  return const IosSimulatorService();
});

/// iOS 模拟器列表状态 Provider
final iosSimulatorsProvider =
    FutureProvider.autoDispose<List<IosSimulator>>((ref) async {
  final service = ref.watch(iosSimulatorServiceProvider);
  return service.fetchSimulators();
});
