/// 构建单条 HarmonyOS shell 命令参数，保持整段命令由设备端 shell 解析。
List<String> harmonyShellArguments(String deviceId, String command) => [
  '-t',
  deviceId,
  'shell',
  command,
];
