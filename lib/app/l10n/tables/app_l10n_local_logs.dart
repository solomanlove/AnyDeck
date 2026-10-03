/// AnyDeck 自身运行日志与本地诊断导出文案。
const localLogsZh = {
  'localLogsTitle': '本地日志与故障排查',
  'localLogsDescription': '抓取 AnyDeck 运行日志、异常堆栈与命令记录，包含保留的历史会话，无需连接手机。',
  'localLogsPrivacy':
      '常见凭据会自动脱敏；日志仍可能包含设备标识、路径或业务内容，分享前请检查。不包含手机 Logcat 或原生崩溃报告。',
  'localLogsCapture': '抓取本地日志',
  'localLogsCapturing': '正在抓取…',
  'localLogsSaved': '本地日志已保存：{path}',
  'localLogsPartial': '已保存部分日志（部分窗口、文件不可用或达到容量上限）：{path}',
  'localLogsFailed': '抓取本地日志失败：{error}',
  'consoleKeyLogs': '仅关键日志（警告 / 错误）',
  'consoleNoLogs': '暂无匹配日志。可调整筛选，或抓取本地日志查看历史记录。',
};

const localLogsEn = {
  'localLogsTitle': 'Local logs & diagnostics',
  'localLogsDescription':
      'Capture AnyDeck runtime logs, exception stacks and command records, including retained sessions. No phone connection required.',
  'localLogsPrivacy':
      'Common credentials are redacted. Logs may still contain device identifiers, paths or app data; review before sharing. Phone Logcat and native crash reports are excluded.',
  'localLogsCapture': 'Capture local logs',
  'localLogsCapturing': 'Capturing…',
  'localLogsSaved': 'Local logs saved: {path}',
  'localLogsPartial':
      'Partial logs saved (some windows/files unavailable or size limit reached): {path}',
  'localLogsFailed': 'Failed to capture local logs: {error}',
  'consoleKeyLogs': 'Key logs only (warnings / errors)',
  'consoleNoLogs':
      'No matching logs. Adjust the filters or capture local logs to view retained history.',
};
