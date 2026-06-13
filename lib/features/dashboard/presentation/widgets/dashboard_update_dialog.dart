part of '../dashboard_screen.dart';

/// 软件版本检查与更新弹窗，提供完整的模拟下载和安装体验。
class _UpdateCheckDialog extends StatefulWidget {
  const _UpdateCheckDialog();

  @override
  State<_UpdateCheckDialog> createState() => _UpdateCheckDialogState();
}

enum _UpdateStatus {
  checking,
  noUpdate,
  hasUpdate,
  downloading,
  installing,
  success,
}

class _UpdateCheckDialogState extends State<_UpdateCheckDialog>
    with SingleTickerProviderStateMixin {
  _UpdateStatus _status = _UpdateStatus.checking;
  double _progress = 0.0;
  Timer? _timer;
  late AnimationController _rotationController;

  @override
  void initState() {
    super.initState();
    // 用于检查更新和安装时的旋转动画
    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
    _startChecking();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _rotationController.dispose();
    super.dispose();
  }

  /// 模拟检查更新的异步网络请求流程
  void _startChecking() {
    setState(() {
      _status = _UpdateStatus.checking;
    });
    Future.delayed(const Duration(milliseconds: 1800), () {
      if (!mounted) return;
      setState(() {
        // 发现新版本 v1.0.1
        _status = _UpdateStatus.hasUpdate;
      });
    });
  }

  /// 模拟下载更新包的进度更新
  void _startDownload() {
    setState(() {
      _status = _UpdateStatus.downloading;
      _progress = 0.0;
    });
    _timer = Timer.periodic(const Duration(milliseconds: 80), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _progress += 0.04;
        if (_progress >= 1.0) {
          _progress = 1.0;
          timer.cancel();
          _startInstalling();
        }
      });
    });
  }

  /// 模拟解压与安装包的校验流程
  void _startInstalling() {
    setState(() {
      _status = _UpdateStatus.installing;
    });
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (!mounted) return;
      setState(() {
        _status = _UpdateStatus.success;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    const brandGreen = Color(0xff09c47c);

    return Dialog(
      backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Padding(
          padding: const EdgeInsets.all(28.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildHeaderIcon(brandGreen),
              const SizedBox(height: 24),
              _buildTitle(theme, isDark),
              const SizedBox(height: 16),
              _buildContent(theme, isDark, brandGreen),
              const SizedBox(height: 28),
              _buildActions(context, theme, isDark, brandGreen),
            ],
          ),
        ),
      ),
    );
  }

  /// 头部图标构建器，支持旋转及不同状态的过渡
  Widget _buildHeaderIcon(Color brandGreen) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: _status == _UpdateStatus.checking ||
              _status == _UpdateStatus.installing
          ? RotationTransition(
              turns: _rotationController,
              child: Container(
                key: const ValueKey('spinner'),
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: brandGreen.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  CupertinoIcons.arrow_2_circlepath,
                  color: brandGreen,
                  size: 32,
                ),
              ),
            )
          : Container(
              key: ValueKey(_status),
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: _status == _UpdateStatus.success ||
                        _status == _UpdateStatus.noUpdate
                    ? brandGreen.withValues(alpha: 0.1)
                    : brandGreen.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _status == _UpdateStatus.success ||
                        _status == _UpdateStatus.noUpdate
                    ? CupertinoIcons.checkmark_seal_fill
                    : CupertinoIcons.arrow_down_circle_fill,
                color: brandGreen,
                size: 36,
              ),
            ),
    );
  }

  /// 标题文案构建
  Widget _buildTitle(ThemeData theme, bool isDark) {
    String title = '';
    switch (_status) {
      case _UpdateStatus.checking:
        title = context.l10n.t('checkUpdate');
        break;
      case _UpdateStatus.noUpdate:
        title = context.l10n.t('currentIsLatest');
        break;
      case _UpdateStatus.hasUpdate:
        title = context.l10n
            .t('updateAvailable')
            .replaceAll('{version}', 'v1.0.1');
        break;
      case _UpdateStatus.downloading:
        title = context.l10n.t('downloading').replaceAll(
              '{progress}',
              (_progress * 100).toInt().toString(),
            );
        break;
      case _UpdateStatus.installing:
        title = context.l10n.t('installing');
        break;
      case _UpdateStatus.success:
        title = context.l10n.t('updateSuccess');
        break;
    }

    return Text(
      title,
      style: theme.textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.bold,
        color: isDark ? Colors.white : Colors.black87,
      ),
      textAlign: TextAlign.center,
    );
  }

  /// 内容区域构建，包括更新日志、下载进度条、安装进度
  Widget _buildContent(ThemeData theme, bool isDark, Color brandGreen) {
    if (_status == _UpdateStatus.checking) {
      return Text(
        context.l10n.t('checkingUpdate'),
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
        textAlign: TextAlign.center,
      );
    }

    if (_status == _UpdateStatus.noUpdate) {
      return Text(
        'v1.0.0\n${context.l10n.t('currentIsLatest')}',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
        textAlign: TextAlign.center,
      );
    }

    if (_status == _UpdateStatus.hasUpdate) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withValues(alpha: 0.05)
              : Colors.black.withValues(alpha: 0.02),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark ? const Color(0xff334155) : const Color(0xffe2e8f0),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(CupertinoIcons.doc_text, size: 16, color: brandGreen),
                const SizedBox(width: 8),
                Text(
                  context.l10n.t('updateLog'),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const Divider(height: 20),
            Text(
              context.l10n.t('updateLogDetail'),
              style: theme.textTheme.bodySmall?.copyWith(
                height: 1.6,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    if (_status == _UpdateStatus.downloading) {
      return Column(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: _progress,
              backgroundColor: isDark
                  ? const Color(0xff334155)
                  : const Color(0xffe2e8f0),
              valueColor: AlwaysStoppedAnimation<Color>(brandGreen),
              minHeight: 8,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${(_progress * 24.8).toStringAsFixed(1)} MB / 24.8 MB',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              Text(
                _progress >= 1.0
                    ? context.l10n.t('downloadComplete')
                    : '1.8 MB/s',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: brandGreen,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      );
    }

    if (_status == _UpdateStatus.installing) {
      return Text(
        context.l10n.t('installing'),
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
        textAlign: TextAlign.center,
      );
    }

    if (_status == _UpdateStatus.success) {
      return Text(
        context.l10n.t('updateSuccessDesc'),
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
        textAlign: TextAlign.center,
      );
    }

    return const SizedBox.shrink();
  }

  /// 底部按钮交互区域
  Widget _buildActions(
    BuildContext context,
    ThemeData theme,
    bool isDark,
    Color brandGreen,
  ) {
    if (_status == _UpdateStatus.checking ||
        _status == _UpdateStatus.downloading ||
        _status == _UpdateStatus.installing) {
      return const SizedBox.shrink();
    }

    if (_status == _UpdateStatus.noUpdate) {
      return SizedBox(
        width: double.infinity,
        height: 44,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: brandGreen,
            foregroundColor: Colors.white,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.l10n.t('close')),
        ),
      );
    }

    if (_status == _UpdateStatus.hasUpdate) {
      return Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 44,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  side: BorderSide(
                    color: isDark
                        ? const Color(0xff334155)
                        : const Color(0xffcbd5e1),
                  ),
                  foregroundColor: isDark ? Colors.white70 : Colors.black87,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () => Navigator.of(context).pop(),
                child: Text(context.l10n.t('later')),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: SizedBox(
              height: 44,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: brandGreen,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _startDownload,
                child: Text(context.l10n.t('updateNow')),
              ),
            ),
          ),
        ],
      );
    }

    if (_status == _UpdateStatus.success) {
      return SizedBox(
        width: double.infinity,
        height: 44,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: brandGreen,
            foregroundColor: Colors.white,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onPressed: () {
            Navigator.of(context).pop();
          },
          child: Text(context.l10n.t('restartApp')),
        ),
      );
    }

    return const SizedBox.shrink();
  }
}
