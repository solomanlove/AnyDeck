import 'dart:ffi';

import 'package:ffi/ffi.dart';

typedef _AccessNative = Int32 Function(Pointer<Utf8> path, Int32 mode);
typedef _AccessDart = int Function(Pointer<Utf8> path, int mode);

final _access = DynamicLibrary.process()
    .lookupFunction<_AccessNative, _AccessDart>('access');

/// 使用 POSIX access(X_OK) 检查当前用户权限，不运行选中的工具。
///
/// 调用方须先确认普通文件且路径不含 NUL；仅在 POSIX 平台调用。
bool canExecutePosixFile(String path) {
  final nativePath = path.toNativeUtf8(allocator: calloc);
  try {
    return _access(nativePath, 1) == 0;
  } finally {
    calloc.free(nativePath);
  }
}
