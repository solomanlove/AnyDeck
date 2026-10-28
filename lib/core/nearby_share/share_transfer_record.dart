/// 互传记录只保存元数据，不保存文件内容或底层协议资料。
enum ShareTransferDirection { send, receive }

enum ShareTransferStatus {
  queued,
  preparing,
  transferring,
  awaitingAcceptance,
  succeeded,
  failed,
  cancelled,
  rejected,
  timedOut,
  interrupted,
}

class ShareTransferRecord {
  const ShareTransferRecord({
    required this.id,
    required this.direction,
    required this.status,
    required this.deviceName,
    required this.address,
    required this.fileName,
    required this.bytes,
    required this.createdAt,
    this.port,
    this.path,
    this.completedAt,
    this.transferredBytes = 0,
    this.error,
    this.sha256,
    this.retryOf,
  });
  final String id;
  final ShareTransferDirection direction;
  final ShareTransferStatus status;
  final String deviceName;
  final String address;
  final int? port;
  final String fileName;
  final String? path;
  final int bytes;
  final int transferredBytes;
  final DateTime createdAt;
  final DateTime? completedAt;
  final String? error;
  final String? sha256;
  final String? retryOf;
  bool get terminal => switch (status) {
    ShareTransferStatus.queued ||
    ShareTransferStatus.preparing ||
    ShareTransferStatus.transferring ||
    ShareTransferStatus.awaitingAcceptance => false,
    _ => true,
  };
  DateTime get sortTime => completedAt ?? createdAt;
  bool get canRetry =>
      direction == ShareTransferDirection.send &&
      terminal &&
      status != ShareTransferStatus.succeeded &&
      path != null;

  ShareTransferRecord update({
    ShareTransferStatus? status,
    String? fileName,
    String? path,
    int? transferredBytes,
    DateTime? completedAt,
    String? error,
    String? sha256,
  }) => ShareTransferRecord(
    id: id,
    direction: direction,
    status: status ?? this.status,
    deviceName: deviceName,
    address: address,
    port: port,
    fileName: fileName ?? this.fileName,
    path: path ?? this.path,
    bytes: bytes,
    transferredBytes: transferredBytes ?? this.transferredBytes,
    createdAt: createdAt,
    completedAt: completedAt ?? this.completedAt,
    error: error ?? this.error,
    sha256: sha256 ?? this.sha256,
    retryOf: retryOf,
  );

  Map<String, Object?> toMap() => {
    'id': id,
    'direction': direction.name,
    'status': status.name,
    'device_name': deviceName,
    'address': address,
    'port': port,
    'file_name': fileName,
    'path': path,
    'bytes': bytes,
    'transferred_bytes': transferredBytes,
    'created_at': createdAt.millisecondsSinceEpoch,
    'completed_at': completedAt?.millisecondsSinceEpoch,
    'error': error,
    'sha256': sha256,
    'retry_of': retryOf,
  };
  factory ShareTransferRecord.fromMap(Map<String, Object?> value) =>
      ShareTransferRecord(
        id: value['id'] as String,
        direction: ShareTransferDirection.values.byName(
          value['direction'] as String,
        ),
        status: ShareTransferStatus.values.byName(value['status'] as String),
        deviceName: value['device_name'] as String,
        address: value['address'] as String,
        port: value['port'] as int?,
        fileName: value['file_name'] as String,
        path: value['path'] as String?,
        bytes: value['bytes'] as int,
        transferredBytes: value['transferred_bytes'] as int,
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          value['created_at'] as int,
        ),
        completedAt: value['completed_at'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(value['completed_at'] as int),
        error: value['error'] as String?,
        sha256: value['sha256'] as String?,
        retryOf: value['retry_of'] as String?,
      );
}
