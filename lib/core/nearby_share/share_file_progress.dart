import 'share_batch_contract.dart';
import 'share_core_contract.dart';

/// 某个文件的实际 IO 字节，index 对应确认后的批次顺序；100% 不表示任务成功。
class ShareCoreFileProgress extends ShareCoreProgress {
  const ShareCoreFileProgress({
    required this.index,
    required super.direction,
    required super.bytes,
    required super.totalBytes,
  });
  final int index;

  Map<String, Object> toMap() => {
    'event': 'file_progress',
    'direction': direction,
    'index': index,
    'bytes': bytes,
    'total_bytes': totalBytes,
  };
}

/// 有界逐文件账本；发送严格匹配声明，接收逐项学习大小并核对整批总量。
class ShareFileProgressLedger {
  ShareFileProgressLedger({
    required this.count,
    required this.bytes,
    required this.direction,
    List<int>? sizes,
  }) {
    ShareBatchContract.validate(count, bytes);
    if (direction != 'send' && direction != 'receive') {
      throw const FormatException('Invalid progress direction');
    }
    _sizes = List<int?>.filled(count, null);
    _done = List<int>.filled(count, 0);
    _seen = List<bool>.filled(count, false);
    if (sizes != null) {
      if (sizes.length != count ||
          sizes.fold<int>(0, (sum, value) => sum + value) != bytes ||
          sizes.any(
            (value) => value < 1 || value > ShareCoreContract.maxFileBytes,
          )) {
        throw const FormatException('Invalid file progress sizes');
      }
      _sizes.setAll(0, sizes);
    }
  }
  final int count;
  final int bytes;
  final String direction;
  late final List<int?> _sizes;
  late final List<int> _done;
  late final List<bool> _seen;
  List<ShareCoreFileProgress> get snapshots => List.unmodifiable([
    for (var index = 0; index < count; index++)
      if (_seen[index])
        ShareCoreFileProgress(
          index: index,
          direction: direction,
          bytes: _done[index],
          totalBytes: _sizes[index]!,
        ),
  ]);

  ShareCoreFileProgress accept(Map<String, dynamic> event) {
    final index = event['index'];
    final done = event['bytes'];
    final total = event['total_bytes'];
    if (event['event'] != 'file_progress' ||
        event['direction'] != direction ||
        index is! int ||
        index < 0 ||
        index >= count ||
        done is! int ||
        total is! int ||
        total < 1 ||
        total > ShareCoreContract.maxFileBytes ||
        done < 0 ||
        done > total ||
        done < _done[index] ||
        (_sizes[index] != null && _sizes[index] != total)) {
      throw const FormatException('Invalid file progress');
    }
    if (_sizes[index] == null) {
      final known = _sizes.whereType<int>().fold<int>(
        0,
        (sum, value) => sum + value,
      );
      final unknown = _sizes.where((value) => value == null).length - 1;
      if (known + total + unknown > bytes ||
          (unknown == 0 && known + total != bytes)) {
        throw const FormatException('File progress exceeds batch declaration');
      }
      _sizes[index] = total;
    }
    _done[index] = done;
    _seen[index] = true;
    return ShareCoreFileProgress(
      index: index,
      direction: direction,
      bytes: done,
      totalBytes: total,
    );
  }

  /// 最终结果可补齐缺失遥测，但不能与已观察到的文件大小矛盾。
  void checkResult(int index, int size) {
    if (index < 0 ||
        index >= count ||
        (_sizes[index] != null && _sizes[index] != size)) {
      throw const FormatException('File result differs from progress');
    }
  }
}
