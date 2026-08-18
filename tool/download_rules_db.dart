import 'dart:io';

void main() async {
  print('=== AdbManage LibChecker Rules Database Downloader ===');
  print('正在准备下载最新的 rules.db 文件...');

  // 使用 JitPack 自动编译的 main-SNAPSHOT 版本 AAR 包，确保能拿到最新的云规则
  const url = 'https://jitpack.io/com/github/LibChecker/LibChecker-Rules-Bundle/main-SNAPSHOT/LibChecker-Rules-Bundle-main-SNAPSHOT.aar';
  print('JitPack AAR 下载链接: $url');

  final tempDir = Directory.systemTemp.createTempSync('adbmanage_rules_download');
  final aarFile = File('${tempDir.path}/rules-bundle.aar');
  final extractDir = Directory('${tempDir.path}/extracted');
  extractDir.createSync();

  try {
    // 1. 下载 AAR 文件 (使用 curl 支持重定向和重试)
    print('正在从 JitPack 下载 AAR 归档包...');
    final downloadResult = await Process.run('curl', [
      '-L',
      '--retry', '3',
      '--connect-timeout', '30',
      '-o', aarFile.path,
      url,
    ]);

    if (downloadResult.exitCode != 0) {
      throw Exception('下载 AAR 失败: ${downloadResult.stderr}');
    }

    if (!aarFile.existsSync() || aarFile.lengthSync() < 1024) {
      throw Exception('下载的 AAR 文件无效或过小（大小: ${aarFile.lengthSync()} 字节）');
    }

    print('AAR 下载完成（大小: ${(aarFile.lengthSync() / 1024 / 1024).toStringAsFixed(2)} MB），正在解压提取 rules.db...');

    // 2. 解压提取 assets/lcrules/rules.db
    // -j 表示不创建原有目录结构直接输出到目标文件夹
    final unzipResult = await Process.run('unzip', [
      '-o',
      '-j',
      aarFile.path,
      'assets/lcrules/rules.db',
      '-d',
      extractDir.path,
    ]);

    if (unzipResult.exitCode != 0) {
      throw Exception('解压 assets/lcrules/rules.db 失败: ${unzipResult.stderr}');
    }

    final dbFile = File('${extractDir.path}/rules.db');
    if (!dbFile.existsSync()) {
      throw Exception('解压完成，但在 assets/ 目录下未发现 rules.db 文件');
    }

    // 3. 将规则库保存到项目的 assets/rules 目录下
    final targetDir = Directory('assets/rules');
    if (!targetDir.existsSync()) {
      targetDir.createSync(recursive: true);
    }

    final targetFile = File('${targetDir.path}/rules.db');
    if (targetFile.existsSync()) {
      targetFile.deleteSync();
    }

    dbFile.copySync(targetFile.path);
    print('==================================================');
    print('【成功】最新 rules.db 数据库文件已就位！');
    print('保存路径: ${targetFile.absolute.path}');
    print('文件大小: ${(targetFile.lengthSync() / 1024 / 1024).toStringAsFixed(2)} MB');
    print('==================================================');
  } catch (e) {
    print('【错误】下载并解析 rules.db 失败: $e');
    print('请检查网络状况或重试。');
    exit(1);
  } finally {
    // 4. 清理临时目录
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  }
}
