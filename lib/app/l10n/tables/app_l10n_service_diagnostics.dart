/// 全局服务检查的状态、范围、问题影响和处理建议。
const serviceDiagnosticsZh = {
  'diagnosticsTitle': '服务与诊断',
  'diagnosticsSubtitle': '检查 App 各项服务及其依赖',
  'diagnosticsSelectService': '点击服务名称可单独检查该服务及其依赖',
  'diagnosticsReadOnly': '只读检查 · 真实状态',
  'diagnosticsNotChecked': '尚未诊断',
  'diagnosticsChecking': '诊断中…',
  'diagnosticsNoIssues': '未发现问题',
  'diagnosticsPartial': '已检查 {checked}/{total} 项',
  'diagnosticsIssueCount': '{count} 项需处理',
  'diagnosticsCheckAll': '检查全部',
  'diagnosticsCheckService': '检查「{service}」',
  'diagnosticsScope': '仅读取运行状态及依赖，不自动启停、安装或修复。每项显示最近一次检查结果，设备功能需在连接后单独验证。',
  'diagnosticsCheckedAt': '最近检查时间：',
  'diagnosticsResult': '检查结果：',
  'diagnosticsImpact': '影响范围：',
  'diagnosticsAdvice': '处理建议：',
  'diagnosticsPath': '工具路径：',
  'diagnosticsVersion': '版本：',
  'diagnosticsEndpoint': '监听地址：',
  'diagnosticsReceiverName': '接收名称：',
  'diagnosticsTechnicalError': '技术信息：',
  'diagnosticsSessionCount': '当前会话数：',
  'diagnosticsMessageKey': '会话信息：',
  'diagnosticsToolGuide': '打开安装与配置引导',
  'diagnosticsStatusnotChecked': '未检查',
  'diagnosticsStatuschecking': '检查中',
  'diagnosticsStatusrunning': '运行正常',
  'diagnosticsStatusready': '已就绪',
  'diagnosticsStatusdisabled': '未启用',
  'diagnosticsStatusmissing': '依赖缺失',
  'diagnosticsStatuserror': '运行异常',
  'diagnosticsStatuspermissionRequired': '待授权',
  'diagnosticsStatusunsupported': '不支持',
  'diagnosticsStatusunknown': '待确认',
  'diagnosticsServiceadb': 'ADB · Android 连接',
  'diagnosticsServicehdc': 'HDC · HarmonyOS 连接',
  'diagnosticsServiceios': 'go-ios · iOS 连接',
  'diagnosticsServicemirror': '设备投屏引擎',
  'diagnosticsServiceairplay': 'AirPlay 接收',
  'diagnosticsServicedlna': 'DLNA 接收',
  'diagnosticsServicetransfer': '文件互传',
  'diagnosticsServicemcp': 'AI MCP',
  'diagnosticsServicevirtualCamera': '虚拟摄像头',
  'diagnosticsServicelanShare': '局域网设备共享',
  'diagnosticsServicenotifications': '系统通知与消息转发',
  'diagnosticsServicedeviceSessions': '摄像头、麦克风与辅助会话',
  'diagnosticsImpactadb': 'Android 设备发现、连接和调试。',
  'diagnosticsImpacthdc': 'HarmonyOS 设备发现、连接和调试。',
  'diagnosticsImpactios': 'iOS 设备连接与管理。',
  'diagnosticsImpactmirror': '设备屏幕投屏与基于 Rust 的音视频功能。',
  'diagnosticsImpactairplay': 'iPhone 等设备通过 AirPlay 无线投屏到电脑。',
  'diagnosticsImpactdlna': '视频 App 通过 DLNA 向电脑投放媒体。',
  'diagnosticsImpacttransfer': '局域网文件发现、发送与接收。',
  'diagnosticsImpactmcp': 'AI 客户端通过 MCP 访问 AnyDeck。',
  'diagnosticsImpactvirtualCamera': '会议等应用使用 AnyDeck 虚拟摄像头。',
  'diagnosticsImpactlanShare': '在电脑间共享 Android 设备连接。',
  'diagnosticsImpactnotifications': '设备连接通知、文件来件通知与手机消息转发。',
  'diagnosticsImpactdeviceSessions': '设备摄像头、麦克风、剪贴板与系统音频转发。',
  'diagnosticsNotCheckedReason': '尚未检查此服务。',
  'diagnosticsRunAdvice': '点击服务名称获取当前状态。',
  'diagnosticsToolReady': '工具版本命令执行成功；不代表设备已连接或调试授权完成。',
  'diagnosticsToolBusy': '工具正在检查、下载或解压，暂未产生最终结果。',
  'diagnosticsToolMissing': '工具缺失或无法执行，请查看路径和技术信息。',
  'diagnosticsToolAdvice': '打开安装与配置引导，检查工具路径和执行权限后重新诊断。',
  'diagnosticsReadyAdvice': '无需处理；需要使用时从对应功能入口操作。',
  'diagnosticsRunningReason': '读取到已有服务处于运行状态。',
  'diagnosticsListeningReason': '现有服务正在运行，本机监听连接检查通过。',
  'diagnosticsCheckingReason': '正在读取此服务的状态和依赖。',
  'diagnosticsUnknownAdvice': '稍后重新诊断；若仍无法确认，请在控制台查看相关记录。',
  'diagnosticsReadyReason': '所需组件已就绪，尚未建立功能会话。',
  'diagnosticsDisabledReason': '服务当前未启用，属于正常停用状态。',
  'diagnosticsDisabledAdvice': '无需处理；使用时从对应功能入口启动。',
  'diagnosticsUnsupportedReason': '当前系统不提供此功能。',
  'diagnosticsNotBundled': '当前 AnyDeck 构建未包含此可选组件。',
  'diagnosticsUnsupportedAdvice': '无需处理，此项不计入故障。',
  'diagnosticsComponentMissing': '所需组件缺失或不兼容。',
  'diagnosticsComponentAdvice': '检查 AnyDeck 安装是否完整，更新或重新安装对应组件后重试。',
  'diagnosticsPermissionReason': '系统授权尚未完成或需要重启。',
  'diagnosticsPermissionAdvice': '从对应功能入口完成系统授权，再重新诊断。',
  'diagnosticsFailedReason': '无法确认服务正常，请查看技术信息。',
  'diagnosticsErrorAdvice': '检查端口、权限与依赖；在控制台查看相关错误后重试。',
  'diagnosticsMirrorReady': '投屏组件可加载，内置资源已验证；未创建投屏会话。',
  'diagnosticsMirrorCliReady': '外部 scrcpy 版本检查通过；未创建投屏会话。',
  'diagnosticsMirrorAdvice': '连接设备后从“投屏”验证画面与控制；此检查不启动或打断投屏。',
  'diagnosticsAirplayPublishing': '服务正在监听，Bonjour 名称发布尚未确认。',
  'diagnosticsPortFailed': '服务报告已运行，但本机监听端口无法连接。',
  'diagnosticsPreparingReason': '服务尚在准备，暂未确认就绪，请稍后重新诊断。',
  'diagnosticsNoStatus': '未获得可确认的状态，不能判断为正常。',
  'diagnosticsNativeMissing': '原生服务接口不可用，请检查 App 安装组件。',
  'diagnosticsTimeout': '检查超时，其余服务仍会继续完成检查。',
  'diagnosticsCameraAdvice': '需要使用时从虚拟摄像头入口安装或批准扩展；诊断不会请求权限或开启镜头。',
  'diagnosticsLanRunning': '当前窗口已存在共享监听或接入会话；未创建额外共享连接。',
  'diagnosticsNotificationFailed': '已有消息转发会话报告错误。',
  'diagnosticsNotificationsReady': '电脑通知授权已就绪；手机端通知访问权限需在设备中单独验证。',
  'diagnosticsNotificationsPermission': '系统尚未允许通知，部分提醒无法送达。',
  'diagnosticsNotificationsAdvice': '在系统设置检查 AnyDeck 通知权限；手机消息转发还需设备端授权。',
  'diagnosticsSessionsScope': '仅读取当前窗口已有的采集与转发会话；其他窗口及未启动功能不在本项验证范围。',
  'diagnosticsSessionsAdvice': '在对应设备工作台检查会话与设备隐私权限；未启用的采集不会在诊断中自动启动。',
  'diagnosticsDeveloperDescription': '检查全部服务及连接环境。此功能也可从主窗口右下角打开。',
};

const serviceDiagnosticsEn = {
  'diagnosticsToolBusy':
      'The tool is being checked, downloaded or extracted. No final result is available yet.',
  'diagnosticsReadOnly': 'Read-only · Actual status',
  'diagnosticsListeningReason':
      'The existing service is running and its local listening connection passed.',
  'diagnosticsCheckingReason':
      'Reading this service’s status and dependencies.',
  'diagnosticsUnknownAdvice':
      'Run the check again shortly. Review console records if the status remains unconfirmed.',
  'diagnosticsMirrorCliReady':
      'The external scrcpy version check passed. No mirroring session was created.',
  'diagnosticsNotBundled':
      'This AnyDeck build does not include this optional component.',
  'diagnosticsTitle': 'Services & diagnostics',
  'diagnosticsSubtitle':
      'Check dependencies, services, listening ports and permissions',
  'diagnosticsSelectService':
      'Select a service to check it and its dependencies',
  'diagnosticsNotChecked': 'Not diagnosed yet',
  'diagnosticsChecking': 'Checking…',
  'diagnosticsNoIssues': 'No issues found',
  'diagnosticsPartial': '{checked} of {total} checked',
  'diagnosticsIssueCount': 'Needs attention ({count})',
  'diagnosticsCheckAll': 'Check all',
  'diagnosticsCheckService': 'Check {service}',
  'diagnosticsScope':
      'Checks only read service status and dependencies. Each service shows its latest result. Verify device features separately after connecting.',
  'diagnosticsCheckedAt': 'Last checked:',
  'diagnosticsResult': 'Result:',
  'diagnosticsImpact': 'Affected features:',
  'diagnosticsAdvice': 'Suggested action:',
  'diagnosticsPath': 'Tool path:',
  'diagnosticsVersion': 'Version:',
  'diagnosticsEndpoint': 'Listening address:',
  'diagnosticsReceiverName': 'Receiver name:',
  'diagnosticsTechnicalError': 'Technical details:',
  'diagnosticsSessionCount': 'Current sessions:',
  'diagnosticsMessageKey': 'Session details:',
  'diagnosticsToolGuide': 'Open installation & configuration guide',
  'diagnosticsStatusnotChecked': 'Not checked',
  'diagnosticsStatuschecking': 'Checking',
  'diagnosticsStatusrunning': 'Running',
  'diagnosticsStatusready': 'Ready',
  'diagnosticsStatusdisabled': 'Disabled',
  'diagnosticsStatusmissing': 'Dependency missing',
  'diagnosticsStatuserror': 'Error',
  'diagnosticsStatuspermissionRequired': 'Permission needed',
  'diagnosticsStatusunsupported': 'Unsupported',
  'diagnosticsStatusunknown': 'Unconfirmed',
  'diagnosticsServiceadb': 'ADB · Android connection',
  'diagnosticsServicehdc': 'HDC · HarmonyOS connection',
  'diagnosticsServiceios': 'go-ios · iOS connection',
  'diagnosticsServicemirror': 'Device mirroring engine',
  'diagnosticsServiceairplay': 'AirPlay receiver',
  'diagnosticsServicedlna': 'DLNA receiver',
  'diagnosticsServicetransfer': 'File transfer',
  'diagnosticsServicemcp': 'AI MCP',
  'diagnosticsServicevirtualCamera': 'Virtual camera',
  'diagnosticsServicelanShare': 'LAN device sharing',
  'diagnosticsServicenotifications': 'Notifications & message forwarding',
  'diagnosticsServicedeviceSessions': 'Camera, microphone & auxiliary sessions',
  'diagnosticsImpactadb': 'Android device discovery, connection and debugging.',
  'diagnosticsImpacthdc':
      'HarmonyOS device discovery, connection and debugging.',
  'diagnosticsImpactios': 'iOS device connection and management.',
  'diagnosticsImpactmirror': 'Device mirroring and Rust audio/video features.',
  'diagnosticsImpactairplay':
      'Wireless AirPlay mirroring from iPhone and other devices.',
  'diagnosticsImpactdlna': 'Media playback on this computer from DLNA apps.',
  'diagnosticsImpacttransfer': 'LAN file discovery, sending and receiving.',
  'diagnosticsImpactmcp': 'AI clients connecting to AnyDeck using MCP.',
  'diagnosticsImpactvirtualCamera':
      'AnyDeck virtual camera in meeting and other apps.',
  'diagnosticsImpactlanShare':
      'Sharing Android device connections between computers.',
  'diagnosticsImpactnotifications':
      'Device, incoming-file and forwarded phone notifications.',
  'diagnosticsImpactdeviceSessions':
      'Device camera, microphone, clipboard and system audio forwarding.',
  'diagnosticsNotCheckedReason': 'This service has not been checked yet.',
  'diagnosticsRunAdvice':
      'Select the service name to check its current status.',
  'diagnosticsToolReady':
      'The version command succeeded. Device connection and debugging authorization are not verified.',
  'diagnosticsToolMissing':
      'The tool is missing or cannot execute. Review its path and technical details.',
  'diagnosticsToolAdvice':
      'Open the guide, check the tool path and execution permissions, then run again.',
  'diagnosticsReadyAdvice': 'No action needed. Open the feature when required.',
  'diagnosticsRunningReason': 'The existing service reports a running state.',
  'diagnosticsReadyReason':
      'Required components are ready; no feature session was created.',
  'diagnosticsDisabledReason':
      'The service is currently disabled. This is a normal stopped state.',
  'diagnosticsDisabledAdvice':
      'No action needed. Start it from the feature when required.',
  'diagnosticsUnsupportedReason':
      'This feature is not available on this operating system.',
  'diagnosticsUnsupportedAdvice':
      'No action needed. This does not count as a fault.',
  'diagnosticsComponentMissing':
      'A required component is missing or incompatible.',
  'diagnosticsComponentAdvice':
      'Check the AnyDeck installation, update or reinstall the component, then try again.',
  'diagnosticsPermissionReason':
      'System authorization is incomplete or a restart is required.',
  'diagnosticsPermissionAdvice':
      'Complete authorization from the feature, then run the check again.',
  'diagnosticsFailedReason':
      'The service could not be confirmed healthy. Review the technical details.',
  'diagnosticsErrorAdvice':
      'Check ports, permissions and dependencies. Review the console errors and try again.',
  'diagnosticsMirrorReady':
      'The mirroring components and bundled resources passed. No mirroring session was created.',
  'diagnosticsMirrorAdvice':
      'Connect a device and open Mirror to verify video and controls. This check does not start or interrupt mirroring.',
  'diagnosticsAirplayPublishing':
      'The service is listening, but Bonjour publication is not yet confirmed.',
  'diagnosticsPortFailed':
      'The service reports running, but its local listening port could not be reached.',
  'diagnosticsPreparingReason':
      'The service is still preparing. Run again shortly to confirm readiness.',
  'diagnosticsNoStatus':
      'No confirmed status was returned; health cannot be assumed.',
  'diagnosticsNativeMissing':
      'The native service interface is unavailable. Check the App installation.',
  'diagnosticsTimeout':
      'This check timed out. Other service checks will still complete.',
  'diagnosticsCameraAdvice':
      'Install or approve the extension from Virtual camera when needed. Diagnosis does not request permission or turn on the camera.',
  'diagnosticsLanRunning':
      'Sharing listeners or joined sessions already exist in this window. No extra connection was created.',
  'diagnosticsNotificationFailed':
      'An existing message forwarding session reported an error.',
  'diagnosticsNotificationsReady':
      'Computer notification permission is ready. Phone notification access must be verified separately.',
  'diagnosticsNotificationsPermission':
      'System notification permission is not granted; some alerts cannot be delivered.',
  'diagnosticsNotificationsAdvice':
      'Check AnyDeck notification permission in system settings. Phone forwarding also requires device authorization.',
  'diagnosticsSessionsScope':
      'Reads only sessions already present in this window. Other windows and inactive features are not verified here.',
  'diagnosticsSessionsAdvice':
      'Check sessions and privacy permissions in the device workspace. Inactive capture is never started by diagnosis.',
  'diagnosticsDeveloperDescription':
      'Check all services and connection tools. Also available in the main window’s bottom-right corner.',
};
