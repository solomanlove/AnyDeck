import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/l10n/app_localizations.dart';
import '../../core/adb/adb_device.dart';
import '../../core/adb/adb_result.dart';
import '../../core/ios/ios_mirror_service.dart';
import '../../core/ios/ios_ble_mouse_service.dart';
import 'ios_tool_widgets.dart';

/// 使用已部署的 WebDriverAgent 执行基础 iOS UI 自动化动作。
class IosAutomationTab extends ConsumerStatefulWidget {
  const IosAutomationTab({super.key, required this.device});

  final AdbDevice device;

  @override
  ConsumerState<IosAutomationTab> createState() => _IosAutomationTabState();
}

class _IosAutomationTabState extends ConsumerState<IosAutomationTab> {
  final _x = TextEditingController(text: '100');
  final _y = TextEditingController(text: '100');
  final _fromX = TextEditingController(text: '100');
  final _fromY = TextEditingController(text: '500');
  final _toX = TextEditingController(text: '100');
  final _toY = TextEditingController(text: '100');
  final _text = TextEditingController();
  final _button = TextEditingController(text: 'home');
  bool _loading = false;
  String _output = '';

  @override
  void dispose() {
    for (final controller in [
      _x,
      _y,
      _fromX,
      _fromY,
      _toX,
      _toY,
      _text,
      _button,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  double? _number(TextEditingController controller) {
    return double.tryParse(controller.text.trim());
  }

  Future<void> _execute(Future<AdbResult> Function() action) async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final result = await action();
      if (!mounted) return;
      setState(() {
        _output = result.isSuccess
            ? result.stdout
            : context.l10n
                  .t('iosCommandFailed')
                  .replaceAll('{error}', result.message);
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _tap() async {
    final x = _number(_x);
    final y = _number(_y);
    if (x == null || y == null) return;
    await _execute(
      () => ref.read(iosCommandServiceProvider).tap(widget.device.id, x, y),
    );
  }

  Future<void> _swipe() async {
    final fromX = _number(_fromX);
    final fromY = _number(_fromY);
    final toX = _number(_toX);
    final toY = _number(_toY);
    if ([fromX, fromY, toX, toY].any((value) => value == null)) return;
    await _execute(
      () => ref
          .read(iosCommandServiceProvider)
          .swipe(
            widget.device.id,
            fromX: fromX!,
            fromY: fromY!,
            toX: toX!,
            toY: toY!,
          ),
    );
  }

  Widget _field(
    BuildContext context,
    TextEditingController controller,
    String label, {
    bool numeric = false,
    double width = 120,
  }) {
    return SizedBox(
      width: width,
      child: TextField(
        controller: controller,
        keyboardType: numeric
            ? const TextInputType.numberWithOptions(decimal: true)
            : TextInputType.text,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final service = ref.read(iosCommandServiceProvider);
    return IosToolScaffold(
      title: context.l10n.t('iosAutomation'),
      description: context.l10n.t('iosWdaRequirement'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: _loading
                    ? null
                    : () => _execute(
                        () => service.automationStatus(widget.device.id),
                      ),
                icon: const Icon(Icons.health_and_safety_outlined),
                label: Text(context.l10n.t('iosWdaStatus')),
              ),
              OutlinedButton.icon(
                onPressed: _loading
                    ? null
                    : () => _execute(
                        () => service.automationSource(widget.device.id),
                      ),
                icon: const Icon(Icons.account_tree_outlined),
                label: Text(context.l10n.t('iosUiSource')),
              ),
              OutlinedButton.icon(
                onPressed: _loading
                    ? null
                    : () => _execute(
                        () => service.pressButton(widget.device.id, 'home'),
                      ),
                icon: const Icon(Icons.home_outlined),
                label: const Text('Home 键'),
              ),
              Consumer(
                builder: (context, ref, _) {
                  final ble = ref.watch(iosBleMouseProvider);
                  return OutlinedButton.icon(
                    onPressed: () =>
                        ref.read(iosBleMouseProvider.notifier).toggle(),
                    icon: Icon(
                      Icons.mouse_outlined,
                      color: ble.isEnabled ? Colors.green : null,
                    ),
                    label: Text(
                      ble.isEnabled
                          ? (ble.state == BleMouseState.connected
                              ? 'BLE 鼠标 (已连接)'
                              : 'BLE 鼠标 (广播中)')
                          : 'BLE 鼠标反控 (关闭)',
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _field(
                context,
                _x,
                context.l10n.t('iosCoordinateX'),
                numeric: true,
              ),
              _field(
                context,
                _y,
                context.l10n.t('iosCoordinateY'),
                numeric: true,
              ),
              FilledButton(
                onPressed: _loading ? null : _tap,
                child: Text(context.l10n.t('iosTap')),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _field(
                context,
                _fromX,
                context.l10n.t('iosFromX'),
                numeric: true,
              ),
              _field(
                context,
                _fromY,
                context.l10n.t('iosFromY'),
                numeric: true,
              ),
              _field(context, _toX, context.l10n.t('iosToX'), numeric: true),
              _field(context, _toY, context.l10n.t('iosToY'), numeric: true),
              FilledButton(
                onPressed: _loading ? null : _swipe,
                child: Text(context.l10n.t('iosSwipe')),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _field(context, _text, context.l10n.t('iosText'), width: 320),
              FilledButton(
                onPressed: _loading
                    ? null
                    : () => _execute(
                        () => service.typeText(widget.device.id, _text.text),
                      ),
                child: Text(context.l10n.t('iosTypeText')),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _field(
                context,
                _button,
                context.l10n.t('iosButtonName'),
                width: 320,
              ),
              FilledButton(
                onPressed: _loading || _button.text.isEmpty
                    ? null
                    : () => _execute(
                        () => service.pressButton(
                          widget.device.id,
                          _button.text.trim(),
                        ),
                      ),
                child: Text(context.l10n.t('iosPressButton')),
              ),
              if (_loading)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 16),
          IosCommandOutput(output: _output),
        ],
      ),
    );
  }
}
