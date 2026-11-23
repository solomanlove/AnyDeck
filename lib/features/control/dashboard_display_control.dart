part of '../dashboard_screen.dart';

/// Android 控制页的显示、渲染和动画设置，随目标设备回读当前值。
class _SystemSettingsPanel extends ConsumerStatefulWidget {
  const _SystemSettingsPanel({required this.device});

  final DiscoveredDevice device;

  @override
  ConsumerState<_SystemSettingsPanel> createState() =>
      _SystemSettingsPanelState();
}

class _SystemSettingsPanelState extends ConsumerState<_SystemSettingsPanel> {
  final _dpiController = TextEditingController();
  final _fontScaleCustomController = TextEditingController();
  final _displaySizeCustomController = TextEditingController();

  String get _deviceId => widget.device.id;
  DeviceActionService get _actions => ref.read(deviceActionServiceProvider);

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
    if (_deviceId != oldWidget.device.id) {
      _dpiController.clear();
      _fontScaleCustomController.clear();
      _displaySizeCustomController.clear();
    }
  }

  /// 写入后刷新发起操作的设备，切换设备时不会把旧结果写入新页面。
  Future<void> _apply(Future<AdbResult> operation) async {
    final deviceId = _deviceId;
    await _runAdbAction(context, ref, operation);
    if (mounted) {
      ref.invalidate(deviceOverviewProvider(deviceId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final overviewAsync = widget.device.isOnline
        ? ref.watch(deviceOverviewProvider(_deviceId))
        : const AsyncValue<DeviceOverview>.loading();
    return overviewAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (err, stack) => const SizedBox.shrink(),
      data: (overview) {
        final dpiMatch = RegExp(
          r'\((\d+)dpi\)',
        ).firstMatch(overview.resolution);
        final currentDpi = int.tryParse(dpiMatch?.group(1) ?? '');
        if (currentDpi != null &&
            _dpiController.text != currentDpi.toString() &&
            !FocusScope.of(context).hasFocus) {
          _dpiController.text = currentDpi.toString();
        }
        final rows = [
          _fontScaleRow(overview),
          _resolutionRow(overview),
          _densityRow(currentDpi),
          _renderingRow('hwuiRenderingBarsLabel', 'visual_bars', overview),
          _renderingRow('profileGpuRenderingLabel', 'true', overview),
          _animationRow(overview),
        ];
        final title = context.l10n.t('systemSettings');
        final theme = Theme.of(context);
        return _GlassSectionCard(
          title: title,
          icon: CupertinoIcons.settings,
          children: [
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0)
                Divider(
                  height: 24,
                  thickness: 0.5,
                  color: theme.appColors.softDivider,
                ),
              rows[i],
            ],
          ],
        );
      },
    );
  }

  Widget _fontScaleRow(DeviceOverview overview) {
    final current =
        double.tryParse(overview.fontScale.replaceAll('x', '')) ?? 1;
    return _AdvancedSettingRow(
      label: context.l10n.t('fontScaleLabel'),
      controls: [
        for (final preset in const [0.80, 1.00, 1.20, 1.40, 1.60])
          _DisplayPresetButton(
            label: preset.toStringAsFixed(2),
            selected: (current - preset).abs() < 0.01,
            onPressed: () => _apply(_actions.setFontScale(_deviceId, preset)),
          ),
        _CustomDisplayValue(
          field: _DisplayValueField(
            width: 70,
            controller: _fontScaleCustomController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          onPressed: () {
            final value = double.tryParse(_fontScaleCustomController.text);
            if (value != null && value >= 0.3 && value <= 4.0) {
              _apply(_actions.setFontScale(_deviceId, value));
            } else {
              _showSnack(
                context,
                context.l10n.t('invalidControlFontScale'),
                isError: true,
              );
            }
          },
        ),
      ],
    );
  }

  Widget _resolutionRow(DeviceOverview overview) {
    return _AdvancedSettingRow(
      label: context.l10n.t('displaySizeLabel'),
      controls: [
        _DisplayPresetButton(
          label: context.l10n.t('resetLabel'),
          selected: overview.resolution == overview.physicalResolution,
          onPressed: () => _apply(_actions.resetDisplaySize(_deviceId)),
        ),
        for (final preset in const [
          '480x800',
          '720x1280',
          '1080x1920',
          '1440x3200',
        ])
          _DisplayPresetButton(
            label: preset,
            selected: overview.rawResolution == preset,
            onPressed: () => _apply(_actions.setDisplaySize(_deviceId, preset)),
          ),
        _CustomDisplayValue(
          field: _DisplayValueField(
            width: 100,
            controller: _displaySizeCustomController,
            hint: 'WxH',
          ),
          onPressed: () {
            final value = _displaySizeCustomController.text.trim();
            if (RegExp(r'^\d+x\d+$').hasMatch(value)) {
              _apply(_actions.setDisplaySize(_deviceId, value));
            } else {
              _showSnack(
                context,
                context.l10n.t('invalidControlResolution'),
                isError: true,
              );
            }
          },
        ),
      ],
    );
  }

  void _submitDensity(String text) {
    final value = int.tryParse(text);
    if (value != null && value >= 80 && value <= 1000) {
      _apply(_actions.setDisplayDensity(_deviceId, value));
    }
  }

  Widget _densityRow(int? currentDpi) {
    return _AdvancedSettingRow(
      label: context.l10n.t('displayDensityLabel'),
      controls: [
        // 加减键和数值属于同一个步进控件，换行时整体移动。
        Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 8,
          children: [
            _DpiStepButton(
              icon: CupertinoIcons.minus,
              onPressed: currentDpi == null
                  ? null
                  : () {
                      if (currentDpi - 10 > 80) {
                        _apply(
                          _actions.setDisplayDensity(
                            _deviceId,
                            currentDpi - 10,
                          ),
                        );
                      }
                    },
            ),
            _DisplayValueField(
              width: 70,
              controller: _dpiController,
              keyboardType: TextInputType.number,
              onSubmitted: _submitDensity,
            ),
            _DpiStepButton(
              icon: CupertinoIcons.plus,
              onPressed: currentDpi == null
                  ? null
                  : () {
                      if (currentDpi + 10 < 1000) {
                        _apply(
                          _actions.setDisplayDensity(
                            _deviceId,
                            currentDpi + 10,
                          ),
                        );
                      }
                    },
            ),
          ],
        ),
        OutlinedButton(
          style: _displayActionStyle(context),
          onPressed: () => _submitDensity(_dpiController.text),
          child: Text(context.l10n.t('send')),
        ),
        OutlinedButton(
          style: _displayActionStyle(context, primary: false),
          onPressed: () => _apply(_actions.resetDisplayDensity(_deviceId)),
          child: Text(context.l10n.t('displayDensityReset')),
        ),
      ],
    );
  }

  Widget _renderingRow(String labelKey, String mode, DeviceOverview overview) {
    return _AdvancedSettingRow(
      label: context.l10n.t(labelKey),
      controls: [
        _DisplayPresetButton(
          label: context.l10n.t('onLabel'),
          selected: overview.hwuiProfile == mode,
          onPressed: () => _apply(_actions.setHwuiProfile(_deviceId, mode)),
        ),
        _DisplayPresetButton(
          label: context.l10n.t('offLabel'),
          selected: overview.hwuiProfile != mode,
          onPressed: () => _apply(_actions.setHwuiProfile(_deviceId, 'false')),
        ),
      ],
    );
  }

  /// 三个动画设置独立写入；批量操作沿用第一项失败结果的反馈。
  void _setAllAnimations(double scale) {
    _apply(
      Future.wait([
        _actions.setWindowAnimationScale(_deviceId, scale),
        _actions.setTransitionAnimationScale(_deviceId, scale),
        _actions.setAnimatorDurationScale(_deviceId, scale),
      ]).then(
        (results) => results.firstWhere(
          (result) => !result.isSuccess,
          orElse: () => results.first,
        ),
      ),
    );
  }

  Widget _animationRow(DeviceOverview overview) {
    return _AdvancedSettingRow(
      label: context.l10n.t('animationScaleLabel'),
      controls: [
        _AnimationScaleDropdown(
          label: context.l10n.t('windowAnimationScale'),
          currentValue: overview.windowAnimationScale,
          onSelected: (value) =>
              _apply(_actions.setWindowAnimationScale(_deviceId, value)),
        ),
        _AnimationScaleDropdown(
          label: context.l10n.t('transitionAnimationScale'),
          currentValue: overview.transitionAnimationScale,
          onSelected: (value) =>
              _apply(_actions.setTransitionAnimationScale(_deviceId, value)),
        ),
        _AnimationScaleDropdown(
          label: context.l10n.t('animatorDurationScale'),
          currentValue: overview.animatorDurationScale,
          onSelected: (value) =>
              _apply(_actions.setAnimatorDurationScale(_deviceId, value)),
        ),
        FilledButton.icon(
          icon: const Icon(CupertinoIcons.bolt_slash),
          label: Text(context.l10n.t('disableAllAnimations')),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            shape: const RoundedRectangleBorder(
              borderRadius: AppThemeSizes.radiusMedium,
            ),
          ),
          onPressed: () => _setAllAnimations(0),
        ),
        OutlinedButton.icon(
          icon: const Icon(CupertinoIcons.refresh),
          label: Text(context.l10n.t('resetAllAnimations')),
          style: _displayActionStyle(context, primary: false),
          onPressed: () => _setAllAnimations(1),
        ),
      ],
    );
  }
}
