import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/l10n/app_localizations.dart';
import '../../../../core/providers/app_providers.dart';
import '../../../../core/providers/network_providers.dart';

class AddPortForwardDialog extends ConsumerStatefulWidget {
  const AddPortForwardDialog({super.key, required this.deviceId});

  final String deviceId;

  @override
  ConsumerState<AddPortForwardDialog> createState() =>
      _AddPortForwardDialogState();
}

class _AddPortForwardDialogState extends ConsumerState<AddPortForwardDialog> {
  final _devicePortController = TextEditingController(text: '8081');
  final _localPortController = TextEditingController(text: '8081');
  final _presetNameController = TextEditingController();
  bool _saveAsPreset = false;
  bool _autoApplyOnConnect = false;

  @override
  void dispose() {
    _devicePortController.dispose();
    _localPortController.dispose();
    _presetNameController.dispose();
    super.dispose();
  }

  void _applyQuickPreset(String name, String port) {
    setState(() {
      _devicePortController.text = port;
      _localPortController.text = port;
      if (_saveAsPreset && _presetNameController.text.isEmpty) {
        _presetNameController.text = name;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      backgroundColor: isDark ? const Color(0xff1e293b) : Colors.white,
      surfaceTintColor: Colors.transparent,
      child: Container(
        width: 440,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 顶部图标与标题
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.swap_horiz, color: primaryColor, size: 32),
                  const SizedBox(width: 12),
                  Text(
                    context.l10n.t('addPortForward'),
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white : const Color(0xff1f2937),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                context.l10n.t('addPortForwardDesc'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: isDark ? Colors.grey[400] : const Color(0xff6b7280),
                ),
              ),
              const SizedBox(height: 20),
              Divider(
                color: isDark ? Colors.grey[800] : const Color(0xffe5e7eb),
              ),
              const SizedBox(height: 16),

              // 端口输入行
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // 设备端口
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.l10n.t('devicePort'),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: isDark
                                ? Colors.grey[300]
                                : const Color(0xff4b5563),
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _devicePortController,
                          keyboardType: TextInputType.number,
                          style: const TextStyle(fontWeight: FontWeight.w500),
                          decoration: _inputDecoration(
                            isDark,
                            primaryColor,
                            '8081',
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.only(left: 12, right: 12, top: 24),
                    child: Icon(
                      CupertinoIcons.arrow_right,
                      color: Color(0xff9ca3af),
                      size: 20,
                    ),
                  ),
                  // 本地端口
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.l10n.t('localPort'),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: isDark
                                ? Colors.grey[300]
                                : const Color(0xff4b5563),
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _localPortController,
                          keyboardType: TextInputType.number,
                          style: const TextStyle(fontWeight: FontWeight.w500),
                          decoration: _inputDecoration(
                            isDark,
                            primaryColor,
                            '8081',
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // 快捷预设
              Text(
                context.l10n.t('quickPresets'),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.grey[300] : const Color(0xff4b5563),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  _quickPresetButton('React Native', '8081', isDark),
                  const SizedBox(width: 10),
                  _quickPresetButton('Flutter', '8080', isDark),
                  const SizedBox(width: 10),
                  _quickPresetButton('Expo', '19000', isDark),
                ],
              ),
              const SizedBox(height: 20),
              Divider(
                color: isDark ? Colors.grey[800] : const Color(0xffe5e7eb),
              ),
              const SizedBox(height: 16),

              // 保存为预设复选框
              _customCheckbox(
                value: _saveAsPreset,
                onChanged: (val) {
                  setState(() {
                    _saveAsPreset = val;
                    if (val && _presetNameController.text.isEmpty) {
                      _presetNameController.text =
                          'Preset ${_devicePortController.text}';
                    }
                  });
                },
                label: context.l10n.t('saveAsPreset'),
                isDark: isDark,
                primaryColor: primaryColor,
              ),

              // 预设高级选项（带平滑大小动画）
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeInOut,
                child: _saveAsPreset
                    ? Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            TextField(
                              controller: _presetNameController,
                              style: const TextStyle(fontSize: 14),
                              decoration: _inputDecoration(
                                isDark,
                                primaryColor,
                                context.l10n.t('presetNameOptional'),
                              ),
                            ),
                            const SizedBox(height: 16),
                            _customCheckbox(
                              value: _autoApplyOnConnect,
                              onChanged: (val) =>
                                  setState(() => _autoApplyOnConnect = val),
                              label: context.l10n.t('autoApplyOnConnect'),
                              isDark: isDark,
                              primaryColor: primaryColor,
                            ),
                          ],
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
              const SizedBox(height: 28),

              // 底部操作按钮
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // 取消按钮
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 14,
                      ),
                      backgroundColor: isDark
                          ? const Color(0xff334155)
                          : const Color(0xfff3f4f6),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      context.l10n.t('cancel'),
                      style: TextStyle(
                        color: isDark
                            ? Colors.grey[200]
                            : const Color(0xff1f2937),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  // 添加按钮
                  TextButton(
                    onPressed: () async {
                      final devPort = _devicePortController.text.trim();
                      final locPort = _localPortController.text.trim();
                      if (devPort.isEmpty || locPort.isEmpty) return;

                      final adb = ref.read(adbServiceProvider);
                      final fullDevPort = devPort.startsWith('tcp:')
                          ? devPort
                          : 'tcp:$devPort';
                      final fullLocPort = locPort.startsWith('tcp:')
                          ? locPort
                          : 'tcp:$locPort';

                      final result = await adb.run([
                        '-s',
                        widget.deviceId,
                        'reverse',
                        fullDevPort,
                        fullLocPort,
                      ]);
                      if (result.isSuccess) {
                        // 强制刷新列表
                        ref.invalidate(
                          activePortForwardsProvider(widget.deviceId),
                        );

                        // 如果勾选了保存为预设
                        if (_saveAsPreset) {
                          final name =
                              _presetNameController.text.trim().isNotEmpty
                              ? _presetNameController.text.trim()
                              : 'Preset $devPort';
                          final preset = PortForwardPreset(
                            name: name,
                            devicePort: devPort,
                            localPort: locPort,
                            autoApply: _autoApplyOnConnect,
                          );
                          await ref
                              .read(portForwardPresetsProvider.notifier)
                              .savePreset(preset);
                        }

                        if (context.mounted) {
                          Navigator.of(context).pop();
                        }
                      } else {
                        // 如果执行失败，在弹窗外显示错误（使用 context 提供的 SnackBar 或者其他提示）
                        // 在此我们也可以直接抛出错误或更新 UI 提示。
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                '${context.l10n.t('reverseFailed')}: ${result.message}',
                              ),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                    },
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 14,
                      ),
                      backgroundColor: primaryColor,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Add', // Exact mockup label
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _quickPresetButton(String title, String port, bool isDark) {
    return Expanded(
      child: GestureDetector(
        onTap: () => _applyQuickPreset(title, port),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xff334155) : const Color(0xfff3f4f6),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.grey[200] : const Color(0xff374151),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  port,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: isDark ? Colors.grey[400] : const Color(0xff6b7280),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _customCheckbox({
    required bool value,
    required ValueChanged<bool> onChanged,
    required String label,
    required bool isDark,
    required Color primaryColor,
  }) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                color: value
                    ? primaryColor
                    : (isDark
                          ? const Color(0xff334155)
                          : const Color(0xffe5e7eb)),
              ),
              child: value
                  ? const Icon(Icons.check, size: 16, color: Colors.white)
                  : null,
            ),
            const SizedBox(width: 10),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.grey[200] : const Color(0xff1f2937),
              ),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(
    bool isDark,
    Color focusedColor,
    String hint,
  ) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(
        color: isDark ? Colors.grey[600] : Colors.grey[400],
        fontSize: 14,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      filled: true,
      fillColor: isDark ? const Color(0xff0f172a) : const Color(0xfff9fafb),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: isDark ? const Color(0xff475569) : const Color(0xffe5e7eb),
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: isDark ? const Color(0xff475569) : const Color(0xffe5e7eb),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: focusedColor, width: 2),
      ),
    );
  }
}
