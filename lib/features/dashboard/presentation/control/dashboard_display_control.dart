part of '../dashboard_screen.dart';

class _SystemSettingsPanel extends ConsumerStatefulWidget {
  const _SystemSettingsPanel({required this.device});

  final AdbDevice device;

  @override
  ConsumerState<_SystemSettingsPanel> createState() =>
      _SystemSettingsPanelState();
}

class _SystemSettingsPanelState extends ConsumerState<_SystemSettingsPanel> {
  final TextEditingController _dpiController = TextEditingController();
  final TextEditingController _fontScaleCustomController =
      TextEditingController();
  final TextEditingController _displaySizeCustomController =
      TextEditingController();

  @override
  void dispose() {
    _dpiController.dispose();
    _fontScaleCustomController.dispose();
    _displaySizeCustomController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _SystemSettingsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.device.id != oldWidget.device.id) {
      _dpiController.clear();
      _fontScaleCustomController.clear();
      _displaySizeCustomController.clear();
    }
  }

  int? _parseDpi(String resolutionText) {
    final match = RegExp(r'\((\d+)dpi\)').firstMatch(resolutionText);
    if (match != null) {
      return int.tryParse(match.group(1)!);
    }
    return null;
  }

  // 统一的高级质感输入框装饰器
  InputDecoration _buildInputDecoration(String? hintText) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return InputDecoration(
      isDense: true,
      hintText: hintText,
      hintStyle: TextStyle(
        color: isDark ? Colors.white.withValues(alpha: 0.3) : Colors.black.withValues(alpha: 0.3),
        fontSize: 13,
      ),
      fillColor: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.black.withValues(alpha: 0.02),
      filled: true,
      contentPadding: const EdgeInsets.symmetric(
        vertical: 10,
        horizontal: 10,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(
          color: isDark ? Colors.white12 : Colors.black12,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(
          color: theme.colorScheme.primary,
          width: 1.5,
        ),
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
      ),
    );
  }

  // 统一的高级预设按钮
  Widget _buildPresetButton({
    required String label,
    required bool isActive,
    required VoidCallback onPressed,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        boxShadow: isActive
            ? [
                BoxShadow(
                  color: theme.colorScheme.primary.withValues(alpha: 0.25),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                )
              ]
            : null,
      ),
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          backgroundColor: isActive
              ? theme.colorScheme.primary
              : (isDark ? Colors.white.withValues(alpha: 0.04) : Colors.black.withValues(alpha: 0.02)),
          foregroundColor: isActive
              ? theme.colorScheme.onPrimary
              : (isDark ? Colors.white70 : Colors.black87),
          side: BorderSide(
            color: isActive
                ? theme.colorScheme.primary
                : (isDark ? Colors.white12 : Colors.black12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        onPressed: onPressed,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final overviewAsync = widget.device.isOnline
        ? ref.watch(deviceOverviewProvider(widget.device.id))
        : const AsyncValue<DeviceOverview>.loading();

    return overviewAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (err, stack) => const SizedBox.shrink(),
      data: (overview) {
        final theme = Theme.of(context);
        final isDark = theme.brightness == Brightness.dark;

        // 解析并更新 DPI
        final currentDpi = _parseDpi(overview.resolution);
        if (currentDpi != null &&
            _dpiController.text != currentDpi.toString() &&
            !FocusScope.of(context).hasFocus) {
          _dpiController.text = currentDpi.toString();
        }

        // 解析字体缩放值
        final double fontScaleNum =
            double.tryParse(overview.fontScale.replaceAll('x', '')) ?? 1.0;

        final actions = ref.read(deviceActionServiceProvider);

        // 将普通卡片背景替换为与主页一致的毛玻璃卡片背景
        return _GlassSectionCard(
          title: context.l10n.t('systemSettings'),
          icon: CupertinoIcons.settings,
          children: [
            Text(
              context.l10n.t('systemSettings'),
              style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 16),

            // 1. 字体缩放 (Font Scale)
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: 150,
                  child: Text(
                    context.l10n.t('fontScaleLabel'),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                Expanded(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      ...[0.80, 1.00, 1.20, 1.40, 1.60].map((preset) {
                        final isActive =
                            (fontScaleNum - preset).abs() < 0.01;
                        return _buildPresetButton(
                          label: preset.toStringAsFixed(2),
                          isActive: isActive,
                          onPressed: () async {
                            await _runAdbAction(
                              context,
                              ref,
                              actions.setFontScale(
                                widget.device.id,
                                preset,
                              ),
                            );
                            ref.invalidate(
                              deviceOverviewProvider(widget.device.id),
                            );
                          },
                        );
                      }),
                      SizedBox(
                        width: 70,
                        child: TextField(
                          controller: _fontScaleCustomController,
                          keyboardType:
                              const TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 13),
                          decoration: _buildInputDecoration(null),
                        ),
                      ),
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: theme.colorScheme.primary,
                          side: BorderSide(
                            color: theme.colorScheme.primary.withValues(alpha: 0.5),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onPressed: () async {
                          final customVal = double.tryParse(
                            _fontScaleCustomController.text,
                          );
                          if (customVal != null &&
                              customVal >= 0.3 &&
                              customVal <= 4.0) {
                            await _runAdbAction(
                              context,
                              ref,
                              actions.setFontScale(
                                widget.device.id,
                                customVal,
                              ),
                            );
                            ref.invalidate(
                              deviceOverviewProvider(widget.device.id),
                            );
                          } else {
                            _showSnack(
                              context,
                              'Invalid font scale (0.3 - 4.0)',
                              isError: true,
                            );
                          }
                        },
                        child: Text(context.l10n.t('setCustomLabel')),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            Divider(height: 28, thickness: 0.5, color: isDark ? Colors.white10 : Colors.black12),

            // 2. 显示大小/分辨率 (Display Size / Resolution)
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: 150,
                  child: Text(
                    context.l10n.t('displaySizeLabel'),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                Expanded(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _buildPresetButton(
                        label: context.l10n.t('resetLabel'),
                        isActive:
                            overview.resolution ==
                            overview.physicalResolution,
                        onPressed: () async {
                          await _runAdbAction(
                            context,
                            ref,
                            actions.resetDisplaySize(widget.device.id),
                          );
                          ref.invalidate(
                            deviceOverviewProvider(widget.device.id),
                          );
                        },
                      ),
                      ...[
                        '480x800',
                        '720x1280',
                        '1080x1920',
                        '1440x3200',
                      ].map((preset) {
                        final isActive = overview.rawResolution == preset;
                        return _buildPresetButton(
                          label: preset,
                          isActive: isActive,
                          onPressed: () async {
                            await _runAdbAction(
                              context,
                              ref,
                              actions.setDisplaySize(
                                widget.device.id,
                                preset,
                              ),
                            );
                            ref.invalidate(
                              deviceOverviewProvider(widget.device.id),
                            );
                          },
                        );
                      }),
                      SizedBox(
                        width: 100,
                        child: TextField(
                          controller: _displaySizeCustomController,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 13),
                          decoration: _buildInputDecoration('WxH'),
                        ),
                      ),
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: theme.colorScheme.primary,
                          side: BorderSide(
                            color: theme.colorScheme.primary.withValues(alpha: 0.5),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onPressed: () async {
                          final sizeVal = _displaySizeCustomController.text
                              .trim();
                          if (RegExp(r'^\d+x\d+$').hasMatch(sizeVal)) {
                            await _runAdbAction(
                              context,
                              ref,
                              actions.setDisplaySize(
                                widget.device.id,
                                sizeVal,
                              ),
                            );
                            ref.invalidate(
                              deviceOverviewProvider(widget.device.id),
                            );
                          } else {
                            _showSnack(
                              context,
                              'Invalid display size (Format: WxH)',
                              isError: true,
                            );
                          }
                        },
                        child: Text(context.l10n.t('setCustomLabel')),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            Divider(height: 28, thickness: 0.5, color: isDark ? Colors.white10 : Colors.black12),

            // 3. 显示大小/密度 (Display Density / DPI)
            Row(
              children: [
                SizedBox(
                  width: 150,
                  child: Text(
                    context.l10n.t('displayDensityLabel'),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 6),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.black.withValues(alpha: 0.02),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isDark ? Colors.white12 : Colors.black12,
                    ),
                  ),
                  child: IconButton(
                    icon: const Icon(CupertinoIcons.minus, size: 16),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                    onPressed: currentDpi == null
                        ? null
                        : () async {
                            final target = currentDpi - 10;
                            if (target > 80) {
                              await _runAdbAction(
                                context,
                                ref,
                                actions.setDisplayDensity(
                                  widget.device.id,
                                  target,
                                ),
                              );
                              ref.invalidate(
                                deviceOverviewProvider(widget.device.id),
                              );
                            }
                          },
                  ),
                ),
                const SizedBox(width: 4),
                SizedBox(
                  width: 70,
                  child: TextField(
                    controller: _dpiController,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 13),
                    decoration: _buildInputDecoration(null),
                    onSubmitted: (val) async {
                      final numVal = int.tryParse(val);
                      if (numVal != null &&
                          numVal >= 80 &&
                          numVal <= 1000) {
                        await _runAdbAction(
                          context,
                          ref,
                          actions.setDisplayDensity(
                            widget.device.id,
                            numVal,
                          ),
                        );
                        ref.invalidate(
                          deviceOverviewProvider(widget.device.id),
                        );
                      }
                    },
                  ),
                ),
                const SizedBox(width: 4),
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 6),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.black.withValues(alpha: 0.02),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isDark ? Colors.white12 : Colors.black12,
                    ),
                  ),
                  child: IconButton(
                    icon: const Icon(CupertinoIcons.plus, size: 16),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                    onPressed: currentDpi == null
                        ? null
                        : () async {
                            final target = currentDpi + 10;
                            if (target < 1000) {
                              await _runAdbAction(
                                context,
                                ref,
                                actions.setDisplayDensity(
                                  widget.device.id,
                                  target,
                                ),
                              );
                              ref.invalidate(
                                deviceOverviewProvider(widget.device.id),
                              );
                            }
                          },
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: theme.colorScheme.primary,
                    side: BorderSide(
                      color: theme.colorScheme.primary.withValues(alpha: 0.5),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: () async {
                    final numVal = int.tryParse(_dpiController.text);
                    if (numVal != null && numVal >= 80 && numVal <= 1000) {
                      await _runAdbAction(
                        context,
                        ref,
                        actions.setDisplayDensity(widget.device.id, numVal),
                      );
                      ref.invalidate(
                        deviceOverviewProvider(widget.device.id),
                      );
                    }
                  },
                  child: Text(context.l10n.t('send')),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: isDark ? Colors.white70 : Colors.black87,
                    side: BorderSide(
                      color: isDark ? Colors.white12 : Colors.black12,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: () async {
                    await _runAdbAction(
                      context,
                      ref,
                      actions.resetDisplayDensity(widget.device.id),
                    );
                    ref.invalidate(
                      deviceOverviewProvider(widget.device.id),
                    );
                  },
                  child: Text(context.l10n.t('displayDensityReset')),
                ),
              ],
            ),
            Divider(height: 28, thickness: 0.5, color: isDark ? Colors.white10 : Colors.black12),

            // 4. HWUI Rendering Bars
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: 150,
                  child: Text(
                    context.l10n.t('hwuiRenderingBarsLabel'),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    _buildPresetButton(
                      label: context.l10n.t('onLabel'),
                      isActive: overview.hwuiProfile == 'visual_bars',
                      onPressed: () async {
                        await _runAdbAction(
                          context,
                          ref,
                          actions.setHwuiProfile(
                            widget.device.id,
                            'visual_bars',
                          ),
                        );
                        ref.invalidate(
                          deviceOverviewProvider(widget.device.id),
                        );
                      },
                    ),
                    _buildPresetButton(
                      label: context.l10n.t('offLabel'),
                      isActive: overview.hwuiProfile != 'visual_bars',
                      onPressed: () async {
                        await _runAdbAction(
                          context,
                          ref,
                          actions.setHwuiProfile(widget.device.id, 'false'),
                        );
                        ref.invalidate(
                          deviceOverviewProvider(widget.device.id),
                        );
                      },
                    ),
                  ],
                ),
              ],
            ),
            Divider(height: 28, thickness: 0.5, color: isDark ? Colors.white10 : Colors.black12),

            // 5. Profile GPU Rendering
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: 150,
                  child: Text(
                    context.l10n.t('profileGpuRenderingLabel'),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    _buildPresetButton(
                      label: context.l10n.t('onLabel'),
                      isActive: overview.hwuiProfile == 'true',
                      onPressed: () async {
                        await _runAdbAction(
                          context,
                          ref,
                          actions.setHwuiProfile(widget.device.id, 'true'),
                        );
                        ref.invalidate(
                          deviceOverviewProvider(widget.device.id),
                        );
                      },
                    ),
                    _buildPresetButton(
                      label: context.l10n.t('offLabel'),
                      isActive: overview.hwuiProfile != 'true',
                      onPressed: () async {
                        await _runAdbAction(
                          context,
                          ref,
                          actions.setHwuiProfile(widget.device.id, 'false'),
                        );
                        ref.invalidate(
                          deviceOverviewProvider(widget.device.id),
                        );
                      },
                    ),
                  ],
                ),
              ],
            ),
            Divider(height: 28, thickness: 0.5, color: isDark ? Colors.white10 : Colors.black12),

            // 6. 动画缩放 (Animation Scale)
            Text(
              context.l10n.t('animationScaleLabel'),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 24,
              runSpacing: 12,
              children: [
                _buildAnimDropdown(
                  context,
                  label: context.l10n.t('windowAnimationScale'),
                  currentVal: overview.windowAnimationScale,
                  onChanged: (val) async {
                    if (val != null) {
                      await _runAdbAction(
                        context,
                        ref,
                        actions.setWindowAnimationScale(
                          widget.device.id,
                          val,
                        ),
                      );
                      ref.invalidate(
                        deviceOverviewProvider(widget.device.id),
                      );
                    }
                  },
                ),
                _buildAnimDropdown(
                  context,
                  label: context.l10n.t('transitionAnimationScale'),
                  currentVal: overview.transitionAnimationScale,
                  onChanged: (val) async {
                    if (val != null) {
                      await _runAdbAction(
                        context,
                        ref,
                        actions.setTransitionAnimationScale(
                          widget.device.id,
                          val,
                        ),
                      );
                      ref.invalidate(
                        deviceOverviewProvider(widget.device.id),
                      );
                    }
                  },
                ),
                _buildAnimDropdown(
                  context,
                  label: context.l10n.t('animatorDurationScale'),
                  currentVal: overview.animatorDurationScale,
                  onChanged: (val) async {
                    if (val != null) {
                      await _runAdbAction(
                        context,
                        ref,
                        actions.setAnimatorDurationScale(
                          widget.device.id,
                          val,
                        ),
                      );
                      ref.invalidate(
                        deviceOverviewProvider(widget.device.id),
                      );
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                FilledButton.icon(
                  icon: const Icon(CupertinoIcons.bolt_slash),
                  label: Text(context.l10n.t('disableAllAnimations')),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: () async {
                    await _runAdbAction(
                      context,
                      ref,
                      Future.wait([
                        actions.setWindowAnimationScale(
                          widget.device.id,
                          0.0,
                        ),
                        actions.setTransitionAnimationScale(
                          widget.device.id,
                          0.0,
                        ),
                        actions.setAnimatorDurationScale(
                          widget.device.id,
                          0.0,
                        ),
                      ]).then(
                        (results) => results.firstWhere(
                          (r) => !r.isSuccess,
                          orElse: () => results.first,
                        ),
                      ),
                    );
                    ref.invalidate(
                      deviceOverviewProvider(widget.device.id),
                    );
                  },
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  icon: const Icon(CupertinoIcons.refresh),
                  label: Text(context.l10n.t('resetAllAnimations')),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: isDark ? Colors.white70 : Colors.black87,
                    side: BorderSide(
                      color: isDark ? Colors.white12 : Colors.black12,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: () async {
                    await _runAdbAction(
                      context,
                      ref,
                      Future.wait([
                        actions.setWindowAnimationScale(
                          widget.device.id,
                          1.0,
                        ),
                        actions.setTransitionAnimationScale(
                          widget.device.id,
                          1.0,
                        ),
                        actions.setAnimatorDurationScale(
                          widget.device.id,
                          1.0,
                        ),
                      ]).then(
                        (results) => results.firstWhere(
                          (r) => !r.isSuccess,
                          orElse: () => results.first,
                        ),
                      ),
                    );
                    ref.invalidate(
                      deviceOverviewProvider(widget.device.id),
                    );
                  },
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _buildAnimDropdown(
    BuildContext context, {
    required String label,
    required String currentVal,
    required ValueChanged<double?> onChanged,
  }) {
    final options = {
      0.0: context.l10n.t('animationScaleOff'),
      0.5: '0.5x',
      1.0: context.l10n.t('animationScaleDefault'),
      1.5: '1.5x',
      2.0: '2.0x',
      5.0: '5.0x',
      10.0: '10.0x',
    };

    final double? parsedVal = double.tryParse(currentVal);
    final effectiveVal = options.keys.firstWhere(
      (k) => (k - (parsedVal ?? 1.0)).abs() < 0.01,
      orElse: () => 1.0,
    );

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: isDark ? Colors.white.withValues(alpha: 0.5) : Colors.black.withValues(alpha: 0.5),
          ),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.black.withValues(alpha: 0.02),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isDark ? Colors.white12 : Colors.black12,
            ),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<double>(
              value: effectiveVal,
              borderRadius: BorderRadius.circular(12),
              dropdownColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
              icon: Padding(
                padding: const EdgeInsets.only(left: 5),
                child: Icon(
                  CupertinoIcons.chevron_down,
                  size: 14,
                  color: isDark ? Colors.white70 : Colors.black.withValues(alpha: 0.5),
                ),
              ),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface,
                fontWeight: FontWeight.w500,
              ),
              onChanged: onChanged,
              items: options.entries.map((entry) {
                return DropdownMenuItem<double>(
                  value: entry.key,
                  child: Text(entry.value),
                );
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }
}
