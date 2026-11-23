part of '../../dashboard_screen.dart';

/// 高级设置共用标签列。窄卡片把标签排在上一行，输入控件在缩放时保留焦点。
class _AdvancedSettingRow extends StatelessWidget {
  const _AdvancedSettingRow({required this.label, required this.controls});

  final String label;
  final List<Widget> controls;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final stacked = width < 700;
        const labelWidth = 138.0;
        const columnGap = 12.0;
        return Wrap(
          spacing: columnGap,
          runSpacing: 6,
          children: [
            SizedBox(
              width: stacked ? width : labelWidth,
              child: Padding(
                padding: EdgeInsets.only(top: stacked ? 0 : 8),
                child: Text(
                  label,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ),
            SizedBox(
              width: stacked ? width : width - labelWidth - columnGap,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: controls,
              ),
            ),
          ],
        );
      },
    );
  }
}

/// 自定义输入框和应用按钮占用同一个排版单元。
class _CustomDisplayValue extends StatelessWidget {
  const _CustomDisplayValue({required this.field, required this.onPressed});

  final Widget field;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 8,
      children: [
        field,
        OutlinedButton(
          style: _displayActionStyle(context),
          onPressed: onPressed,
          child: Text(context.l10n.t('setCustomLabel')),
        ),
      ],
    );
  }
}

/// 自定义字号、分辨率和 DPI 的数值输入框，宽度按输入格式分别指定。
class _DisplayValueField extends StatelessWidget {
  const _DisplayValueField({
    required this.width,
    required this.controller,
    this.hint,
    this.keyboardType,
    this.onSubmitted,
  });

  final double width;
  final TextEditingController controller;
  final String? hint;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final border = OutlineInputBorder(
      borderRadius: AppThemeSizes.radiusMedium,
      borderSide: BorderSide(color: theme.appColors.subtleDivider),
    );
    return SizedBox(
      width: width,
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 13),
        onSubmitted: onSubmitted,
        decoration: InputDecoration(
          isDense: true,
          hintText: hint,
          hintStyle: TextStyle(color: theme.colorScheme.onSurfaceVariant),
          fillColor: theme.appColors.subtleSurface,
          filled: true,
          contentPadding: const EdgeInsets.all(10),
          enabledBorder: border,
          border: border,
          focusedBorder: border.copyWith(
            borderSide: BorderSide(
              color: theme.colorScheme.primary,
              width: 1.5,
            ),
          ),
        ),
      ),
    );
  }
}

/// 字号、分辨率和渲染预设的选中态由设备回读值决定。
class _DisplayPresetButton extends StatelessWidget {
  const _DisplayPresetButton({
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        backgroundColor: selected ? primary : theme.appColors.subtleSurface,
        foregroundColor: selected
            ? theme.colorScheme.onPrimary
            : theme.appColors.toolbarForeground,
        side: BorderSide(
          color: selected ? primary : theme.appColors.subtleDivider,
        ),
        minimumSize: const Size(0, 40),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        shape: const RoundedRectangleBorder(
          borderRadius: AppThemeSizes.radiusMedium,
        ),
      ),
      onPressed: onPressed,
      child: Text(
        label,
        style: TextStyle(
          fontSize: 13,
          fontWeight: selected ? FontWeight.bold : FontWeight.w500,
        ),
      ),
    );
  }
}

/// 统一显示设置提交、重置及动画操作的边框、尺寸和主题色。
ButtonStyle _displayActionStyle(BuildContext context, {bool primary = true}) {
  final theme = Theme.of(context);
  return OutlinedButton.styleFrom(
    foregroundColor: primary
        ? theme.colorScheme.primary
        : theme.appColors.toolbarForeground,
    side: BorderSide(
      color: primary
          ? theme.colorScheme.primary.withValues(alpha: 0.5)
          : theme.appColors.subtleDivider,
    ),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    shape: const RoundedRectangleBorder(
      borderRadius: AppThemeSizes.radiusMedium,
    ),
  );
}

/// DPI 步进按钮共用边框和水波纹裁切形状。
class _DpiStepButton extends StatelessWidget {
  const _DpiStepButton({required this.icon, required this.onPressed});

  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shape = RoundedRectangleBorder(
      borderRadius: AppThemeSizes.radiusMedium,
      side: BorderSide(color: theme.appColors.subtleDivider),
    );
    return Material(
      color: theme.appColors.subtleSurface,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        customBorder: shape,
        onTap: onPressed,
        hoverColor: theme.colorScheme.primary.withValues(alpha: 0.08),
        splashColor: theme.colorScheme.primary.withValues(alpha: 0.16),
        highlightColor: theme.colorScheme.primary.withValues(alpha: 0.10),
        child: SizedBox.square(
          dimension: 32,
          child: Icon(
            icon,
            size: 16,
            color: onPressed == null
                ? theme.disabledColor
                : theme.appColors.toolbarForeground,
          ),
        ),
      ),
    );
  }
}

/// 动画类型标签始终跟随自己的下拉框，设备返回未知倍率时按默认值展示。
class _AnimationScaleDropdown extends StatelessWidget {
  const _AnimationScaleDropdown({
    required this.label,
    required this.currentValue,
    required this.onSelected,
  });

  final String label;
  final String currentValue;
  final ValueChanged<double> onSelected;

  @override
  Widget build(BuildContext context) {
    final options = {
      0.0: context.l10n.t('animationScaleOff'),
      0.5: '0.5x',
      1.0: context.l10n.t('animationScaleDefault'),
      1.5: '1.5x',
      2.0: '2.0x',
      5.0: '5.0x',
      10.0: '10.0x',
    };
    final current = double.tryParse(currentValue) ?? 1.0;
    final effectiveValue = options.keys.firstWhere(
      (scale) => (scale - current).abs() < 0.01,
      orElse: () => 1.0,
    );
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: theme.appColors.subtleSurface,
            borderRadius: AppThemeSizes.radiusMedium,
            border: Border.all(color: theme.appColors.subtleDivider),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<double>(
              value: effectiveValue,
              borderRadius: BorderRadius.circular(12),
              dropdownColor: theme.appColors.panelSurface,
              icon: Padding(
                padding: const EdgeInsets.only(left: 5),
                child: Icon(
                  CupertinoIcons.chevron_down,
                  size: 14,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface,
                fontWeight: FontWeight.w500,
              ),
              onChanged: (value) {
                if (value != null) onSelected(value);
              },
              items: [
                for (final entry in options.entries)
                  DropdownMenuItem<double>(
                    value: entry.key,
                    child: Text(entry.value),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
