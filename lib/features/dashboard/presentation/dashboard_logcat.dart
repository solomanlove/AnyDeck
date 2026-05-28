part of 'dashboard_screen.dart';

class _LogcatTab extends ConsumerWidget {
  const _LogcatTab({required this.device});

  final AdbDevice device;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(logcatControllerProvider.notifier);
    final state = ref.watch(logcatControllerProvider);
    final lines = controller.visibleLines();

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              FilledButton.icon(
                icon: Icon(state.isRunning ? Icons.stop : Icons.play_arrow),
                label: Text(
                  state.isRunning
                      ? context.l10n.t('stop')
                      : context.l10n.t('start'),
                ),
                onPressed: () {
                  state.isRunning
                      ? controller.stop()
                      : controller.start(device.id);
                },
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.cleaning_services),
                label: Text(context.l10n.t('clear')),
                onPressed: controller.clear,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    labelText: context.l10n.t('filterLog'),
                  ),
                  onChanged: controller.setFilter,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xff101827),
                borderRadius: BorderRadius.circular(8),
              ),
              child: state.error != null
                  ? Text(
                      state.error!,
                      style: const TextStyle(color: Colors.redAccent),
                    )
                  : ListView.builder(
                      itemCount: lines.length,
                      itemBuilder: (context, index) {
                        final line = lines[index];
                        return SelectableText(
                          line,
                          style: TextStyle(
                            color: _logColor(line),
                            fontFamily: 'monospace',
                            fontSize: 12,
                            height: 1.25,
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 用于承载一组相关操作按钮的小型复用卡片。
class _ActionCard extends StatelessWidget {
  const _ActionCard({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: children),
          ],
        ),
      ),
    );
  }
}

/// 操作面板中统一样式的 outlined 图标按钮。
class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      icon: Icon(icon, size: 18),
      label: Text(label),
      onPressed: onPressed,
    );
  }
}

/// 带开关状态的操作按钮，点击在开/关之间切换，图标和颜色随状态变化。
class _ToggleActionButton extends StatefulWidget {
  const _ToggleActionButton({
    required this.iconOn,
    required this.iconOff,
    required this.label,
    required this.onToggle,
  });

  final IconData iconOn;
  final IconData iconOff;
  final String label;
  final ValueChanged<bool> onToggle;

  @override
  State<_ToggleActionButton> createState() => _ToggleActionButtonState();
}

class _ToggleActionButtonState extends State<_ToggleActionButton> {
  bool _isOn = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return _isOn
        ? FilledButton.icon(
            icon: Icon(widget.iconOn, size: 18),
            label: Text(widget.label),
            style: FilledButton.styleFrom(
              backgroundColor: colorScheme.primary,
              foregroundColor: colorScheme.onPrimary,
            ),
            onPressed: () {
              setState(() => _isOn = false);
              widget.onToggle(false);
            },
          )
        : OutlinedButton.icon(
            icon: Icon(widget.iconOff, size: 18),
            label: Text(widget.label),
            onPressed: () {
              setState(() => _isOn = true);
              widget.onToggle(true);
            },
          );
  }
}

/// dashboard 各面板复用的居中空态、加载态和错误态。
