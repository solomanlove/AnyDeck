import 'dart:collection';

/// 同时限制行数、单行长度和字符总量，日志突发时只保留最近尾部。
class BoundedLogBuffer {
  BoundedLogBuffer({
    this.maxLines = 3000,
    this.maxLineLength = 16384,
    this.maxCharacters = 4 * 1024 * 1024,
  });

  final int maxLines;
  final int maxLineLength;
  final int maxCharacters;
  final Queue<String> _lines = Queue();
  int _characters = 0;

  bool get isEmpty => _lines.isEmpty;
  int get length => _lines.length;
  int get characters => _characters;
  Iterable<String> get lines => _lines;

  void add(String line) {
    final limit = maxLineLength < maxCharacters ? maxLineLength : maxCharacters;
    final bounded = line.length > limit ? line.substring(0, limit) : line;
    _lines.addLast(bounded);
    _characters += bounded.length;
    while (_lines.length > maxLines || _characters > maxCharacters) {
      _characters -= _lines.removeFirst().length;
    }
  }

  void clear() {
    _lines.clear();
    _characters = 0;
  }

  void addAll(Iterable<String> lines) {
    for (final line in lines) {
      add(line);
    }
  }
}
