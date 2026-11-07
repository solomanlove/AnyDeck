import 'dart:io';

import 'package:any_deck/core/nearby_share/share_core_client.dart';
import 'package:any_deck/core/nearby_share/share_send_selection.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('2 GiB以上稀疏文件可选择并构造发送批次，不读取内容或发起网络传输', () async {
    final root = await Directory.systemTemp.createTemp(
      'anydeck-large-metadata-',
    );
    addTearDown(() => root.delete(recursive: true));
    final file = File('${root.path}/large.bin');
    final handle = await file.open(mode: FileMode.write);
    const size = 2 * 1024 * 1024 * 1024 + 123;
    await handle.truncate(size);
    await handle.close();
    final selection = await ShareSendSelection.inspect([file]);
    expect(selection.bytes, size);
    await selection.files.single.verifyUnchanged();
    final request = ShareBatchRequest([ShareBatchFile(file.path, size)]);
    expect(request.bytes, size);
  });

  test('大文件接收清单、整批与逐文件进度均通过，字节完成不冒充终态', () {
    const size = 5 * 1024 * 1024 * 1024 + 7;
    ShareBatchContract.validate(2, size + 3);
    final progress = ShareCoreProgress.parse({
      'event': 'progress',
      'direction': 'receive',
      'bytes': size - 1,
      'total_bytes': size,
    });
    expect(progress.bytes, size - 1);
    final ledger = ShareFileProgressLedger(
      count: 2,
      bytes: size + 3,
      direction: 'receive',
    );
    ledger.accept({
      'event': 'file_progress',
      'direction': 'receive',
      'index': 0,
      'bytes': size,
      'total_bytes': size,
    });
    expect(ledger.snapshots.single.totalBytes, size);
    final received = ShareBatchReceived(
      count: 1,
      bytes: size,
      directory: '/synthetic',
    );
    received.add({
      'event': 'batch_file_received',
      'index': 0,
      'path': '/synthetic/large.bin',
      'bytes': size,
      'sha256': 'a' * 64,
    });
    expect(
      received.finish({
        'event': 'batch_received',
        'file_count': 1,
        'total_bytes': size,
        'sender_hash_verified': false,
      }).single['bytes'],
      size,
    );
  });

  test('移除产品大小上限后仍拒绝多文件计数溢出与不匹配进度', () {
    final max = ShareCoreContract.maxFileBytes;
    expect(
      () => ShareBatchRequest([
        ShareBatchFile('/a', max),
        const ShareBatchFile('/b', 1),
      ]),
      throwsFormatException,
    );
    final ledger = ShareFileProgressLedger(
      count: 2,
      bytes: max,
      direction: 'receive',
    );
    ledger.accept({
      'event': 'file_progress',
      'direction': 'receive',
      'index': 0,
      'bytes': 0,
      'total_bytes': max - 1,
    });
    expect(
      () => ledger.accept({
        'event': 'file_progress',
        'direction': 'receive',
        'index': 1,
        'bytes': 0,
        'total_bytes': max,
      }),
      throwsFormatException,
    );
    expect(
      () => ShareFileProgressLedger(
        count: 3,
        bytes: max,
        direction: 'send',
        sizes: [max, max, 3],
      ),
      throwsFormatException,
    );
  });
}
