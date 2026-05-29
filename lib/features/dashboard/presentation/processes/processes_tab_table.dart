part of 'processes_tab.dart';

class _ProcessTableWidths {
  final double name;
  final double cpu;
  final double time;
  final double memory;
  final double pid;
  final double user;

  const _ProcessTableWidths({
    required this.name,
    required this.cpu,
    required this.time,
    required this.memory,
    required this.pid,
    required this.user,
  });

  factory _ProcessTableWidths.adaptive({required double viewportWidth}) {
    // Distribute widths based on typical sizes
    const double minTotal = 820.0;
    if (viewportWidth > minTotal) {
      final double extra = viewportWidth - minTotal;
      return _ProcessTableWidths(
        name: 300.0 + extra * 0.7,
        cpu: 110.0,
        time: 120.0,
        memory: 100.0,
        pid: 90.0,
        user: 100.0 + extra * 0.3,
      );
    } else {
      return const _ProcessTableWidths(
        name: 300.0,
        cpu: 110.0,
        time: 120.0,
        memory: 100.0,
        pid: 90.0,
        user: 100.0,
      );
    }
  }

  double get total => name + cpu + time + memory + pid + user;
}

class _ProcessTable extends StatefulWidget {
  final String deviceId;
  final List<AdbProcess> processes;
  final List<AdbPackage> packages;
  final String? selectedPid;
  final _ProcessTableWidths widths;
  final String sortColumn;
  final bool sortAscending;
  final ValueChanged<String> onSort;
  final ValueChanged<AdbProcess> onSelected;

  const _ProcessTable({
    required this.deviceId,
    required this.processes,
    required this.packages,
    required this.selectedPid,
    required this.widths,
    required this.sortColumn,
    required this.sortAscending,
    required this.onSort,
    required this.onSelected,
  });

  @override
  State<_ProcessTable> createState() => _ProcessTableState();
}

class _ProcessTableState extends State<_ProcessTable> {
  final ScrollController _horizontalController = ScrollController();
  final ScrollController _verticalController = ScrollController();

  @override
  void dispose() {
    _horizontalController.dispose();
    _verticalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tableWidth = max(
      widget.widths.total,
      MediaQuery.of(context).size.width,
    );

    return Scrollbar(
      controller: _horizontalController,
      notificationPredicate: (notification) =>
          notification.metrics.axis == Axis.horizontal,
      child: SingleChildScrollView(
        controller: _horizontalController,
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: tableWidth,
          child: Column(
            children: [
              // Header
              _buildTableHeader(context),
              // Body
              Expanded(
                child: Scrollbar(
                  controller: _verticalController,
                  child: ListView.builder(
                    controller: _verticalController,
                    itemCount: widget.processes.length,
                    itemBuilder: (context, index) {
                      final process = widget.processes[index];
                      return _buildTableRow(context, process, index);
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTableHeader(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final headerStyle = textTheme.titleSmall?.copyWith(
      fontWeight: FontWeight.bold,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );

    Widget headerCell(String column, String label, double width) {
      final isSorted = widget.sortColumn == column;
      return InkWell(
        onTap: () => widget.onSort(column),
        child: Container(
          width: width,
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.centerLeft,
          child: Row(
            children: [
              Flexible(
                child: Text(
                  label,
                  style: headerStyle,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (isSorted) ...[
                const SizedBox(width: 4),
                Icon(
                  widget.sortAscending
                      ? Icons.arrow_upward
                      : Icons.arrow_downward,
                  size: 14,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ],
            ],
          ),
        ),
      );
    }

    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.5),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          headerCell('name', context.l10n.t('processName'), widget.widths.name),
          headerCell('cpu', context.l10n.t('cpuPercent'), widget.widths.cpu),
          headerCell('time', context.l10n.t('cpuTime'), widget.widths.time),
          headerCell('memory', context.l10n.t('memory'), widget.widths.memory),
          headerCell('pid', context.l10n.t('pid'), widget.widths.pid),
          headerCell('user', context.l10n.t('user'), widget.widths.user),
        ],
      ),
    );
  }

  Widget _buildTableRow(BuildContext context, AdbProcess process, int index) {
    final isSelected = process.pid == widget.selectedPid;
    final basePackage = process.name.contains(':')
        ? process.name.split(':').first
        : process.name;

    final matchedPackage = widget.packages.firstWhere(
      (pkg) => pkg.name == basePackage,
      orElse: () => AdbPackage(name: '', system: false, enabled: true),
    );

    // Row alternating background
    final Color? rowColor = isSelected
        ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.4)
        : index % 2 == 0
        ? null
        : Theme.of(
            context,
          ).colorScheme.surfaceContainerLowest.withValues(alpha: 0.5);

    return InkWell(
      onTap: () => widget.onSelected(process),
      child: Container(
        height: 56,
        decoration: BoxDecoration(
          color: rowColor,
          border: Border(
            bottom: BorderSide(
              color: Theme.of(context).dividerColor.withValues(alpha: 0.2),
              width: 0.5,
            ),
          ),
        ),
        child: Row(
          children: [
            // Process Name cell
            Container(
              width: widget.widths.name,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      width: 28,
                      height: 28,
                      color: Colors.transparent,
                      child:
                          matchedPackage.name.isNotEmpty &&
                              matchedPackage.iconLocalPath != null &&
                              File(matchedPackage.iconLocalPath!).existsSync()
                          ? Image.file(
                              File(matchedPackage.iconLocalPath!),
                              fit: BoxFit.contain,
                              errorBuilder: (context, error, stackTrace) =>
                                  _buildFallbackIcon(matchedPackage),
                            )
                          : _buildFallbackIcon(matchedPackage),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          matchedPackage.name.isNotEmpty
                              ? (process.name.contains(':')
                                    ? '${matchedPackage.displayName}:${process.name.split(':').sublist(1).join(':')}'
                                    : matchedPackage.displayName)
                              : process.name,
                          style: TextStyle(
                            fontWeight: matchedPackage.name.isNotEmpty
                                ? FontWeight.bold
                                : FontWeight.normal,
                            fontSize: 13,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (matchedPackage.name.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            process.name,
                            style: TextStyle(
                              fontSize: 11,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // CPU cell
            _buildTextCell(process.cpu, widget.widths.cpu),
            // CPU Time cell
            _buildTextCell(process.cpuTime, widget.widths.time),
            // Memory cell
            _buildTextCell(process.memory, widget.widths.memory),
            // PID cell
            _buildTextCell(process.pid, widget.widths.pid),
            // User cell
            _buildTextCell(process.user, widget.widths.user),
          ],
        ),
      ),
    );
  }

  Widget _buildTextCell(String text, double width) {
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 13),
      ),
    );
  }

  Widget _buildFallbackIcon(AdbPackage package) {
    if (package.name.isEmpty) {
      return const Icon(Icons.android, color: Colors.grey, size: 20);
    }
    final icon = package.flutter
        ? Icons.flutter_dash
        : package.system
        ? Icons.settings_applications
        : Icons.android;
    final color = package.system ? Colors.grey[600] : Colors.green[600];
    return Icon(icon, color: color, size: 20);
  }
}
