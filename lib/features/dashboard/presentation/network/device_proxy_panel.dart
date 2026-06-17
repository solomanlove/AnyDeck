import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/l10n/app_localizations.dart';
import '../../../../core/providers/network_providers.dart';

/// Network Tab 中的设备 HTTP 代理快捷设置面板。
class DeviceProxyPanel extends ConsumerStatefulWidget {
  const DeviceProxyPanel({super.key, required this.deviceId});

  final String deviceId;

  @override
  ConsumerState<DeviceProxyPanel> createState() => _DeviceProxyPanelState();
}

class _DeviceProxyPanelState extends ConsumerState<DeviceProxyPanel> {
  final _hostController = TextEditingController(text: '127.0.0.1');
  final _portController = TextEditingController(text: '8888');

  @override
  void initState() {
    super.initState();
    _loadDefaults();
  }

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    super.dispose();
  }

  Future<void> _loadDefaults() async {
    final defaults = await loadDeviceProxyDefaults();
    if (!mounted) {
      return;
    }
    setState(() {
      _hostController.text = defaults.host;
      _portController.text = '${defaults.port}';
    });
  }

  Future<void> _applyProxy() async {
    final host = _hostController.text.trim();
    final port = int.tryParse(_portController.text.trim());
    if (host.isEmpty || port == null || port < 1 || port > 65535) {
      _showSnack(context.l10n.t('deviceProxyInvalid'), isError: true);
      return;
    }

    try {
      await ref
          .read(deviceProxyControllerProvider(widget.deviceId).notifier)
          .apply(host: host, port: port);
      await saveDeviceProxyDefaults(host: host, port: port);
      if (mounted) {
        _showSnack(context.l10n.t('deviceProxyApplySuccess'));
      }
    } catch (error) {
      if (mounted) {
        _showSnack(
          '${context.l10n.t('deviceProxyApplyFailed')}: $error',
          isError: true,
        );
      }
    }
  }

  Future<void> _clearProxy() async {
    try {
      await ref
          .read(deviceProxyControllerProvider(widget.deviceId).notifier)
          .clear();
      if (mounted) {
        _showSnack(context.l10n.t('deviceProxyClearSuccess'));
      }
    } catch (error) {
      if (mounted) {
        _showSnack(
          '${context.l10n.t('deviceProxyClearFailed')}: $error',
          isError: true,
        );
      }
    }
  }

  void _showSnack(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : const Color(0xff09c47c),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final proxyAsync = ref.watch(deviceHttpProxyProvider(widget.deviceId));
    final isBusy = ref.watch(deviceProxyControllerProvider(widget.deviceId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader(
          title: context.l10n.t('deviceHttpProxy'),
          actions: [
            IconButton(
              tooltip: context.l10n.t('refresh'),
              icon: const Icon(CupertinoIcons.refresh),
              onPressed: isBusy
                  ? null
                  : () => ref.invalidate(
                      deviceHttpProxyProvider(widget.deviceId),
                    ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.03)
                    : Colors.white.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.08)
                      : Colors.black.withValues(alpha: 0.04),
                  width: 1.5,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _ProxyStatus(proxyAsync: proxyAsync, isDark: isDark),
                  const SizedBox(height: 16),
                  Text(
                    context.l10n.t('deviceProxyDesc'),
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark
                          ? Colors.grey[500]
                          : const Color(0xff6b7280),
                    ),
                  ),
                  const SizedBox(height: 16),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final narrow = constraints.maxWidth < 560;
                      if (narrow) {
                        return Column(
                          children: [
                            _ProxyTextField(
                              controller: _hostController,
                              label: context.l10n.t('deviceProxyHost'),
                              hintText: '127.0.0.1',
                              isDark: isDark,
                              enabled: !isBusy,
                            ),
                            const SizedBox(height: 12),
                            _ProxyTextField(
                              controller: _portController,
                              label: context.l10n.t('deviceProxyPort'),
                              hintText: '8888',
                              keyboardType: TextInputType.number,
                              isDark: isDark,
                              enabled: !isBusy,
                            ),
                          ],
                        );
                      }

                      return Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: _ProxyTextField(
                              controller: _hostController,
                              label: context.l10n.t('deviceProxyHost'),
                              hintText: '127.0.0.1',
                              isDark: isDark,
                              enabled: !isBusy,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _ProxyTextField(
                              controller: _portController,
                              label: context.l10n.t('deviceProxyPort'),
                              hintText: '8888',
                              keyboardType: TextInputType.number,
                              isDark: isDark,
                              enabled: !isBusy,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 18),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    alignment: WrapAlignment.end,
                    children: [
                      OutlinedButton.icon(
                        onPressed: isBusy ? null : _clearProxy,
                        icon: const Icon(CupertinoIcons.clear, size: 16),
                        label: Text(context.l10n.t('deviceProxyClear')),
                      ),
                      FilledButton.icon(
                        onPressed: isBusy ? null : _applyProxy,
                        icon: isBusy
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(CupertinoIcons.check_mark, size: 16),
                        label: Text(context.l10n.t('deviceProxyApply')),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.actions});

  final String title;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: isDark ? Colors.white : const Color(0xff1f2937),
          ),
        ),
        const Spacer(),
        ...actions,
      ],
    );
  }
}

class _ProxyStatus extends StatelessWidget {
  const _ProxyStatus({required this.proxyAsync, required this.isDark});

  final AsyncValue<DeviceProxyConfig> proxyAsync;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return proxyAsync.when(
      data: (proxy) => _StatusChip(
        icon: proxy.isEnabled
            ? CupertinoIcons.check_mark_circled
            : CupertinoIcons.minus_circle,
        label: proxy.isEnabled
            ? (proxy.address.isEmpty ? proxy.rawValue : proxy.address)
            : context.l10n.t('deviceProxyNotSet'),
        isDark: isDark,
        isError: false,
      ),
      loading: () => _StatusChip(
        icon: CupertinoIcons.clock,
        label: context.l10n.t('deviceProxyLoading'),
        isDark: isDark,
        isError: false,
      ),
      error: (error, _) => _StatusChip(
        icon: CupertinoIcons.exclamationmark_triangle,
        label: '${context.l10n.t('deviceProxyReadFailed')}: $error',
        isDark: isDark,
        isError: true,
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.icon,
    required this.label,
    required this.isDark,
    required this.isError,
  });

  final IconData icon;
  final String label;
  final bool isDark;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final color = isError
        ? Colors.redAccent
        : Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isDark ? Colors.grey[200] : const Color(0xff374151),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProxyTextField extends StatelessWidget {
  const _ProxyTextField({
    required this.controller,
    required this.label,
    required this.hintText,
    required this.isDark,
    required this.enabled,
    this.keyboardType,
  });

  final TextEditingController controller;
  final String label;
  final String hintText;
  final bool isDark;
  final bool enabled;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      enabled: enabled,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        hintText: hintText,
        isDense: true,
        filled: true,
        fillColor: isDark
            ? Colors.black.withValues(alpha: 0.2)
            : Colors.white.withValues(alpha: 0.65),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: isDark
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.black.withValues(alpha: 0.08),
          ),
        ),
      ),
    );
  }
}
