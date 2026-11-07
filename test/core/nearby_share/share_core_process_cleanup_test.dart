import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:any_deck/core/nearby_share/share_core_sessions.dart';
import 'package:flutter_test/flutter_test.dart';

/// 仅编译无网络操作的受控进程；覆盖真实 PID、comm 路径与信号交互。
void main() {
  late Directory fixtures;
  late File core;

  setUpAll(() async {
    if (!Platform.isMacOS) return;
    fixtures = await Directory.systemTemp.createTemp('anydeck cleanup spaces ');
    fixtures = Directory(await fixtures.resolveSymbolicLinks());
    core = File('${fixtures.path}/anydeck-share-core');
    final source = File('${fixtures.path}/fixture.c');
    await source.writeAsString(_fixtureSource);
    final compiled = await Process.run('/usr/bin/clang', [
      source.path,
      '-o',
      core.path,
    ]).timeout(const Duration(seconds: 30));
    expect(compiled.exitCode, 0, reason: compiled.stderr.toString());
    await core.copy('${fixtures.path}/share-network');
    await Directory('${fixtures.path}/other').create();
    await core.copy('${fixtures.path}/other/anydeck-share-core');
    await core.copy('${fixtures.path}/other/share-network');
    await core.copy('${fixtures.path}/share-dfile');
    await core.copy('${fixtures.path}/share-ble');
  });

  tearDownAll(() async {
    if (Platform.isMacOS) await fixtures.delete(recursive: true);
  });

  test('超时仅让精确 sibling 网络 helper 恢复，BLE/DFile 与外部同名进程强制回收', () async {
    final run = await _FixtureRun.start(fixtures, core);
    try {
      await stopShareCoreProcess(
        run.process,
        coreExecutable: core.path,
        gracefulTimeout: const Duration(milliseconds: 100),
      );
      expect(await run.process.exitCode, -ProcessSignal.sigkill.signalNumber);
      await _eventually(
        () async => File('${run.directory.path}/0.restored').exists(),
      );
      await _eventually(() async => !await run.anyChildrenRunning());
      expect(await File('${run.directory.path}/1.restored').exists(), isFalse);
      expect(await File('${run.directory.path}/2.restored').exists(), isFalse);
      expect(await File('${run.directory.path}/3.restored').exists(), isFalse);
    } finally {
      await run.dispose();
    }
  }, skip: !Platform.isMacOS);

  test('sibling helper 是 symlink 时不授予恢复豁免', () async {
    final helper = File('${fixtures.path}/share-network');
    final moved = await helper.rename('${fixtures.path}/network-fixture');
    final link = await Link(helper.path).create(moved.path);
    _FixtureRun? run;
    try {
      final activeRun = await _FixtureRun.start(fixtures, core);
      run = activeRun;
      await stopShareCoreProcess(
        activeRun.process,
        coreExecutable: core.path,
        gracefulTimeout: const Duration(milliseconds: 100),
      );
      await _eventually(() async => !await activeRun.anyChildrenRunning());
      expect(
        await File('${activeRun.directory.path}/0.restored').exists(),
        isFalse,
      );
    } finally {
      try {
        await run?.dispose();
      } finally {
        await link.delete();
        await moved.rename(helper.path);
      }
    }
  }, skip: !Platform.isMacOS);

  test('未匹配实际 Core 路径时不按 helper 名字豁免子进程', () async {
    final run = await _FixtureRun.start(fixtures, core);
    try {
      await stopShareCoreProcess(
        run.process,
        coreExecutable: '${fixtures.path}/other/anydeck-share-core',
        gracefulTimeout: const Duration(milliseconds: 100),
      );
      await _eventually(() async => !await run.anyChildrenRunning());
      for (var index = 0; index < run.childPids.length; index++) {
        expect(
          await File('${run.directory.path}/$index.restored').exists(),
          isFalse,
        );
      }
    } finally {
      await run.dispose();
    }
  }, skip: !Platform.isMacOS);

  test('worker 提前退出时明确报告退出原因并清理本轮目录与进程', () async {
    final directory = await fixtures.createTemp('failed run ');
    await expectLater(
      _FixtureRun.start(
        fixtures,
        core,
        directory: directory,
        workers: [
          '${fixtures.path}/share-network',
          '${fixtures.path}/missing-worker',
          '${fixtures.path}/share-dfile',
          '${fixtures.path}/share-ble',
        ],
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'startup failure',
          allOf(contains('before readiness'), contains('worker 1 exited')),
        ),
      ),
    );
    expect(await directory.exists(), isFalse);
    final processes = await Process.run('/bin/ps', ['-axo', 'comm=']);
    expect(
      processes.stdout
          .toString()
          .split('\n')
          .where((path) => path.trim().startsWith('${fixtures.path}/')),
      isEmpty,
    );
  }, skip: !Platform.isMacOS);
}

/// 每轮只记录自己启动的 PID；失败时也只清理由夹具派生的进程。
class _FixtureRun {
  _FixtureRun(
    this.process,
    this.directory,
    this.childPids,
    this.output,
    this.errors,
  );
  final Process process;
  final Directory directory;
  final List<int> childPids;
  final StreamSubscription<String> output;
  final StreamSubscription<String> errors;

  static Future<_FixtureRun> start(
    Directory fixtures,
    File core, {
    Directory? directory,
    List<String>? workers,
  }) async {
    final runDirectory = directory ?? await fixtures.createTemp('run ');
    final workerPaths =
        workers ??
        [
          '${fixtures.path}/share-network',
          '${fixtures.path}/other/share-network',
          '${fixtures.path}/share-dfile',
          '${fixtures.path}/share-ble',
        ];
    late final Process process;
    try {
      process = await Process.start(core.path, [
        runDirectory.path,
        ...workerPaths,
      ]);
    } catch (_) {
      await runDirectory.delete(recursive: true);
      rethrow;
    }
    final ready = Completer<List<int>>();
    final ownedPids = <int>[];
    final errorsDone = Completer<void>();
    var errorText = '';
    var startupFinished = false;
    void failed(String reason) {
      if (!ready.isCompleted && !startupFinished) {
        ready.completeError(StateError('$reason: ${errorText.trim()}'));
      }
    }

    Future<void> stopped(String reason) async {
      if (ready.isCompleted || startupFinished) return;
      final exit = await process.exitCode.timeout(
        const Duration(seconds: 2),
        onTimeout: () => -999,
      );
      await errorsDone.future.timeout(
        const Duration(seconds: 2),
        onTimeout: () {},
      );
      failed('$reason before readiness (exit $exit)');
    }

    final errors = process.stderr
        .transform(utf8.decoder)
        .listen(
          (text) {
            errorText = '$errorText$text';
            if (errorText.length > 4096) {
              errorText = errorText.substring(errorText.length - 4096);
            }
          },
          onError: (Object error) {
            errorText = '$errorText\nFixture stderr failed: $error';
            if (!errorsDone.isCompleted) errorsDone.complete();
            failed('Fixture stderr failed');
          },
          onDone: () {
            if (!errorsDone.isCompleted) errorsDone.complete();
          },
        );
    final output = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          (line) {
            try {
              final parts = line.split(' ');
              if (parts.length == 2 && parts.first == 'spawn') {
                ownedPids.add(int.parse(parts[1]));
              } else if (parts.length == 5 && parts.first == 'ready') {
                final pids = parts.skip(1).map(int.parse).toList();
                if (!ready.isCompleted) ready.complete(pids);
              } else {
                failed('Invalid fixture startup message');
              }
            } catch (error) {
              failed('Invalid fixture startup message: $error');
            }
          },
          onError: (Object error) => failed('Fixture stdout failed: $error'),
          onDone: () => unawaited(stopped('Fixture stdout closed')),
        );
    unawaited(process.exitCode.then((_) => stopped('Fixture exited')));
    final run = _FixtureRun(process, runDirectory, ownedPids, output, errors);
    try {
      // C 夹具总启动期限为 20 秒，额外留出重负载下事件调度与退出报告的时间。
      await ready.future.timeout(const Duration(seconds: 25));
      startupFinished = true;
      return run;
    } catch (_) {
      startupFinished = true;
      await run.dispose();
      rethrow;
    }
  }

  Future<bool> anyChildrenRunning() async {
    final result = await Process.run('/bin/ps', [
      '-p',
      childPids.join(','),
      '-o',
      'stat=',
    ]).timeout(const Duration(seconds: 2));
    return result.stdout
        .toString()
        .split('\n')
        .any(
          (state) => state.trim().isNotEmpty && !state.trim().startsWith('Z'),
        );
  }

  Future<void> dispose() async {
    try {
      final owned = childPids.toSet();
      final manifest = File('${directory.path}/owned.pids');
      try {
        if (await manifest.exists()) {
          owned.addAll(
            (await manifest.readAsLines()).map(int.tryParse).whereType<int>(),
          );
        }
      } on FileSystemException {
        /* stdout 中记录的 PID 仍必须清理。 */
      }
      // 补齐 fork 与 spawn 行之间的窗口；仅允许清理当前夹具目录下的 executable。
      try {
        final children = await Process.run('/usr/bin/pgrep', [
          '-P',
          '${process.pid}',
        ]).timeout(const Duration(seconds: 2));
        owned.addAll(
          children.stdout
              .toString()
              .split('\n')
              .map(int.tryParse)
              .whereType<int>(),
        );
      } on TimeoutException {
        /* 继续清理已知 PID，不让补充查询阻断回收。 */
      }
      if (owned.isNotEmpty) {
        final result = await Process.run('/bin/ps', [
          '-ww',
          '-p',
          owned.join(','),
          '-o',
          'pid=,comm=',
        ]).timeout(const Duration(seconds: 2));
        for (final line in result.stdout.toString().split('\n')) {
          final match = RegExp(r'^\s*(\d+)\s+(.+)$').firstMatch(line);
          if (match != null &&
              match[2]!.startsWith('${directory.parent.path}/')) {
            Process.killPid(int.parse(match[1]!), ProcessSignal.sigkill);
          }
        }
      }
    } finally {
      try {
        final exit = await process.exitCode.timeout(
          Duration.zero,
          onTimeout: () => -999,
        );
        if (exit == -999) process.kill(ProcessSignal.sigkill);
        await process.exitCode.timeout(const Duration(seconds: 2));
      } finally {
        await output.cancel();
        await errors.cancel();
        await process.stdin.close();
        if (await directory.exists()) await directory.delete(recursive: true);
      }
    }
  }
}

Future<void> _eventually(Future<bool> Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!await condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Fixture process cleanup timed out');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

// 网络 helper 替身只写恢复标记：既不加载 CoreWLAN，也不执行任何网络命令。
const _fixtureSource = r'''
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/select.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

static volatile sig_atomic_t restore = 0;
static pid_t children[4] = {0};
static void request_restore(int ignored) { restore = 1; }

static double monotonic_seconds(void) {
  struct timespec now;
  clock_gettime(CLOCK_MONOTONIC, &now);
  return now.tv_sec + now.tv_nsec / 1000000000.0;
}

// 启动失败由父进程先回收；Dart 仍保留 manifest/stdout/PPID 三种兜底来源。
static int failed_start(void) {
  for (int index = 0; index < 4; index++) {
    if (children[index] > 0) kill(children[index], SIGKILL);
  }
  for (int index = 0; index < 4; index++) {
    if (children[index] > 0) {
      while (waitpid(children[index], NULL, 0) < 0 && errno == EINTR) {}
    }
  }
  return 5;
}

static void touch(const char *path) {
  FILE *file = fopen(path, "w");
  if (file != NULL) fclose(file);
}

int main(int argc, char **argv) {
  if (argc == 4 && strcmp(argv[1], "worker") == 0) {
    signal(SIGTERM, request_restore);
    touch(argv[3]);
    while (!restore) {
      fd_set reads;
      FD_ZERO(&reads);
      FD_SET(STDIN_FILENO, &reads);
      struct timeval timeout = {0, 20000};
      if (select(1, &reads, NULL, NULL, &timeout) > 0) {
        char value;
        if (read(STDIN_FILENO, &value, 1) == 0) restore = 1;
      }
    }
    usleep(150000);
    touch(argv[2]);
    return 0;
  }
  if (argc != 6) return 2;
  signal(SIGTERM, SIG_IGN);
  char manifest_path[4096];
  snprintf(manifest_path, sizeof(manifest_path), "%s/owned.pids", argv[1]);
  FILE *manifest = fopen(manifest_path, "w");
  if (manifest == NULL) { perror("open owned.pids"); return 3; }
  fcntl(fileno(manifest), F_SETFD, FD_CLOEXEC);
  const double deadline = monotonic_seconds() + 20.0;
  for (int index = 0; index < 4; index++) {
    char marker[4096], ready[4096];
    snprintf(marker, sizeof(marker), "%s/%d.restored", argv[1], index);
    snprintf(ready, sizeof(ready), "%s/%d.ready", argv[1], index);
    int control[2];
    if (pipe(control) != 0) { perror("pipe"); return failed_start(); }
    fcntl(control[1], F_SETFD, FD_CLOEXEC);
    children[index] = fork();
    if (children[index] == 0) {
      dup2(control[0], STDIN_FILENO);
      close(control[0]);
      close(control[1]);
      int silent = open("/dev/null", O_WRONLY);
      dup2(silent, STDOUT_FILENO);
      dup2(silent, STDERR_FILENO);
      close(silent);
      execl(argv[index + 2], argv[index + 2], "worker", marker, ready, NULL);
      _exit(4);
    }
    close(control[0]);
    if (children[index] < 0) { perror("fork"); return failed_start(); }
    fprintf(manifest, "%d\n", children[index]);
    if (fflush(manifest) != 0) { perror("write owned.pids"); return failed_start(); }
    printf("spawn %d\n", children[index]);
    fflush(stdout);
    for (;;) {
      int status = 0;
      pid_t result = waitpid(children[index], &status, WNOHANG);
      if (result == children[index]) {
        children[index] = 0;
        fprintf(stderr, "worker %d exited before ready (status %d)\n", index, status);
        return failed_start();
      }
      if (result < 0 && errno != EINTR) { perror("waitpid"); return failed_start(); }
      if (access(ready, F_OK) == 0) break;
      if (monotonic_seconds() >= deadline) {
        fprintf(stderr, "worker %d readiness timed out after 20 seconds\n", index);
        return failed_start();
      }
      usleep(10000);
    }
  }
  fclose(manifest);
  printf("ready %d %d %d %d\n", children[0], children[1], children[2], children[3]);
  fflush(stdout);
  for (;;) pause();
}
''';
