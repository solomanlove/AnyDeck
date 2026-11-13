/// 开机自启入口中的系统批准提示；中英文状态与错误保持一致。
const autoStartZh = {
  'autoStartNeedsApproval': '登录项已注册，等待你在系统设置中批准。',
  'autoStartManual': '自启配置已保存，请在系统登录项中确认是否允许运行。',
  'autoStartUnavailable': '此版本无法注册系统登录项。',
  'autoStartReadFailed': '无法读取登录项状态，请刷新重试。',
  'autoStartUpdateFailed': '更新开机自启失败，请重试。',
  'autoStartOpenFailed': '无法打开系统设置，请从 Apple 菜单手动进入。',
  'autoStartOpenSettings': '打开系统设置',
  'autoStartRefresh': '刷新状态',
};

const autoStartEn = {
  'autoStartNeedsApproval':
      'The login item is registered and needs your approval in System Settings.',
  'autoStartManual':
      'Startup is configured. Check Login Items to confirm it is allowed to run.',
  'autoStartUnavailable': 'This version cannot register a login item.',
  'autoStartReadFailed':
      'Could not read the login item status. Refresh to retry.',
  'autoStartUpdateFailed': 'Could not update launch at startup. Try again.',
  'autoStartOpenFailed':
      'Could not open System Settings. Open it manually from the Apple menu.',
  'autoStartOpenSettings': 'Open System Settings',
  'autoStartRefresh': 'Refresh status',
};
