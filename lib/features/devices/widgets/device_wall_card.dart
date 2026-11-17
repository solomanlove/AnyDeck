import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../app/theme/app_theme.dart';
import 'device_wall_phone.dart';

/// 设备墙中的手机卡片，只负责展示，设备命令与选择状态由宿主持有。
///
/// [name]、[systemVersion]、[statusLabel] 和 [ipAddress] 来自实际设备资料；
/// [brand]、[coverTitle]、[coverHint] 是没有可用截图时的封面信息，
/// [screenshot] 仅接受真实截图，不会生成模拟的手机内容。
/// [phoneWidth] 决定手机尺寸，默认保持原型 132px 和 9:18.5 的比例。
/// [batchMode] 为 true 时显示勾选框并隐藏操作栏；[selected]、[selectable]
/// 和 [onSelected] 由父级管理，点击卡片任意非交互空白或手机均可选择。
/// 普通模式下 [onOpen] 打开投屏或重连，[onInfo] 进入设备工作台，
/// [onMore] 打开操作菜单，[onSecondaryTapDown] 复用设备右键菜单。
/// [busy] 阻止重复打开，[actionLabel] 和 [actionIcon] 表达当前主操作。
class DeviceWallCard extends StatelessWidget {
  const DeviceWallCard({
    super.key,
    required this.name,
    required this.systemVersion,
    required this.statusLabel,
    required this.brand,
    required this.coverTitle,
    required this.coverHint,
    required this.actionLabel,
    required this.online,
    this.ipAddress,
    this.screenshot,
    this.batchMode = false,
    this.selected = false,
    this.selectable = true,
    this.busy = false,
    this.phoneWidth = 132,
    this.actionIcon = LucideIcons.monitorPlay,
    this.onOpen,
    this.onInfo,
    this.onMore,
    this.onSelected,
    this.onSecondaryTapDown,
  });

  final String name;
  final String systemVersion;
  final String statusLabel;
  final String brand;
  final String coverTitle;
  final String coverHint;
  final String actionLabel;
  final bool online;
  final String? ipAddress;
  final Uint8List? screenshot;
  final bool batchMode;
  final bool selected;
  final bool selectable;
  final bool busy;
  final double phoneWidth;
  final IconData actionIcon;
  final VoidCallback? onOpen;
  final VoidCallback? onInfo;
  final VoidCallback? onMore;
  final ValueChanged<bool>? onSelected;
  final GestureTapDownCallback? onSecondaryTapDown;

  VoidCallback? get _select =>
      selectable && onSelected != null ? () => onSelected!(!selected) : null;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final compact = MediaQuery.sizeOf(context).width <= 490;
    final checked = batchMode && selected;
    return Semantics(
      container: true,
      label: '$name，$statusLabel',
      selected: batchMode ? selected : null,
      child: Material(
        color: checked ? scheme.primaryContainer : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: AppThemeSizes.radiusLarge,
          side: BorderSide(
            color: checked ? scheme.primary : Colors.transparent,
          ),
        ),
        child: InkWell(
          onTap: batchMode ? _select : null,
          onSecondaryTapDown: batchMode ? null : onSecondaryTapDown,
          hoverColor: theme.appColors.panelSurface,
          borderRadius: AppThemeSizes.radiusLarge,
          child: Padding(
            padding: compact
                ? const EdgeInsets.fromLTRB(8, 9, 8, 11)
                : const EdgeInsets.fromLTRB(10, 10, 10, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildStatus(context),
                const SizedBox(height: 10),
                DeviceWallPhone(
                  width: phoneWidth,
                  online: online,
                  screenshot: screenshot,
                  brand: brand,
                  title: coverTitle,
                  hint: coverHint,
                  semanticLabel: batchMode
                      ? '${context.l10n.t('selectDevice')} $name'
                      : '$actionLabel $name',
                  onTap: batchMode
                      ? _select
                      : busy
                      ? null
                      : onOpen,
                ),
                const SizedBox(height: 14),
                _buildCaption(context),
                const SizedBox(height: 11),
                if (batchMode)
                  const SizedBox(height: 31)
                else
                  _buildActions(context),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatus(BuildContext context) {
    final theme = Theme.of(context);
    final foreground = online
        ? theme.appColors.success
        : theme.colorScheme.onSurfaceVariant;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: phoneWidth, minHeight: 21),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (batchMode) ...[
            SizedBox.square(
              dimension: 21,
              child: Checkbox(
                value: selected,
                onChanged: selectable && onSelected != null
                    ? (value) => onSelected!(value ?? false)
                    : null,
                semanticLabel: '${context.l10n.t('selectDevice')} $name',
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
            ),
            const Spacer(),
            const SizedBox(width: 5),
          ],
          if (online && MediaQuery.sizeOf(context).width > 490) ...[
            Icon(Icons.circle, size: 5, color: foreground),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              statusLabel,
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 11, color: foreground),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCaption(BuildContext context) {
    final theme = Theme.of(context);
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final metaStyle = TextStyle(
      fontSize: 11,
      height: 17 / 11,
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ConstrainedBox(
          constraints: BoxConstraints(minHeight: 36 * textScale),
          child: InkWell(
            onTap: batchMode ? _select : onInfo,
            borderRadius: AppThemeSizes.radiusSmall,
            child: SizedBox(
              width: double.infinity,
              child: Text(
                name,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: MediaQuery.sizeOf(context).width <= 490 ? 12 : 13,
                  height: MediaQuery.sizeOf(context).width <= 490
                      ? 1.5
                      : 18 / 13,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(systemVersion, textAlign: TextAlign.center, style: metaStyle),
        Text(ipAddress ?? '', textAlign: TextAlign.center, style: metaStyle),
      ],
    );
  }

  Widget _buildActions(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Flexible(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 104),
            child: OutlinedButton(
              onPressed: busy ? null : onOpen,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 31),
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                backgroundColor: online
                    ? scheme.primaryContainer
                    : theme.appColors.panelSurface,
                foregroundColor: online
                    ? scheme.primary
                    : scheme.onSurfaceVariant,
                side: BorderSide(
                  color: online ? Colors.transparent : scheme.outlineVariant,
                ),
                shape: const RoundedRectangleBorder(
                  borderRadius: AppThemeSizes.radiusMedium,
                ),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (busy)
                    const SizedBox.square(
                      dimension: 14,
                      child: CircularProgressIndicator(strokeWidth: 1.5),
                    )
                  else if (MediaQuery.sizeOf(context).width > 490)
                    Icon(actionIcon, size: 14),
                  if (busy || MediaQuery.sizeOf(context).width > 490)
                    const SizedBox(width: 5),
                  Flexible(
                    child: Text(
                      actionLabel,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 5),
        IconButton(
          tooltip: '${context.l10n.t('deviceActions')} · $name',
          onPressed: onMore,
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints.tightFor(width: 31, height: 31),
          padding: const EdgeInsets.all(6),
          style: IconButton.styleFrom(
            shape: const RoundedRectangleBorder(
              borderRadius: AppThemeSizes.radiusMedium,
            ),
            foregroundColor: scheme.onSurfaceVariant,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          icon: const Icon(LucideIcons.ellipsis, size: 18),
        ),
      ],
    );
  }
}
