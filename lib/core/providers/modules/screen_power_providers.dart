import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../scrcpy/embedded_scrcpy_service.dart';
import 'device_registry_providers.dart';
import 'service_providers.dart';

/// 跟踪与控制单台物理设备显示屏息屏（电源关闭）状态的控制器。
///
/// 默认状态为 false（屏幕开启）。
/// 集成了：
/// 1. 自动备份与恢复亮度设置（规避荣耀等机型息屏后亮度变最低的假死现象）；
/// 2. `adb shell getevent` 物理触摸与按键监听，用户触摸真机时自动退出息屏；
/// 3. `dumpsys window windows` 针对 FLAG_SECURE 密码锁屏界面的自适应防黑屏保护机制。
class ScreenPowerOffNotifier extends Notifier<bool> {
  ScreenPowerOffNotifier(this.deviceId);
  final String deviceId;
  Process? _geteventProcess;
  Timer? _secureCheckTimer;
  int? _savedBrightness;
  int? _savedBrightnessMode;

  @override
  bool build() {
    ref.onDispose(() {
      _stopListener();
      _secureCheckTimer?.cancel();
    });
    return false;
  }

  /// 供外部与内部统一调用的亮灭控制接口，实现状态与物理控制收口
  Future<void> toggleScreenPower(bool off) async {
    if (state == off) return;
    
    final isHarmony = ref
        .read(deviceRegistryProvider)
        .any((device) => device.id == deviceId && device.isHarmony);
    if (isHarmony) {
      final result = await ref
          .read(hdcServiceProvider)
          .setScreenPower(deviceId, powerOn: !off);
      if (result.isSuccess) {
        state = off;
      }
      return;
    }

    final adb = ref.read(adbServiceProvider);

    if (off) {
      // 息屏前：保存当前的亮度和自动亮度模式，以便亮屏时可以完美恢复，解决荣耀等机型息屏后亮度变最低的假死现象
      try {
        final brightnessRes = await adb.shell(deviceId, "settings get system screen_brightness");
        if (brightnessRes.isSuccess) {
          _savedBrightness = int.tryParse(brightnessRes.stdout.trim());
        }
        final modeRes = await adb.shell(deviceId, "settings get system screen_brightness_mode");
        if (modeRes.isSuccess) {
          _savedBrightnessMode = int.tryParse(modeRes.stdout.trim());
        }
      } catch (e) {
        stdout.writeln('[ScreenPowerOff] Failed to save brightness settings: $e');
      }
    }

    // 改变物理手机显示器供电状态
    await _setScreenPowerMode(!off);
    
    if (!off) {
      // 亮屏后：将原本被物理手机系统暗置为最低的亮度重新唤醒。由于部分手机在自动亮度模式下会忽略亮度修改命令，我们必须先切到手动模式(0)，设置亮度，再切回自动模式。
      try {
        // 1. 强制将亮度模式设为手动 (0)
        await adb.shellArgs(deviceId, ['settings', 'put', 'system', 'screen_brightness_mode', '0']);
        
        // 2. 写入原亮度或高对比度兜底值 (150)
        final targetBrightness = _savedBrightness ?? 150;
        await adb.shellArgs(deviceId, ['settings', 'put', 'system', 'screen_brightness', targetBrightness.toString()]);
        
        // 3. 如果用户原先开启了自动亮度，在 200 毫秒后恢复自动亮度模式 (1)
        if (_savedBrightnessMode == 1) {
          Future.delayed(const Duration(milliseconds: 200), () async {
            await adb.shellArgs(deviceId, ['settings', 'put', 'system', 'screen_brightness_mode', '1']);
          });
        }
      } catch (e) {
        stdout.writeln('[ScreenPowerOff] Failed to restore brightness settings: $e');
      }
    }

    state = off;
    if (off) {
      _startListener();
      _startSecureCheck();
    } else {
      _stopListener();
      _stopSecureCheck();
    }
  }

  /// 传统的 setOff 仅做逻辑状态迁移与监听切换
  void setOff(bool value) {
    if (state == value) return;
    state = value;
    if (value) {
      _startListener();
      _startSecureCheck();
    } else {
      _stopListener();
      _stopSecureCheck();
    }
  }

  /// 启动安全界面防双黑屏监控（周期轮询）
  void _startSecureCheck() {
    _secureCheckTimer?.cancel();
    final adb = ref.read(adbServiceProvider);
    _secureCheckTimer = Timer.periodic(const Duration(milliseconds: 1500), (timer) async {
      try {
        // 利用 shell 管道匹配当前焦点窗口属性是否拥有安全屏障（FLAG_SECURE）或是系统锁屏界面
        final res = await adb.shell(
          deviceId,
          "dumpsys window windows | grep -A 15 'mCurrentFocus' | grep -E 'FLAG_SECURE|password|credential|pin|lock'",
        );
        if (res.isSuccess && res.stdout.trim().isNotEmpty) {
          stdout.writeln('[ScreenPowerOff] FLAG_SECURE window or lock screen detected! Force waking screen to allow input.');
          // 一旦监测到黑屏安全壁垒，强制退出息屏，瞬间点亮物理手机供用户交互
          await toggleScreenPower(false);
        }
      } catch (e) {
        stdout.writeln('[ScreenPowerOff] Secure check error: $e');
      }
    });
  }

  /// 关闭安全界面监控
  void _stopSecureCheck() {
    _secureCheckTimer?.cancel();
    _secureCheckTimer = null;
  }

  /// 开启物理手机触摸/按键监听器
  void _startListener() async {
    _stopListener();
    final adb = ref.read(adbServiceProvider);
    final startTime = DateTime.now(); // 记录监听器启动的初始时间
    try {
      stdout.writeln('[ScreenPowerOff] starting getevent listener for $deviceId');
      // 启动 adb shell getevent 持续监听手机硬件的输入事件
      _geteventProcess = await Process.start(
        adb.executable,
        ['-s', deviceId, 'shell', 'getevent'],
      );

      // 用正则匹配格式为 /dev/input/eventX: 的真实硬件输入事件，用以过滤设备列表等初始化信息
      final eventRegex = RegExp(r'/dev/input/event\d+:');

      _geteventProcess!.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) async {
        stdout.writeln('[ScreenPowerOff] getevent stdout: $line');
        if (eventRegex.hasMatch(line)) {
          // 过滤息屏瞬间 1 秒内的噪点/系统状态余震事件，防止误判导致瞬间重新唤醒
          final elapsed = DateTime.now().difference(startTime);
          if (elapsed.inMilliseconds < 1000) {
            stdout.writeln('[ScreenPowerOff] Ignored early event (cooldown): $line');
            return;
          }
          stdout.writeln('[ScreenPowerOff] touch event detected! stopping listener and waking screen.');
          // 检测到触摸或硬件按键，直接调用统一接口退出息屏
          await toggleScreenPower(false);
        }
      });

      // 监听错误日志流
      _geteventProcess!.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        stdout.writeln('[ScreenPowerOff] getevent stderr: $line');
      });

      // 监听进程退出状态
      _geteventProcess!.exitCode.then((code) {
        stdout.writeln('[ScreenPowerOff] getevent exited with code: $code');
        _geteventProcess = null;
      });
    } catch (e) {
      stdout.writeln('Failed to start getevent listener: $e');
    }
  }

  /// 关闭并注销物理手机的触摸/按键监听器，杀掉后台 adb 进程
  void _stopListener() {
    _geteventProcess?.kill();
    _geteventProcess = null;
  }

  /// 向 scrcpy 发送控制模式命令 (10 代表设置屏幕电源模式，2 代表亮屏，0 代表息屏)
  Future<bool> _setScreenPowerMode(bool powerOn) async {
    final buffer = ByteData(2);
    buffer.setUint8(0, 10); // 控制消息类型：设置屏幕电源模式
    buffer.setUint8(1, powerOn ? 2 : 0); // 2 = 正常亮屏, 0 = 息屏
    final message = buffer.buffer.asUint8List();
    bool success = false;
    try {
      success = await ref.read(embeddedScrcpyServiceProvider).sendControl(
        deviceId: deviceId,
        controlMessage: message,
      );
    } catch (_) {}
    if (powerOn) {
      // 荣耀/华为等设备兼容性双重保障：
      final adb = ref.read(adbServiceProvider);
      // 保障一：向 Android 系统注入 KEYCODE_WAKEUP (224) 唤醒键以点亮背光
      await adb.shellArgs(deviceId, ['input', 'keyevent', '224']);
      // 保障二：向屏幕注入一次微小的滑动事件 (swipe 10 10 10 10)，迫使系统的 PowerManager 触发 userActivity 物理激活屏幕
      await adb.shellArgs(deviceId, ['input', 'swipe', '10', '10', '10', '10']);
      return true;
    }
    return success;
  }
}

/// 单台物理设备息屏电源控制 Provider。
///
/// 家族参数 [deviceId] 为目标设备 ID。
final screenPowerOffProvider =
    NotifierProvider.family<ScreenPowerOffNotifier, bool, String>(
      ScreenPowerOffNotifier.new,
    );
