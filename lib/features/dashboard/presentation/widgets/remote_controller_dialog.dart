part of '../dashboard_screen.dart';

class _RemoteControllerDialog extends ConsumerWidget {
  const _RemoteControllerDialog({required this.device});

  final AdbDevice device;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actions = ref.read(deviceActionServiceProvider);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      backgroundColor: isDark ? const Color(0xff1e293b) : Colors.white,
      child: Container(
        width: 320,
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Title Bar
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  context.l10n.t('remoteController'),
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: isDark ? const Color(0xffeceff1) : const Color(0xFF1E1E2E),
                  ),
                ),
                IconButton(
                  icon: const Icon(CupertinoIcons.xmark, size: 20),
                  onPressed: () => Navigator.of(context).pop(),
                  color: Colors.grey,
                  hoverColor: Colors.grey.withValues(alpha: 0.1),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Outer grey frame resembling a real remote control
            Container(
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF0F172A) : const Color(0xFFECEEF2),
                borderRadius: BorderRadius.circular(20),
              ),
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
              child: Column(
                children: [
                  // Row 1: Power, Vol Down, Vol Up
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildCircularButton(
                        icon: CupertinoIcons.power,
                        tooltip: context.l10n.t('power'),
                        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE0E2E7),
                        iconColor: const Color(
                          0xFFF38BA8,
                        ), // soft premium red for power
                        onPressed: () => _runAdb(
                          context,
                          ref,
                          pressPowerKeyAndResetScreenPower(
                            actions: actions,
                            deviceId: device.id,
                            screenPowerOffNotifier: ref.read(
                              screenPowerOffProvider(device.id).notifier,
                            ),
                          ),
                        ),
                      ),
                      _buildCircularButton(
                        icon: CupertinoIcons.volume_down,
                        tooltip: context.l10n.t('volumeDown'),
                        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE0E2E7),
                        iconColor: isDark ? const Color(0xffeceff1) : const Color(0xFF5F6B6E),
                        onPressed: () => _runAdb(
                          context,
                          ref,
                          actions.volumeDown(device.id),
                        ),
                      ),
                      _buildCircularButton(
                        icon: CupertinoIcons.volume_up,
                        tooltip: context.l10n.t('volumeUp'),
                        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE0E2E7),
                        iconColor: isDark ? const Color(0xffeceff1) : const Color(0xFF5F6B6E),
                        onPressed: () =>
                            _runAdb(context, ref, actions.volumeUp(device.id)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                  // Row 2: D-Pad
                  _buildDPad(context, ref, actions, isDark),
                  const SizedBox(height: 32),
                  // Row 3: Home, Back (Capsule), Recents
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildCircularButton(
                        icon: CupertinoIcons.circle,
                        tooltip: context.l10n.t('home'),
                        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE0E2E7),
                        iconColor: isDark ? const Color(0xffeceff1) : const Color(0xFF5F6B6E),
                        onPressed: () => _runAdb(
                          context,
                          ref,
                          actions.keyEvent(device.id, 3),
                        ),
                      ),
                      _buildCapsuleButton(
                        icon: Icons.arrow_left_rounded,
                        tooltip: context.l10n.t('back'),
                        color: isDark ? const Color(0xFF334155) : const Color(0xFFD3D5DC),
                        iconColor: isDark ? const Color(0xffeceff1) : const Color(0xFF1E1E2E),
                        onPressed: () => _runAdb(
                          context,
                          ref,
                          actions.keyEvent(device.id, 4),
                        ),
                      ),
                      _buildCircularButton(
                        icon: CupertinoIcons.square,
                        tooltip: 'Recents',
                        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE0E2E7),
                        iconColor: isDark ? const Color(0xffeceff1) : const Color(0xFF5F6B6E),
                        onPressed: () => _runAdb(
                          context,
                          ref,
                          actions.keyEvent(device.id, 187),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCircularButton({
    required IconData icon,
    required String tooltip,
    required Color color,
    required Color iconColor,
    required VoidCallback onPressed,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: color,
        shape: const CircleBorder(),
        child: InkWell(
          onTap: onPressed,
          customBorder: const CircleBorder(),
          hoverColor: Colors.black.withValues(alpha: 0.05),
          child: SizedBox(
            width: 52,
            height: 52,
            child: Icon(icon, color: iconColor, size: 24),
          ),
        ),
      ),
    );
  }

  Widget _buildCapsuleButton({
    required IconData icon,
    required String tooltip,
    required Color color,
    required Color iconColor,
    required VoidCallback onPressed,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: color,
        borderRadius: BorderRadius.circular(26),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(26),
          hoverColor: Colors.black.withValues(alpha: 0.05),
          child: SizedBox(
            width: 90,
            height: 52,
            child: Icon(icon, color: iconColor, size: 30),
          ),
        ),
      ),
    );
  }

  Widget _buildDPad(
    BuildContext context,
    WidgetRef ref,
    DeviceActionService actions,
    bool isDark,
  ) {
    return Container(
      width: 190,
      height: 190,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFD4D6DD),
        shape: BoxShape.circle,
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Directional buttons/sectors (Up, Down, Left, Right)
          // Up
          Positioned(
            top: 4,
            left: 55,
            right: 55,
            height: 50,
            child: _buildDPadSector(
              isDark: isDark,
              tooltip: 'Up',
              onPressed: () =>
                  _runAdb(context, ref, actions.keyEvent(device.id, 19)),
            ),
          ),
          // Down
          Positioned(
            bottom: 4,
            left: 55,
            right: 55,
            height: 50,
            child: _buildDPadSector(
              isDark: isDark,
              tooltip: 'Down',
              onPressed: () =>
                  _runAdb(context, ref, actions.keyEvent(device.id, 20)),
            ),
          ),
          // Left
          Positioned(
            left: 4,
            top: 55,
            bottom: 55,
            width: 50,
            child: _buildDPadSector(
              isDark: isDark,
              tooltip: 'Left',
              onPressed: () =>
                  _runAdb(context, ref, actions.keyEvent(device.id, 21)),
            ),
          ),
          // Right
          Positioned(
            right: 4,
            top: 55,
            bottom: 55,
            width: 50,
            child: _buildDPadSector(
              isDark: isDark,
              tooltip: 'Right',
              onPressed: () =>
                  _runAdb(context, ref, actions.keyEvent(device.id, 22)),
            ),
          ),

          // Center OK button
          Material(
            color: isDark ? const Color(0xFF334155) : Colors.white,
            shape: const CircleBorder(),
            elevation: 2,
            child: InkWell(
              onTap: () =>
                  _runAdb(context, ref, actions.keyEvent(device.id, 23)),
              customBorder: const CircleBorder(),
              hoverColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFECEEF2),
              child: SizedBox(
                width: 84,
                height: 84,
                child: Center(
                  child: Text(
                    'OK',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: isDark ? const Color(0xffeceff1) : const Color(0xFF1E1E2E),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDPadSector({
    required bool isDark,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        customBorder: const CircleBorder(),
        hoverColor: Colors.black.withValues(alpha: 0.05),
        child: Center(
          child: Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xffeceff1) : const Color(0xFF1E1E2E),
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _runAdb(
    BuildContext context,
    WidgetRef ref,
    Future<AdbResult> actionFuture,
  ) async {
    try {
      final res = await actionFuture;
      if (!res.isSuccess && context.mounted) {
        _showSnack(context, res.stderr, isError: true);
      }
    } catch (e) {
      if (context.mounted) {
        _showSnack(context, e.toString(), isError: true);
      }
    }
  }
}
