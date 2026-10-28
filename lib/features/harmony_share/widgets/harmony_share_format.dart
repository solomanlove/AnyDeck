/// 二进制字节单位供确认、队列和传输面板共用，不涉及文件内容。
String formatShareBytes(int bytes) {
  const units = ['B', 'KiB', 'MiB', 'GiB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  return '${unit == 0 ? bytes : value.toStringAsFixed(1)} ${units[unit]}';
}

/// 已知业务错误映射双语提示，其他原生诊断保持原文便于排查。
String formatShareError(String error, String Function(String) text) =>
    error == 'history_buffer_full' ? text('harmonyShareHistoryBufferFull') : error;
