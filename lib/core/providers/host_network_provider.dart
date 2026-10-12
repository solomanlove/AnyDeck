import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../network/host_network_info.dart';
import '../network/host_network_service.dart';

/// 独立服务入口，便于测试网络切换和权限失败。
final hostNetworkServiceProvider = Provider((ref) => HostNetworkService());

/// 仅提供当前电脑主机的网络信息，不进行自动定时轮询，由用户手动触发刷新。
final hostNetworkProvider =
    AsyncNotifierProvider.autoDispose<HostNetworkNotifier, HostNetworkInfo>(
      HostNetworkNotifier.new,
    );

class HostNetworkNotifier extends AsyncNotifier<HostNetworkInfo> {
  bool _reading = false;

  @override
  Future<HostNetworkInfo> build() async {
    final service = ref.watch(hostNetworkServiceProvider);
    return service.read();
  }

  /// 串行刷新避免重复并发，销毁后丢弃异步结果。
  Future<void> refresh({bool requestWifiAccess = false}) async {
    if (_reading || state.isLoading) return;
    _reading = true;
    state = const AsyncLoading<HostNetworkInfo>();
    try {
      final service = ref.read(hostNetworkServiceProvider);
      if (requestWifiAccess) await service.requestWifiAccess();
      final info = await service.read();
      if (ref.mounted) state = AsyncData(info);
    } catch (error, stack) {
      if (ref.mounted) state = AsyncError(error, stack);
    } finally {
      _reading = false;
    }
  }
}
