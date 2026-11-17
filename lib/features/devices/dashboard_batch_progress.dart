part of '../dashboard_screen.dart';

/// 单台设备的批量任务进度，由进度弹窗展示。
class _BatchItemProgress {
  final RegisteredDevice device;
  _BatchItemStatus status;
  String message;

  _BatchItemProgress({required this.device})
    : status = _BatchItemStatus.pending,
      message = '';
}

/// 汇总批量任务的逐台进度，并保留原有取消与结果交互。
class _BatchProgressDialog extends ConsumerStatefulWidget {
  final String title;
  final List<RegisteredDevice> devices;
  final Future<String> Function(RegisteredDevice device) action;

  const _BatchProgressDialog({
    required this.title,
    required this.devices,
    required this.action,
  });

  @override
  ConsumerState<_BatchProgressDialog> createState() =>
      _BatchProgressDialogState();
}

class _BatchProgressDialogState extends ConsumerState<_BatchProgressDialog> {
  late List<_BatchItemProgress> _items;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _items = widget.devices.map((d) => _BatchItemProgress(device: d)).toList();
    _runActions();
  }

  Future<void> _runActions() async {
    // 限制 USB 总线最大并发数为 4，防止瞬时并发重度 I/O 打崩宿主机 USB 控制器
    const maxConcurrency = 4;
    var nextIndex = 0;

    Future<void> worker() async {
      while (true) {
        if (!mounted) return;
        final int index;
        if (nextIndex < _items.length) {
          index = nextIndex++;
        } else {
          break;
        }

        if (!mounted) return;
        setState(() {
          _items[index].status = _BatchItemStatus.running;
          _items[index].message = '正在执行...';
        });
        try {
          final res = await widget.action(_items[index].device);
          if (mounted) {
            setState(() {
              _items[index].status = _BatchItemStatus.success;
              _items[index].message = res;
            });
          }
        } catch (e) {
          if (mounted) {
            setState(() {
              _items[index].status = _BatchItemStatus.failed;
              _items[index].message = e.toString().replaceFirst(
                'Exception: ',
                '',
              );
            });
          }
        }
      }
    }

    final poolSize =
        _items.length < maxConcurrency ? _items.length : maxConcurrency;
    final workers = List.generate(poolSize, (_) => worker());
    await Future.wait(workers);

    if (mounted) {
      setState(() {
        _finished = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 500,
        height: 350,
        child: Column(
          children: [
            Expanded(
              child: ListView.separated(
                itemCount: _items.length,
                separatorBuilder: (context, index) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final item = _items[index];
                  Widget statusIcon = const Icon(
                    CupertinoIcons.clock,
                    color: Colors.grey,
                    size: 18,
                  );
                  if (item.status == _BatchItemStatus.running) {
                    statusIcon = const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    );
                  } else if (item.status == _BatchItemStatus.success) {
                    statusIcon = const Icon(
                      CupertinoIcons.check_mark_circled_solid,
                      color: Colors.green,
                      size: 18,
                    );
                  } else if (item.status == _BatchItemStatus.failed) {
                    statusIcon = const Icon(
                      CupertinoIcons.exclamationmark_circle_fill,
                      color: Colors.red,
                      size: 18,
                    );
                  }

                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        statusIcon,
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.device.displayName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                item.message.isEmpty ? '等待执行...' : item.message,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: item.status == _BatchItemStatus.failed
                                      ? Colors.red
                                      : colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _finished ? () => Navigator.of(context).pop() : null,
          child: Text(_finished ? context.l10n.t('close') : '正在执行...'),
        ),
      ],
    );
  }
}

// ==========================================
// 批量录屏专用弹窗
// ==========================================
