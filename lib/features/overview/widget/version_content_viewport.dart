import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../app/l10n/app_localizations.dart';

/// 系统版本双栏的共享阅读视口；窄窗口显示滚动条和两端跳转按钮。
/// child 使用足够的宽度排版，controller 随视口卸载回收。
class VersionContentViewport extends StatefulWidget {
  const VersionContentViewport({super.key, required this.child});
  final Widget child;

  @override
  State<VersionContentViewport> createState() => _VersionContentViewportState();
}

class _VersionContentViewportState extends State<VersionContentViewport> {
  final _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _scroll(bool end) {
    _controller.animateTo(
      end ? _controller.position.maxScrollExtent : 0,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final narrow = constraints.maxWidth < 1280;
      return Column(
        children: [
          if (narrow)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  TextButton.icon(
                    onPressed: () => _scroll(false),
                    icon: const Icon(Icons.arrow_back, size: 16),
                    label: Text(context.l10n.t('versionList')),
                  ),
                  Expanded(
                    child: Text(
                      context.l10n.t('versionScrollHint'),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => _scroll(true),
                    icon: const Icon(Icons.arrow_forward, size: 16),
                    label: Text(context.l10n.t('versionDetails')),
                  ),
                ],
              ),
            ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, body) => Scrollbar(
                controller: _controller,
                thumbVisibility: narrow,
                trackVisibility: narrow,
                scrollbarOrientation: ScrollbarOrientation.bottom,
                child: SingleChildScrollView(
                  key: const Key('systemVersionsHorizontalScroll'),
                  controller: _controller,
                  scrollDirection: Axis.horizontal,
                  padding: EdgeInsets.only(bottom: narrow ? 16 : 0),
                  child: SizedBox(
                    width: math.max(1280, body.maxWidth),
                    height: math.max(0, body.maxHeight - (narrow ? 16 : 0)),
                    child: widget.child,
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    },
  );
}
