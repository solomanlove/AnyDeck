import 'dart:async';

/// 将 PTY 的 CR、CRLF、CRCRLF 统一为换行，保留跨数据块的回车状态。
/// 不等待完整行，确保没有换行的 shell 提示符也能立即显示。
class TerminalNewlineNormalizer extends StreamTransformerBase<String, String> {
  const TerminalNewlineNormalizer();

  @override
  Stream<String> bind(Stream<String> stream) async* {
    var afterCarriageReturn = false;
    await for (final chunk in stream) {
      final output = StringBuffer();
      for (final codeUnit in chunk.codeUnits) {
        if (codeUnit == 13) {
          if (!afterCarriageReturn) output.write('\n');
          afterCarriageReturn = true;
        } else {
          if (codeUnit != 10 || !afterCarriageReturn) {
            output.writeCharCode(codeUnit);
          }
          afterCarriageReturn = false;
        }
      }
      if (output.isNotEmpty) yield output.toString();
    }
  }
}
