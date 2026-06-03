import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../../l10n/app_localizations.dart';
import '../../settings/app_settings_controller.dart';
import '../../theme/app_theme.dart';
import '../../../features/dashboard/presentation/control/embedded_scrcpy_viewer.dart';
import '../../../core/scrcpy/embedded_scrcpy_service.dart';
import 'mirror_floating_toolbar.dart';

/// 投屏独立窗口应用入口。
class MirrorWindowApp extends ConsumerWidget {
  const MirrorWindowApp({
    super.key,
    required this.windowId,
    required this.argument,
  });

  final int windowId;
  final Map<String, dynamic> argument;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    final deviceId = argument['deviceId'] as String? ?? '';
    final deviceName = argument['deviceName'] as String? ?? 'Device';

    return MaterialApp(
      onGenerateTitle: (context) => deviceName,
      debugShowCheckedModeBanner: false,
      locale: settings.language.locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizationsDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      theme: buildAppTheme(Brightness.light),
      darkTheme: buildAppTheme(Brightness.dark),
      themeMode: settings.themeMode,
      home: MirrorWindowContent(
        deviceId: deviceId,
        deviceName: deviceName,
        windowId: windowId,
      ),
    );
  }
}

class MirrorWindowContent extends ConsumerStatefulWidget {
  const MirrorWindowContent({
    super.key,
    required this.deviceId,
    required this.deviceName,
    required this.windowId,
  });

  final String deviceId;
  final String deviceName;
  final int windowId;

  @override
  ConsumerState<MirrorWindowContent> createState() => _MirrorWindowContentState();
}

class _MirrorWindowContentState extends ConsumerState<MirrorWindowContent> {
  String? _errorMessage;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startMirroring();
    });
  }

  Future<void> _startMirroring() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final activeMirror = ref.read(activeEmbeddedMirrorProvider(widget.deviceId));
      if (activeMirror == null) {
        await ref
            .read(activeEmbeddedMirrorProvider(widget.deviceId).notifier)
            .toggleMirroring();
      }
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final textureId = ref.watch(activeEmbeddedMirrorProvider(widget.deviceId));
    final isMirrorActive = textureId != null;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final headerBgColor = isDark
        ? Theme.of(context).cardColor
        : const Color(0xffffffff);
    final borderColor = isDark
        ? const Color(0xff2d2d2d)
        : const Color(0xffeceef1);

    Widget contentWidget;
    if (_isLoading) {
      contentWidget = const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('正在启动投屏服务...', style: TextStyle(fontSize: 14)),
          ],
        ),
      );
    } else if (_errorMessage != null) {
      contentWidget = Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 48),
              const SizedBox(height: 16),
              Text(
                '投屏启动失败',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _startMirroring,
                icon: const Icon(Icons.refresh),
                label: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    } else if (isMirrorActive) {
      contentWidget = Stack(
        children: [
          Positioned.fill(
            child: ClipRRect(
              child: EmbeddedScrcpyViewer(deviceId: widget.deviceId),
            ),
          ),
          Positioned(
            top: 10,
            left: 16,
            right: 16,
            child: Center(
              child: MirrorFloatingToolbar(
                deviceId: widget.deviceId,
                windowId: widget.windowId,
              ),
            ),
          ),
        ],
      );
    } else {
      contentWidget = const Center(
        child: Text('未连接或投屏已停止'),
      );
    }

    return Scaffold(
      backgroundColor: isDark ? const Color(0xff121212) : const Color(0xfff8f9fa),
      body: Column(
        children: [
          Container(
            height: 44, // 减小高度，由 56 降至 44
            padding: EdgeInsets.only(
              left: Platform.isMacOS ? 80 : 16,
              right: 16,
              top: 4, // 让标题再距离上一些
            ),
            decoration: BoxDecoration(
              color: headerBgColor,
              border: Border(
                bottom: BorderSide(
                  color: borderColor,
                  width: 1,
                ),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  widget.deviceName,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
          ),
          Expanded(
            child: contentWidget,
          ),
        ],
      ),
    );
  }
}
