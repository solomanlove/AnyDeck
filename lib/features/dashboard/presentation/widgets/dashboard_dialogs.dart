part of '../dashboard_screen.dart';

class _SettingsDialog extends ConsumerWidget {
  const _SettingsDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    final controller = ref.read(appSettingsProvider.notifier);

    return AlertDialog(
      title: Text(context.l10n.t('settings')),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<AppLanguage>(
              initialValue: settings.language,
              decoration: InputDecoration(
                labelText: context.l10n.t('language'),
              ),
              items: [
                DropdownMenuItem(
                  value: AppLanguage.zh,
                  child: Text(context.l10n.t('chinese')),
                ),
                DropdownMenuItem(
                  value: AppLanguage.en,
                  child: Text(context.l10n.t('english')),
                ),
              ],
              onChanged: (value) {
                if (value != null) {
                  controller.setLanguage(value);
                }
              },
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<ThemeMode>(
              initialValue: settings.themeMode,
              decoration: InputDecoration(labelText: context.l10n.t('theme')),
              items: [
                DropdownMenuItem(
                  value: ThemeMode.system,
                  child: Text(context.l10n.t('themeSystem')),
                ),
                DropdownMenuItem(
                  value: ThemeMode.light,
                  child: Text(context.l10n.t('themeLight')),
                ),
                DropdownMenuItem(
                  value: ThemeMode.dark,
                  child: Text(context.l10n.t('themeDark')),
                ),
              ],
              onChanged: (value) {
                if (value != null) {
                  controller.setThemeMode(value);
                }
              },
            ),
            const SizedBox(height: 8),
            const Divider(),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(CupertinoIcons.person),
              title: Text(context.l10n.t('authorInfo')),
              trailing: const Icon(CupertinoIcons.chevron_right),
              onTap: () => showDialog<void>(
                context: context,
                builder: (_) => const _AuthorInfoDialog(),
              ),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(CupertinoIcons.book),
              title: Text(context.l10n.t('softwareManual')),
              trailing: const Icon(CupertinoIcons.chevron_right),
              onTap: () => showDialog<void>(
                context: context,
                builder: (_) => const _SoftwareManualDialog(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.l10n.t('close')),
        ),
      ],
    );
  }
}

/// 作者信息弹窗，保持设置页内的轻量信息入口。
class _AuthorInfoDialog extends StatelessWidget {
  const _AuthorInfoDialog();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.l10n.t('authorInfo')),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _InfoLine(
              label: context.l10n.t('authorNameLabel'),
              value: context.l10n.t('authorName'),
            ),
            const SizedBox(height: 8),
            _InfoLine(
              label: context.l10n.t('authorRoleLabel'),
              value: context.l10n.t('authorRole'),
            ),
            const SizedBox(height: 16),
            Text(context.l10n.t('authorDescription')),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.l10n.t('close')),
        ),
      ],
    );
  }
}

/// 软件说明书弹窗，覆盖启动前准备和常用调试流程。
class _SoftwareManualDialog extends StatelessWidget {
  const _SoftwareManualDialog();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.l10n.t('softwareManual')),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ManualSection(
                title: context.l10n.t('softwareOverviewTitle'),
                body: context.l10n.t('softwareOverview'),
              ),
              _ManualSection(
                title: context.l10n.t('softwareRequirementsTitle'),
                body: context.l10n.t('softwareRequirements'),
              ),
              _ManualSection(
                title: context.l10n.t('softwareWorkflowTitle'),
                body: context.l10n.t('softwareWorkflow'),
              ),
              _ManualSection(
                title: context.l10n.t('softwareNoticeTitle'),
                body: context.l10n.t('softwareNotice'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.l10n.t('close')),
        ),
      ],
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 72, child: Text(label, style: textTheme.bodyMedium)),
        Expanded(
          child: Text(
            value,
            style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

class _ManualSection extends StatelessWidget {
  const _ManualSection({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(body),
        ],
      ),
    );
  }
}

class _ExitConfirmDialog extends StatelessWidget {
  const _ExitConfirmDialog();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Dialog(
      backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(32),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 340),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 顶部应用 Logo
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  image: const DecorationImage(
                    image: AssetImage('assets/brand/app_logo.png'),
                    fit: BoxFit.cover,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              // 确认提示文本
              Text(
                context.l10n.t('confirmExitTitle'),
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: 24),
              // 直接退出
              _DialogActionButton(
                text: context.l10n.t('exitDirectly'),
                isPrimary: true,
                onPressed: () async {
                  Navigator.of(context).pop();
                  await windowManager.setPreventClose(false);
                  await windowManager.destroy();
                  exit(0);
                },
              ),
              const SizedBox(height: 12),
              // 最小化到托盘
              _DialogActionButton(
                text: context.l10n.t('minimizeToTray'),
                onPressed: () async {
                  Navigator.of(context).pop();
                  await windowManager.hide();
                },
              ),
              const SizedBox(height: 12),
              // 取消退出
              _DialogActionButton(
                text: context.l10n.t('cancelExit'),
                onPressed: () {
                  Navigator.of(context).pop();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DialogActionButton extends StatefulWidget {
  const _DialogActionButton({
    required this.text,
    required this.onPressed,
    this.isPrimary = false,
  });

  final String text;
  final VoidCallback onPressed;
  final bool isPrimary;

  @override
  State<_DialogActionButton> createState() => _DialogActionButtonState();
}

class _DialogActionButtonState extends State<_DialogActionButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final primaryBg = const Color(0xFF007BFF);
    final primaryHoverBg = const Color(0xFF0069D9);
    final secondaryBg = isDark ? const Color(0xFF333333) : const Color(0xFFEFEFEF);
    final secondaryHoverBg = isDark ? const Color(0xFF444444) : const Color(0xFFE2E2E2);

    final bg = widget.isPrimary
        ? (_isHovered ? primaryHoverBg : primaryBg)
        : (_isHovered ? secondaryHoverBg : secondaryBg);

    final textColor = widget.isPrimary
        ? Colors.white
        : (isDark ? Colors.white70 : Colors.black87);

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 280,
        height: 48,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(24),
          boxShadow: widget.isPrimary && _isHovered
              ? [
                  BoxShadow(
                    color: primaryBg.withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  )
                ]
              : null,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(24),
            onTap: widget.onPressed,
            child: Center(
              child: Text(
                widget.text,
                style: TextStyle(
                  color: textColor,
                  fontSize: 15,
                  fontWeight: widget.isPrimary ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 设备发现卡片，已重构为响应式表格形式。
