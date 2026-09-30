import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/l10n/app_localizations.dart';
import '../../core/adb/adb_device.dart';
import '../../core/adb/adb_result.dart';
import '../../core/harmony/hdc_service.dart';
import '../../core/providers/app_providers.dart';
import '../../core/scrcpy/scrcpy_session.dart';
import '../widgets/dashboard_snack.dart';
import '../widgets/glass_section_card.dart';

/// 鸿蒙手机专属控制面板 Tab。
///
/// 与 Android 设备控制解耦，仅提供鸿蒙系统实际支持的 uinput 按键、
/// Ability/Deeplink 启动、文本注入、无线调试切换以及电源管理功能。
class HarmonyControlTab extends ConsumerStatefulWidget {
  /// 创建鸿蒙专属控制 Tab 实例
  const HarmonyControlTab({
    super.key,
    required this.device,
    required this.sessions,
  });

  /// 当前操作的目标鸿蒙设备
  final AdbDevice device;

  /// 全局活跃投屏会话列表
  final Map<String, ScrcpySession> sessions;

  @override
  ConsumerState<HarmonyControlTab> createState() => _HarmonyControlTabState();
}

class _HarmonyControlTabState extends ConsumerState<HarmonyControlTab> {
  final _urlController = TextEditingController();
  final _bundleController = TextEditingController();
  final _abilityController = TextEditingController();
  bool _isProcessing = false;

  @override
  void dispose() {
    _urlController.dispose();
    _bundleController.dispose();
    _abilityController.dispose();
    super.dispose();
  }

  Future<void> _executeHdcAction(
    String description,
    Future<AdbResult> Function(HdcService hdc) action,
  ) async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);
    try {
      final hdc = ref.read(hdcServiceProvider);
      final result = await action(hdc);
      if (!mounted) return;
      DashboardSnack.show(
        context,
        result.isSuccess
            ? '$description成功'
            : '$description失败: ${result.message}',
        isError: !result.isSuccess,
      );
    } catch (e) {
      if (mounted) {
        DashboardSnack.show(context, '$description异常: $e', isError: true);
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  void _showInputTextModal() {
    final textController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(CupertinoIcons.keyboard, size: 20),
            const SizedBox(width: 8),
            Text(ctx.l10n.t('inputText')),
          ],
        ),
        content: TextField(
          controller: textController,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '请输入要发送到鸿蒙设备的文本（支持中文及Unicode）',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (val) {
            Navigator.of(ctx).pop();
            if (val.trim().isNotEmpty) {
              _executeHdcAction(
                '发送文本',
                (hdc) => hdc.inputText(widget.device.id, val),
              );
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(ctx.l10n.t('cancel')),
          ),
          FilledButton.icon(
            icon: const Icon(CupertinoIcons.paperplane, size: 16),
            label: Text(ctx.l10n.t('send')),
            onPressed: () {
              Navigator.of(ctx).pop();
              final text = textController.text;
              if (text.trim().isNotEmpty) {
                _executeHdcAction(
                  '发送文本',
                  (hdc) => hdc.inputText(widget.device.id, text),
                );
              }
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isOnline = ref.watch(deviceOnlineProvider(widget.device.id));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!isOnline)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(CupertinoIcons.exclamationmark_triangle_fill, color: Colors.orange),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      context.l10n.t('offlineControlWarning'),
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ),
          AbsorbPointer(
            absorbing: !isOnline || _isProcessing,
            child: Opacity(
              opacity: isOnline ? 1.0 : 0.6,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildQuickNavigationCard(context),
                  const SizedBox(height: 16),
                  _buildAbilityAndDeeplinkCard(context),
                  const SizedBox(height: 16),
                  _buildPowerAndRebootCard(context),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 导航与常用按键控制卡片
  Widget _buildQuickNavigationCard(BuildContext context) {
    return GlassSectionCard(
      title: '快捷按键与文本控制',
      icon: CupertinoIcons.gamecontroller,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            OutlinedButton.icon(
              icon: const Icon(CupertinoIcons.back, size: 16),
              label: const Text('返回键'),
              onPressed: () => _executeHdcAction(
                '返回键',
                (hdc) => hdc.injectKey(widget.device.id, 2),
              ),
            ),
            OutlinedButton.icon(
              icon: const Icon(CupertinoIcons.home, size: 16),
              label: const Text('主屏幕 (Home)'),
              onPressed: () => _executeHdcAction(
                '主屏幕键',
                (hdc) => hdc.injectKey(widget.device.id, 1),
              ),
            ),
            OutlinedButton.icon(
              icon: const Icon(CupertinoIcons.square_stack_3d_down_right, size: 16),
              label: const Text('最近任务'),
              onPressed: () => _executeHdcAction(
                '最近任务键',
                (hdc) => hdc.openRecentTasks(widget.device.id),
              ),
            ),
            OutlinedButton.icon(
              icon: const Icon(CupertinoIcons.keyboard, size: 16),
              label: Text(context.l10n.t('inputText')),
              onPressed: _showInputTextModal,
            ),
            OutlinedButton.icon(
              icon: const Icon(CupertinoIcons.volume_up, size: 16),
              label: const Text('音量+'),
              onPressed: () => _executeHdcAction(
                '音量增加',
                (hdc) => hdc.injectKey(widget.device.id, 16),
              ),
            ),
            OutlinedButton.icon(
              icon: const Icon(CupertinoIcons.volume_down, size: 16),
              label: const Text('音量-'),
              onPressed: () => _executeHdcAction(
                '音量减少',
                (hdc) => hdc.injectKey(widget.device.id, 17),
              ),
            ),
            OutlinedButton.icon(
              icon: const Icon(CupertinoIcons.volume_off, size: 16),
              label: const Text('静音'),
              onPressed: () => _executeHdcAction(
                '静音按键',
                (hdc) => hdc.volumeMute(widget.device.id),
              ),
            ),
            OutlinedButton.icon(
              icon: const Icon(CupertinoIcons.sun_max, size: 16),
              label: const Text('唤醒屏幕'),
              onPressed: () => _executeHdcAction(
                '唤醒屏幕',
                (hdc) => hdc.setScreenPower(widget.device.id, powerOn: true),
              ),
            ),
            OutlinedButton.icon(
              icon: const Icon(CupertinoIcons.moon_fill, size: 16),
              label: const Text('熄屏休眠'),
              onPressed: () => _executeHdcAction(
                '熄屏休眠',
                (hdc) => hdc.setScreenPower(widget.device.id, powerOn: false),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// 鸿蒙 Ability 与深层链接启动卡片
  Widget _buildAbilityAndDeeplinkCard(BuildContext context) {
    return GlassSectionCard(
      title: 'Ability 与深层链接启动',
      icon: CupertinoIcons.link,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _urlController,
                decoration: const InputDecoration(
                  labelText: 'URL / Deeplink 链接',
                  hintText: 'https://... 或 custom://...',
                  isDense: true,
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(CupertinoIcons.compass, size: 18),
                ),
              ),
            ),
            const SizedBox(width: 12),
            FilledButton.icon(
              icon: const Icon(CupertinoIcons.play_arrow, size: 16),
              label: const Text('打开链接'),
              onPressed: () {
                final url = _urlController.text.trim();
                if (url.isEmpty) return;
                _executeHdcAction(
                  '打开链接',
                  (hdc) => hdc.shell(widget.device.id, 'aa start -U "$url"'),
                );
              },
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              flex: 3,
              child: TextField(
                controller: _bundleController,
                decoration: const InputDecoration(
                  labelText: 'Bundle Name (包名)',
                  hintText: 'com.example.harmonyapp',
                  isDense: true,
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(CupertinoIcons.app, size: 18),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 3,
              child: TextField(
                controller: _abilityController,
                decoration: const InputDecoration(
                  labelText: 'Ability Name',
                  hintText: 'EntryAbility',
                  isDense: true,
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(CupertinoIcons.bolt, size: 18),
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              icon: const Icon(CupertinoIcons.play_fill, size: 16),
              label: const Text('启动 Ability'),
              onPressed: () {
                final bundle = _bundleController.text.trim();
                final ability = _abilityController.text.trim();
                if (bundle.isEmpty) return;
                _executeHdcAction(
                  '启动 Ability',
                  (hdc) => ability.isNotEmpty
                      ? hdc.shell(widget.device.id, 'aa start -b "$bundle" -a "$ability"')
                      : hdc.shell(widget.device.id, 'aa start -b "$bundle"'),
                );
              },
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              icon: const Icon(CupertinoIcons.stop_fill, size: 16),
              label: const Text('强制停止'),
              onPressed: () {
                final bundle = _bundleController.text.trim();
                if (bundle.isEmpty) return;
                _executeHdcAction(
                  '停止应用',
                  (hdc) => hdc.shell(widget.device.id, 'aa force-stop -b "$bundle"'),
                );
              },
            ),
          ],
        ),
      ],
    );
  }

  /// 电源与重启管理卡片
  Widget _buildPowerAndRebootCard(BuildContext context) {
    return GlassSectionCard(
      title: '电源与系统管理',
      icon: CupertinoIcons.power,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            OutlinedButton.icon(
              icon: const Icon(CupertinoIcons.restart, size: 16),
              label: const Text('重启系统'),
              onPressed: () => _confirmReboot('重启系统', '确定要重启鸿蒙设备吗？', 'reboot'),
            ),
            OutlinedButton.icon(
              icon: const Icon(CupertinoIcons.arrow_right_circle, size: 16),
              label: const Text('重启至 Bootloader'),
              onPressed: () => _confirmReboot(
                '重启至 Bootloader',
                '设备将进入 Fastboot / Bootloader 刷机模式。',
                'reboot loader',
              ),
            ),
            OutlinedButton.icon(
              icon: const Icon(CupertinoIcons.wrench, size: 16),
              label: const Text('重启至 Recovery'),
              onPressed: () => _confirmReboot(
                '重启至 Recovery',
                '设备将进入系统恢复 Recovery 模式。',
                'reboot recovery',
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _confirmReboot(String title, String content, String command) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(ctx.l10n.t('cancel')),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _executeHdcAction(title, (hdc) => hdc.shell(widget.device.id, command));
            },
            child: Text(ctx.l10n.t('confirm')),
          ),
        ],
      ),
    );
  }
}
