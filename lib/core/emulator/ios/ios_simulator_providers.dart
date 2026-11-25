import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'ios_simulator.dart';
import 'ios_simulator_service.dart';

/// iOS 模拟器服务实例 Provider
final iosSimulatorServiceProvider = Provider<IosSimulatorService>((ref) {
  return const IosSimulatorService();
});

/// 首次订阅立即读取，随后低频检查外部启停，取消订阅时停止轮询。
final iosRunningSimulatorCountProvider = StreamProvider.autoDispose<int>((
  ref,
) async* {
  final service = ref.watch(iosSimulatorServiceProvider);
  if (!service.isSupported) {
    yield 0;
    return;
  }
  yield await service.countBootedSimulators();
  yield* Stream<void>.periodic(const Duration(seconds: 5))
      .asyncMap((_) => service.countBootedSimulators());
});

/// iOS 模拟器列表状态 Provider
final iosSimulatorsProvider =
    FutureProvider.autoDispose<List<IosSimulator>>((ref) async {
  final service = ref.watch(iosSimulatorServiceProvider);
  return service.fetchSimulators();
});
