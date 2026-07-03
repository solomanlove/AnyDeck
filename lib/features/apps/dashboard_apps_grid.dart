part of '../dashboard_screen.dart';

class _PackageGrid extends ConsumerWidget {
  const _PackageGrid({
    required this.deviceId,
    required this.packages,
    required this.selectedPackage,
    required this.onSelected,
    required this.gridItemSize,
  });

  final String deviceId;
  final List<AdbPackage> packages;
  final String? selectedPackage;
  final ValueChanged<String> onSelected;
  final double gridItemSize;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GridView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: gridItemSize,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.85,
      ),
      itemCount: packages.length,
      itemBuilder: (context, index) {
        final package = packages[index];
        return _PackageGridItem(
          deviceId: deviceId,
          package: package,
          selected: package.name == selectedPackage,
          onSelected: () => onSelected(package.name),
          size: gridItemSize,
        );
      },
    );
  }
}

class _PackageGridItem extends ConsumerStatefulWidget {
  const _PackageGridItem({
    required this.deviceId,
    required this.package,
    required this.selected,
    required this.onSelected,
    required this.size,
  });

  final String deviceId;
  final AdbPackage package;
  final bool selected;
  final VoidCallback onSelected;
  final double size;

  @override
  ConsumerState<_PackageGridItem> createState() => _PackageGridItemState();
}

class _PackageGridItemState extends ConsumerState<_PackageGridItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final package = widget.package;

    // Calculate dimensions based on the user-controlled zoom size
    final double iconSize = widget.size * 0.42;
    final double labelFontSize = max(11.0, widget.size * 0.11);
    final double secondaryFontSize = max(9.0, widget.size * 0.09);

    final icon = package.flutter
        ? CupertinoIcons.square_grid_2x2
        : package.system
        ? CupertinoIcons.settings
        : CupertinoIcons.device_phone_portrait;
    final iconPath = package.iconLocalPath;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onSelected,
        onDoubleTap: () {
          widget.onSelected();
          _showAppDetailsDialog(context, ref, widget.deviceId, package);
        },
        child: AnimatedScale(
          scale: _isHovered ? 1.04 : 1.0,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: widget.selected
                  ? colorScheme.primaryContainer.withValues(alpha: 0.8)
                  : _isHovered
                  ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.4)
                  : colorScheme.surfaceContainerHighest.withValues(alpha: 0.15),
              border: Border.all(
                color: widget.selected
                    ? colorScheme.primary
                    : _isHovered
                    ? colorScheme.outlineVariant.withValues(alpha: 0.8)
                    : colorScheme.outlineVariant.withValues(alpha: 0.3),
                width: 1.5,
              ),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                if (_isHovered)
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
              ],
            ),
            child: Stack(
              children: [
                Positioned.fill(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // App Icon (应用图标)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: SizedBox(
                            width: iconSize,
                            height: iconSize,
                            child: iconPath != null && File(iconPath).existsSync()
                                ? Image.file(
                                    File(iconPath),
                                    fit: BoxFit.contain,
                                    errorBuilder: (context, error, stackTrace) =>
                                        _FallbackGridIcon(
                                          icon: icon,
                                          system: package.system,
                                          colorScheme: colorScheme,
                                          size: iconSize,
                                        ),
                                  )
                                : _FallbackGridIcon(
                                    icon: icon,
                                    system: package.system,
                                    colorScheme: colorScheme,
                                    size: iconSize,
                                  ),
                          ),
                        ),
                        SizedBox(height: max(6.0, widget.size * 0.06)),
                        // App Name (应用名称)
                        Text(
                          package.displayName,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            fontSize: labelFontSize,
                            color: widget.selected
                              ? colorScheme.onPrimaryContainer
                              : colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 2),
                        // Size or Version (应用大小或版本)
                        Text(
                          package.storageBytes != null && package.storageBytes! > 0
                              ? package.storageLabel
                              : package.versionLabel,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: secondaryFontSize,
                            color: widget.selected
                              ? colorScheme.onPrimaryContainer.withValues(alpha: 0.7)
                              : colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // DEBUG 调试斜角标，类似于 Flutter 的 Debug Banner 样式
                if (package.debuggable)
                  Positioned(
                    top: 5,
                    right: -18,
                    child: Transform.rotate(
                      angle: 0.785398, // 旋转 45 度 (pi / 4)
                      child: Container(
                        width: 60,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              colorScheme.error,
                              colorScheme.error.withValues(alpha: 0.85),
                            ],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.15),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 2.5),
                        child: const Text(
                          'DEBUG',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 7.0,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 网格视图中默认的圆角矩形占位图标
class _FallbackGridIcon extends StatelessWidget {
  const _FallbackGridIcon({
    required this.icon,
    required this.system,
    required this.colorScheme,
    required this.size,
  });

  final IconData icon;
  final bool system;
  final ColorScheme colorScheme;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: system
            ? colorScheme.surfaceContainerHighest
            : colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: Icon(
          icon,
          size: size * 0.6,
          color: system
              ? colorScheme.onSurfaceVariant
              : colorScheme.onPrimaryContainer,
        ),
      ),
    );
  }
}
