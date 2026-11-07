/// 面向用户的错误说明；仅解析明确的异常/IPC 边界，不按路径或任意子串猜原因。
/// 原始 error 保留在服务与记录中，技术详情由用户主动打开。
String formatShareError(String error, String Function(String) text) {
  final message = error.startsWith('Bad state: ')
      ? error.substring('Bad state: '.length)
      : error;
  final key = switch (message) {
    'history_buffer_full' => 'harmonyShareHistoryBufferFull',
    'outbox_full' => 'harmonyShareOutboxFull',
    'outbox_cancelling' || 'outbox_disposed' => 'harmonyShareOutboxUnavailable',
    'Settings active' ||
    'Transfer or settings active' ||
    'Transfer active' => 'harmonyShareSettingsBusy',
    'Transfer cancelled' ||
    'Batch transfer cancelled' => 'harmonyShareStatus_cancelled',
    'FormatException: Invalid file selection' ||
    'FormatException: Select 1 to 100 files' ||
    'FormatException: Only nonempty regular files up to 1 GiB' ||
    'FormatException: Only nonempty regular files' ||
    'FormatException: Select one nonempty regular file' ||
    'FormatException: Invalid file size total' ||
    'FormatException: Select one nonempty file up to 1 GiB' =>
      'harmonyShareSelectionLimit',
    'FormatException: Share Core direct mode unavailable' =>
      'harmonyShareCoreUnavailable',
    'FormatException: Invalid local name' => 'harmonyShareLocalNameInvalid',
    'FormatException: Invalid receive directory' =>
      'harmonyShareDirectoryError',
    'FormatException: Incompatible Share Core handshake' ||
    'FormatException: Invalid Share Core capabilities' ||
    'FormatException: Incompatible experimental transfer contract' =>
      'harmonyShareCoreUnavailable',
    _ => null,
  };
  if (key != null) return text(key);
  if (_timeout.hasMatch(message)) return text('harmonyShareOperationTimedOut');
  final fileMessage = _fileError.firstMatch(message)?.group(1);
  final fileKey = switch (fileMessage) {
    'Share Core is not bundled' => 'harmonyShareCoreUnavailable',
    'No active IPv4 network with netmask' => 'harmonyShareNetworkUnavailable',
    'Receive directory unavailable' ||
    'Downloads unavailable' => 'harmonyShareDirectoryError',
    'Queued file changed or unavailable' => 'harmonyShareSourceChanged',
    _ => null,
  };
  if (fileKey != null) return text(fileKey);
  final core = _coreError.firstMatch(message);
  final reason = core?.group(2);
  final coreKey = switch (reason) {
    'discovery_port_in_use' when core?.group(1) != 'send_failed' =>
      'harmonyShareDiscoveryPortInUse',
    'receive_port_in_use' when core?.group(1) == 'receive_failed' =>
      'harmonyShareReceivePortInUse',
    'discovery_failed' || 'discovery_start_timeout' || 'core_stopped'
        when core?.group(1) != 'send_failed' => 'harmonyShareDiscoveryFailed',
    'discovery_permission_denied' || 'discovery_advertising_failed'
        when core?.group(1) != 'send_failed' => 'harmonyShareDiscoveryPermission',
    'phone_rejected' when core?.group(1) == 'send_failed' =>
      'harmonySharePeerRejected',
    'decision_timeout' ||
    'deadline' ||
    'dfile_timeout' => 'harmonyShareOperationTimedOut',
    'tcp_failed' => 'harmonySharePeerUnavailable',
    'direct_mode_disabled' => 'harmonyShareDirectModeDisabled',
    'direct_network_permission_required' => 'harmonyShareDirectPermission',
    'direct_network_restore_unavailable' => 'harmonyShareDirectRestoreUnavailable',
    'direct_network_restore_failed' || 'direct_network_restore_pending' =>
      'harmonyShareDirectRestoreFailed',
    'direct_network_busy' => 'harmonyShareDirectNetworkBusy',
    'direct_ble_failed' || 'direct_ble_required' ||
    'direct_auth_channel_unavailable' => 'harmonyShareDirectBleFailed',
    'direct_network_wifi_unavailable' || 'direct_network_not_found' ||
    'direct_network_join_failed' || 'direct_network_join_timeout' ||
    'direct_network_address_unavailable' || 'direct_network_changed' =>
      'harmonyShareDirectJoinFailed',
    'direct_network_invalid_request' || 'direct_network_helper_failed' ||
    'direct_network_lease_expired' => 'harmonyShareDirectProtocolFailed',
    'direct_network_cancelled' => 'harmonyShareStatus_cancelled',
    'unsupported_network_mode' when core?.group(1) == 'receive_failed' =>
      'harmonyShareDirectModeUnsupported',
    'insufficient_space' when core?.group(1) == 'receive_failed' =>
      'harmonyShareInsufficientSpace',
    'invalid_files' when core?.group(1) == 'send_failed' =>
      'harmonyShareFileUnavailable',
    'invalid_batch' || 'size_mismatch' || 'unsafe_file'
        when core?.group(1) == 'receive_failed' =>
      'harmonyShareReceiveValidationFailed',
    _ => 'harmonyShareOperationFailed',
  };
  return text(coreKey);
}

final _timeout = RegExp(r'^TimeoutException(?: after [0-9:.]+)?: ');
final _fileError = RegExp(
  r"^FileSystemException: ([^,\n]+)(?:, path = '[^\n]*')?$",
);
// 发送包含 phase，接收记录仅包含 reason；均只接受完整、单行的错误信封。
final _coreError = RegExp(
  r'^(?:Share Core )?(send_failed|receive_failed|discovery_failed): (?:[a-z_]+ )?([a-z_]+)$',
);
