part of '../dashboard_screen.dart';

/// 文件工具栏在窄窗口中拆为导航和操作两行，保留路径输入与全部操作。
class _FilesToolbarLayout extends StatelessWidget {
  const _FilesToolbarLayout({
    required this.navigation,
    required this.pathBar,
    required this.actions,
  });

  final List<Widget> navigation;
  final Widget pathBar;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 800) {
          return Row(
            children: [
              ...navigation,
              Expanded(child: pathBar),
              ...actions,
            ],
          );
        }
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                ...navigation,
                Expanded(child: pathBar),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: actions),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// 文件表头与列表共用同一个横向滚动区域，避免固定列宽挤压窄窗口。
extension _FilesTableViewportExtension on Widget {
  Widget _withFilesTableViewport({
    required bool isGridView,
    required Widget header,
  }) => _FilesTableViewport(isGridView: isGridView, header: header, body: this);
}

class _FilesTableViewport extends StatelessWidget {
  const _FilesTableViewport({
    required this.isGridView,
    required this.header,
    required this.body,
  });

  final bool isGridView;
  final Widget header;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    if (isGridView) return body;
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: max(constraints.maxWidth, 820),
          height: constraints.maxHeight,
          child: Column(
            children: [
              header,
              Expanded(child: body),
            ],
          ),
        ),
      ),
    );
  }
}
