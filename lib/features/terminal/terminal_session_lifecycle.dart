part of 'terminal_tab.dart';

/// 终端 Tab 的可见性决定设备 shell 进程何时暂停或恢复。
void _syncTerminalSession(_TerminalTabState view) {
  final device = view.widget.device;
  if (!view.widget.isVisible) {
    view._sessionNotifier.suspendDevice(device.id);
    return;
  }
  final terminalState = view.ref.read(adbTerminalProvider);
  if (terminalState.getSessions(device.id).isEmpty) {
    unawaited(
      view._sessionNotifier.createSession(
        device.id,
        isHarmony: device.isHarmony,
      ),
    );
  } else {
    unawaited(view._sessionNotifier.resumeDevice(device.id));
  }
  view._inputFocusNode.requestFocus();
}

void _scrollTerminalToBottom(ScrollController controller) {
  if (controller.hasClients) {
    controller.animateTo(
      controller.position.maxScrollExtent,
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
    );
  }
}

void _sendTerminalCommand(
  _TerminalTabState view,
  String sessionId,
  String text,
) {
  view._sessionNotifier.sendCommand(
    view.widget.device.id,
    sessionId,
    text.trim(),
  );
  view._commandController.clear();
  view._inputFocusNode.requestFocus();
}
