import 'package:any_deck/core/nearby_share/share_batch_contract.dart';
import 'package:any_deck/core/nearby_share/share_core_contract.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('批次请求支持跨 1 GiB 总量，但保持单文件和 UTF-8 行上限', () {
    final request = ShareBatchRequest([
      const ShareBatchFile('/synthetic/大文件.bin', 1073741824),
      const ShareBatchFile('/synthetic/line\nname.bin', 65536),
    ]).request(localIp: '127.0.0.1', peerIp: '127.0.0.2', port: 44800);
    expect(request['version'], 3);
    expect((request['files'] as List).length, 2);
    expect(ShareCoreContract.version, 2);
    expect(
      () => ShareBatchRequest([const ShareBatchFile('/a', 1073741825)]),
      throwsFormatException,
    );
    expect(
      () => ShareBatchRequest([
        const ShareBatchFile('/a', 1),
        const ShareBatchFile('/other/A', 1),
      ]),
      throwsFormatException,
    );
    expect(
      () => ShareBatchRequest(
        List.generate(101, (i) => ShareBatchFile('/file-$i', 1)),
      ),
      throwsFormatException,
    );
    final long = ShareBatchRequest(
      List.generate(100, (i) => ShareBatchFile('/${'长' * 300}/file-$i', 1)),
    );
    expect(
      () => long.request(localIp: '127.0.0.1', peerIp: '127.0.0.2', port: 1),
      throwsFormatException,
    );
  });
  Map<String, dynamic> file(int index, String path, int bytes) => {
    'event': 'batch_file_received',
    'index': index,
    'path': path,
    'bytes': bytes,
    'sha256': 'a' * 64,
  };
  Map<String, dynamic> end(int count, int bytes) => {
    'event': 'batch_received',
    'file_count': count,
    'total_bytes': bytes,
    'sender_hash_verified': false,
  };
  test('逐文件结果与最终摘要都完整才返回不可变结果', () {
    final result = ShareBatchReceived(
      count: 2,
      bytes: 1073807360,
      directory: '/synthetic/received',
    );
    result.add(file(0, '/synthetic/received/a.bin', 1073741824));
    expect(() => result.finish(end(2, 1073807360)), throwsFormatException);
    result.add(file(1, '/synthetic/received/b.bin', 65536));
    final files = result.finish(end(2, 1073807360));
    expect(files.length, 2);
    expect(() => files.add({}), throwsUnsupportedError);
    expect(() => files[0]['path'] = 'changed', throwsUnsupportedError);
    expect(
      () => result.add(file(2, '/synthetic/received/c', 1)),
      throwsFormatException,
    );
  });
  test('拒绝重复、乱序、越界路径、伪造 hash 与错误总量', () {
    for (final event in [
      file(1, '/root/a', 1),
      {...file(0, '/root/a', 1), 'index': 0.0},
      file(0, '/other/a', 1),
      file(0, '/root/../a', 1),
      file(0, '/root/a', 4),
      {...file(0, '/root/a', 1), 'sha256': 'bad'},
    ]) {
      expect(
        () => ShareBatchReceived(
          count: 2,
          bytes: 3,
          directory: '/root',
        ).add(event),
        throwsFormatException,
      );
    }
    final result = ShareBatchReceived(count: 2, bytes: 3, directory: '/root');
    result.add(file(0, '/root/a', 1));
    expect(() => result.add(file(1, '/root/a', 2)), throwsFormatException);
    result.add(file(1, '/root/b', 2));
    expect(
      () => result.finish({...end(2, 3), 'sender_hash_verified': true}),
      throwsFormatException,
    );
    expect(() => result.finish(end(2, 4)), throwsFormatException);
    expect(result.finish(end(2, 3)).length, 2);
  });
}
