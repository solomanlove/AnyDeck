import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../app/l10n/app_localizations.dart';

/// 通用的应用内 WebView 组件。
/// 提供桌面端适配的地址与操作工具栏、加载进度条、页面错误处理和导航控制。
class InAppWebViewWidget extends StatefulWidget {
  final String initialUrl;
  final String? title;
  final bool showToolbar;
  final VoidCallback? onClose;
  final VoidCallback? onBack;

  const InAppWebViewWidget({
    super.key,
    required this.initialUrl,
    this.title,
    this.showToolbar = true,
    this.onClose,
    this.onBack,
  });

  @override
  State<InAppWebViewWidget> createState() => _InAppWebViewWidgetState();
}

class _InAppWebViewWidgetState extends State<InAppWebViewWidget> {
  InAppWebViewController? _webViewController;
  late TextEditingController _urlInputController;

  double _progress = 0;
  bool _canGoBack = false;
  bool _canGoForward = false;
  bool _hasError = false;
  String _errorMessage = '';
  String _currentTitle = '';

  final InAppWebViewSettings _settings = InAppWebViewSettings(
    isInspectable: true,
    transparentBackground: false,
    mediaPlaybackRequiresUserGesture: false,
    allowsInlineMediaPlayback: true,
    javaScriptEnabled: true,
    supportZoom: true,
    disableVerticalScroll: false,
    disableHorizontalScroll: false,
    horizontalScrollBarEnabled: true,
    verticalScrollBarEnabled: true,
    allowsBackForwardNavigationGestures: true,
    userAgent:
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
  );

  @override
  void initState() {
    super.initState();
    _currentTitle = widget.title ?? '';
    _urlInputController = TextEditingController(text: widget.initialUrl);
  }

  @override
  void dispose() {
    _urlInputController.dispose();
    super.dispose();
  }

  Future<void> _updateNavState() async {
    if (_webViewController == null) return;
    final canBack = await _webViewController!.canGoBack();
    final canForward = await _webViewController!.canGoForward();
    if (mounted) {
      setState(() {
        _canGoBack = canBack;
        _canGoForward = canForward;
      });
    }
  }

  Future<void> _loadCurrentInputUrl() async {
    var raw = _urlInputController.text.trim();
    if (raw.isEmpty) return;
    if (!raw.startsWith('http://') &&
        !raw.startsWith('https://') &&
        !raw.startsWith('file://')) {
      raw = 'https://$raw';
    }
    _urlInputController.text = raw;
    await _webViewController?.loadUrl(
      urlRequest: URLRequest(url: WebUri(raw)),
    );
  }

  Future<void> _openInExternalBrowser() async {
    final currentUrl = _urlInputController.text.trim();
    if (currentUrl.isEmpty) return;
    try {
      if (Platform.isMacOS) {
        await Process.run('open', [currentUrl]);
      } else if (Platform.isWindows) {
        await Process.run('cmd', ['/c', 'start', '', currentUrl]);
      } else if (Platform.isLinux) {
        await Process.run('xdg-open', [currentUrl]);
      }
    } catch (_) {}
  }

  void _copyUrlToClipboard() {
    final currentUrl = _urlInputController.text.trim();
    if (currentUrl.isNotEmpty) {
      Clipboard.setData(ClipboardData(text: currentUrl));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.l10n.t('copiedToClipboard').replaceAll('{label}', 'URL'),
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final displayTitle = _currentTitle.isNotEmpty
        ? _currentTitle
        : (widget.title ?? '');

    return Column(
      children: [
        if (displayTitle.isNotEmpty ||
            widget.onClose != null ||
            widget.onBack != null)
          _buildTitleBar(theme, displayTitle),
        if (widget.showToolbar) _buildToolbar(theme),
        if (_progress > 0 && _progress < 1.0)
          LinearProgressIndicator(
            value: _progress,
            minHeight: 2,
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
            valueColor: AlwaysStoppedAnimation<Color>(theme.colorScheme.primary),
          ),
        Expanded(
          child: Stack(
            children: [
              InAppWebView(
                initialUrlRequest: URLRequest(
                  url: WebUri(widget.initialUrl),
                ),
                initialSettings: _settings,
                gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
                  Factory<OneSequenceGestureRecognizer>(
                    () => EagerGestureRecognizer(),
                  ),
                },
                onWebViewCreated: (controller) {
                  _webViewController = controller;
                },
                onLoadStart: (controller, url) {
                  setState(() {
                    _hasError = false;
                    _errorMessage = '';
                    if (url != null) {
                      _urlInputController.text = url.toString();
                    }
                  });
                  _updateNavState();
                },
                onProgressChanged: (controller, progress) {
                  setState(() {
                    _progress = progress / 100.0;
                  });
                },
                onTitleChanged: (controller, title) {
                  if (title != null && title.isNotEmpty) {
                    setState(() {
                      _currentTitle = title;
                    });
                  }
                },
                onLoadStop: (controller, url) async {
                  setState(() {
                    _progress = 0;
                    if (url != null) {
                      _urlInputController.text = url.toString();
                    }
                  });
                  await _updateNavState();
                },
                onReceivedError: (controller, request, error) {
                  setState(() {
                    _hasError = true;
                    _errorMessage = error.description;
                  });
                },
                shouldOverrideUrlLoading: (controller, navigationAction) async {
                  return NavigationActionPolicy.ALLOW;
                },
              ),
              if (_hasError)
                Container(
                  color: theme.colorScheme.surface,
                  alignment: Alignment.center,
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        CupertinoIcons.exclamationmark_circle,
                        size: 48,
                        color: Colors.redAccent,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        context.l10n.t('loadFailed'),
                        style: theme.textTheme.titleMedium,
                      ),
                      if (_errorMessage.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          _errorMessage,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        icon: const Icon(CupertinoIcons.refresh, size: 16),
                        label: Text(context.l10n.t('retry')),
                        onPressed: () {
                          setState(() {
                            _hasError = false;
                          });
                          _webViewController?.reload();
                        },
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTitleBar(ThemeData theme, String displayTitle) {
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
      ),
      child: NavigationToolbar(
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.onBack != null) ...[
              IconButton(
                icon: const Icon(CupertinoIcons.chevron_back, size: 18),
                tooltip: context.l10n.t('back'),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                onPressed: widget.onBack,
              ),
              const SizedBox(width: 4),
            ],
            Icon(
              CupertinoIcons.globe,
              size: 16,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 8),
          ],
        ),
        middle: Text(
          displayTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
            fontSize: 13,
            color: theme.colorScheme.onSurface,
          ),
        ),
        trailing: widget.onClose != null
            ? IconButton(
                icon: const Icon(CupertinoIcons.xmark, size: 16),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                tooltip: '关闭',
                onPressed: widget.onClose,
              )
            : const SizedBox.shrink(),
      ),
    );
  }

  Widget _buildToolbar(ThemeData theme) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
      ),
      child: NavigationToolbar(
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(CupertinoIcons.chevron_back, size: 18),
              onPressed: _canGoBack
                  ? () async {
                      await _webViewController?.goBack();
                      await _updateNavState();
                    }
                  : null,
              tooltip: '后退',
            ),
            IconButton(
              icon: const Icon(CupertinoIcons.chevron_forward, size: 18),
              onPressed: _canGoForward
                  ? () async {
                      await _webViewController?.goForward();
                      await _updateNavState();
                    }
                  : null,
              tooltip: '前进',
            ),
            IconButton(
              icon: const Icon(CupertinoIcons.refresh, size: 18),
              onPressed: () {
                _webViewController?.reload();
              },
              tooltip: '刷新',
            ),
          ],
        ),
        middle: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 540),
          child: SizedBox(
            height: 32,
            child: TextField(
              controller: _urlInputController,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(fontSize: 13),
              decoration: InputDecoration(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 0,
                ),
                filled: true,
                fillColor: theme.colorScheme.surface,
                prefixIcon: const Icon(
                  CupertinoIcons.lock_shield_fill,
                  size: 14,
                  color: Color(0xff09c47c),
                ),
                prefixIconConstraints: const BoxConstraints(
                  minWidth: 32,
                  minHeight: 32,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(
                    color: theme.colorScheme.outlineVariant,
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(
                    color:
                        theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
                  ),
                ),
                hintText: '输入网址 (如 https://...)',
                hintStyle: const TextStyle(fontSize: 12),
              ),
              onSubmitted: (_) => _loadCurrentInputUrl(),
            ),
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(CupertinoIcons.doc_on_clipboard, size: 18),
              tooltip: '复制链接',
              onPressed: _copyUrlToClipboard,
            ),
            IconButton(
              icon: const Icon(CupertinoIcons.compass, size: 18),
              tooltip: '在系统浏览器打开',
              onPressed: _openInExternalBrowser,
            ),
          ],
        ),
      ),
    );
  }
}
