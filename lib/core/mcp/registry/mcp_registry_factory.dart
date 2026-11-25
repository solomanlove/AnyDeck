import '../../adb/adb_service.dart';
import '../../adb/discovered_device.dart';
import '../../apps/android_app_instance_service.dart';
import '../../apps/app_management_service.dart';
import '../../device_actions/device_action_service.dart';
import '../../device_info/device_info_service.dart';
import '../../files/file_manager_service.dart';
import '../../harmony/hdc_service.dart';
import '../../ios/ios_command_service.dart';
import '../../ios/ios_device_service.dart';
import '../../layout_inspector/layout_inspector_service.dart';
import '../tools/mcp_app_tools.dart';
import '../tools/mcp_device_tools.dart';
import '../tools/mcp_file_tools.dart';
import '../tools/mcp_harmony_tools.dart';
import '../tools/mcp_ios_tools.dart';
import '../tools/mcp_ios_diagnostic_tools.dart';
import '../tools/mcp_log_tools.dart';
import '../tools/mcp_ui_tools.dart';
import 'mcp_tool_registry.dart';

/// 主窗口和独立 Server 共享同一组装入口，按需发现设备，不新增轮询进程。
class McpRegistryFactory {
  McpRegistryFactory({
    required this.adb,
    required this.hdc,
    required this.iosDevices,
    required this.iosCommands,
  });
  final AdbService adb;
  final HdcService hdc;
  final IosDeviceService iosDevices;
  final IosCommandService iosCommands;
  List<DiscoveredDevice>? _devices;
  DateTime? _checkedAt;
  Future<List<DiscoveredDevice>>? _pending;

  Future<List<DiscoveredDevice>> discover(bool refresh) async {
    if (_pending != null) return _pending!;
    if (!refresh &&
        _checkedAt != null &&
        DateTime.now().difference(_checkedAt!).inSeconds < 2) {
      return _devices!;
    }
    _pending = _scan();
    try {
      return await _pending!;
    } finally {
      _pending = null;
    }
  }

  Future<List<DiscoveredDevice>> _scan() async {
    final found = <DiscoveredDevice>[];
    // 每个平台独立失败，避免一个不可用的工具链吞掉其他平台设备。
    for (final scan in [
      adb.listDevices,
      hdc.listDevices,
      iosDevices.listDevices,
    ]) {
      try {
        found.addAll(await scan());
      } catch (_) {
        /* 缺失平台不伪造设备。 */
      }
    }
    _devices = found;
    _checkedAt = DateTime.now();
    return found;
  }

  Future<String?> resolve(String id) async {
    final matches = (await discover(
      false,
    )).where((d) => d.id == id && d.isOnline).toList();
    if (matches.length != 1) return null;
    final d = matches.single;
    return d.isIos
        ? 'ios'
        : d.isHarmony
        ? 'harmony'
        : 'android';
  }

  McpToolRegistry create() {
    bool harmony(String id) =>
        _devices?.any((d) => d.id == id && d.isHarmony) ?? false;
    Future<bool> isHarmony(String id) async => await resolve(id) == 'harmony';
    Future<bool> isIos(String id) async => await resolve(id) == 'ios';
    final actions = DeviceActionService(
      adb,
      hdc: hdc,
      isHarmonyResolver: harmony,
    );
    final layout = LayoutInspectorService(
      adb,
      hdc: hdc,
      isHarmonyResolver: harmony,
    );
    final files = FileManagerService(adb, hdc: hdc, isHarmonyResolver: harmony);
    final harmonyTools = McpHarmonyTools(hdc);
    final registry = McpToolRegistry()
      ..resolvePlatform = resolve
      ..isIosDevice = isIos;
    registry.registerAll(
      McpDeviceTools(
        adbService: adb,
        deviceInfoService: DeviceInfoService(adb),
        iosDeviceService: iosDevices,
        iosCommandService: iosCommands,
        isIosDevice: isIos,
        isHarmonyDevice: isHarmony,
        hdcService: hdc,
        discoverDevices: discover,
        harmonyDetail: harmonyTools.detail,
      ).getTools(),
    );
    registry.registerAll(
      McpUiTools(
        adbService: adb,
        actionService: actions,
        layoutService: layout,
        iosService: iosCommands,
        isIosDevice: isIos,
        isHarmonyDevice: isHarmony,
        hdcService: hdc,
      ).getTools(),
    );
    registry.registerAll(
      McpAppTools(
        appService: AppManagementService(adb, hdc: hdc),
        androidAppInstances: AndroidAppInstanceService(adb),
        isHarmonyDevice: isHarmony,
      ).getTools(),
    );
    registry.registerAll(
      McpFileTools(adbService: adb, fileManagerService: files).getTools(),
    );
    registry.registerAll(McpLogTools(adbService: adb).getTools());
    registry.registerAll(
      McpIosTools(commands: iosCommands, isIosDevice: isIos).getTools(),
    );
    registry.registerAll(harmonyTools.getTools());
    registry.registerAll(McpIosDiagnosticTools(iosCommands).getTools());
    return registry;
  }
}
