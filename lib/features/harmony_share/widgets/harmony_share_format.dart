import '../../../core/nearby_share/share_transfer_rate.dart';
import '../../../core/nearby_share/share_transfer_record.dart';

export 'harmony_share_error.dart';

/// 未知接收文件名只显示稳定序号，不将占位文案写入文件元数据。
String formatShareRecordName(ShareTransferRecord record, String Function(String) text) {
  if (record.fileName.isNotEmpty) return record.fileName;
  if (record.fileIndex != null) return text('harmonyShareFileIndex').replaceAll('{index}', '${record.fileIndex! + 1}');
  return record.fileCount > 1
      ? text('harmonyShareBatchFiles').replaceAll('{count}', '${record.fileCount}')
      : text('harmonyShareUnknownFile');
}

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

/// 速度与剩余时间只估算当前批次；舍入时间避免展示虚假的秒级精确值。
String formatShareRate(ShareRateEstimate rate, String Function(String) text) {
  final speed = rate.bytesPerSecond < 1
      ? '${rate.bytesPerSecond.toStringAsFixed(2)} B'
      : formatShareBytes(rate.bytesPerSecond.round());
  final seconds = rate.remaining.inSeconds;
  final (key, value) = seconds < 60
      ? ('harmonyShareEtaSeconds', seconds)
      : seconds < 3600
      ? ('harmonyShareEtaMinutes', (seconds / 60).ceil())
      : seconds < 86400
      ? ('harmonyShareEtaHours', (seconds / 3600).ceil())
      : ('harmonyShareEtaDays', (seconds / 86400).ceil());
  return text('harmonyShareRate')
      .replaceAll('{speed}', speed)
      .replaceAll('{time}', text(key).replaceAll('{value}', '$value'));
}
