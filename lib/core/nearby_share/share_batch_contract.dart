import 'dart:convert';
import 'dart:io';

import 'share_core_contract.dart';
import 'share_local_name.dart';

/// IPC 3 批次契约；实际批次能力由已校验的原生制品和服务接线共同提供。
abstract final class ShareBatchContract {
  static const version = 3;
  static const maxFiles = 100;
  static const maxBytes = maxFiles * ShareCoreContract.maxFileBytes;

  static void validate(int count, int bytes) {
    if (count < 1 ||
        count > maxFiles ||
        bytes < count ||
        bytes > count * ShareCoreContract.maxFileBytes) {
      throw const FormatException('Invalid batch limits');
    }
  }
}

/// 文件声明中的大小来自用户确认时的快照，Core 在网络发送前再次核对。
class ShareBatchFile {
  const ShareBatchFile(this.path, this.bytes);
  final String path;
  final int bytes;

  void validate() {
    if (!path.startsWith('/') ||
        path.contains('\u0000') ||
        utf8.encode(path).length > 4096 ||
        path.split('/').any((part) => part == '..') ||
        path.endsWith('/') ||
        bytes < 1 ||
        bytes > ShareCoreContract.maxFileBytes) {
      throw const FormatException('Invalid batch file');
    }
  }

  Map<String, Object> toMap() => {'path': path, 'bytes': bytes};
}

/// 一次原生批次请求；有界 JSONL，不允许目录扁平化后名称冲突。
class ShareBatchRequest {
  ShareBatchRequest(List<ShareBatchFile> files, {
    this.localName = ShareLocalName.defaultName,
  })
    : files = List.unmodifiable(files) {
    ShareLocalName.validate(localName);
    ShareBatchContract.validate(files.length, bytes);
    final names = <String>{};
    for (final file in files) {
      file.validate();
      if (!names.add(file.path.split('/').last.toLowerCase())) {
        throw const FormatException('Conflicting batch file names');
      }
    }
  }
  final List<ShareBatchFile> files;
  final String localName;
  int get bytes => files.fold(0, (sum, file) => sum + file.bytes);

  Map<String, Object> request({
    required String localIp,
    required String peerIp,
    required int port,
  }) {
    if (InternetAddress.tryParse(localIp)?.type != InternetAddressType.IPv4 ||
        InternetAddress.tryParse(peerIp)?.type != InternetAddressType.IPv4 ||
        port < 1 ||
        port > 65535) {
      throw const FormatException('Invalid batch peer');
    }
    final value = <String, Object>{
      'version': ShareBatchContract.version,
      'command': 'send_batch_experimental',
      'local_name': localName,
      'local_ip': localIp,
      'peer_ip': peerIp,
      'port': port,
      'duration_seconds': ShareCoreContract.transferTimeout.inSeconds,
      'files': files.map((file) => file.toMap()).toList(),
    };
    if (utf8.encode(jsonEncode(value)).length > 65536) {
      throw const FormatException('Batch request too large');
    }
    return value;
  }
}

/// 只在最终摘要与所有逐文件结果一致时提交成功，避免 stdout 中断时生成假整批结果。
class ShareBatchReceived {
  ShareBatchReceived({
    required this.count,
    required this.bytes,
    required this.directory,
  }) {
    ShareBatchContract.validate(count, bytes);
    if (!directory.startsWith('/') || directory.split('/').contains('..')) {
      throw const FormatException('Invalid batch destination');
    }
  }
  final int count;
  final int bytes;
  final String directory;
  final List<Map<String, Object>> _files = [];
  final Set<String> _paths = {};
  bool _complete = false;

  void add(Map<String, dynamic> event) {
    if (_complete ||
        event['event'] != 'batch_file_received' ||
        event['index'] is! int ||
        event['index'] != _files.length ||
        _files.length >= count) {
      throw const FormatException('Invalid batch result order');
    }
    final path = event['path'];
    final size = event['bytes'];
    final hash = event['sha256'];
    if (path is! String ||
        size is! int ||
        hash is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(hash)) {
      throw const FormatException('Invalid batch result');
    }
    ShareBatchFile(path, size).validate();
    if (File(path).parent.path != Directory(directory).path ||
        _paths.contains(path.toLowerCase()) ||
        _files.fold<int>(0, (sum, item) => sum + (item['bytes'] as int)) +
                size >
            bytes) {
      throw const FormatException('Batch result outside destination or total');
    }
    _paths.add(path.toLowerCase());
    _files.add({'path': path, 'bytes': size, 'sha256': hash});
  }

  List<Map<String, Object>> finish(Map<String, dynamic> event) {
    if (_complete ||
        event['event'] != 'batch_received' ||
        event['file_count'] is! int ||
        event['total_bytes'] is! int ||
        event['file_count'] != count ||
        event['total_bytes'] != bytes ||
        event['sender_hash_verified'] != false ||
        _files.length != count ||
        _files.fold<int>(0, (sum, file) => sum + (file['bytes'] as int)) !=
            bytes) {
      throw const FormatException('Incomplete batch result');
    }
    _complete = true;
    return List.unmodifiable(
      _files.map((file) => Map<String, Object>.unmodifiable(file)),
    );
  }
}
