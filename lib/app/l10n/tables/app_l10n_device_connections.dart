/// 设备连接状态与无线调试功能本地化文案表。新增 key 时必须同时补齐 zh/en。
const deviceConnectionsZh = {
  // 连接图标 Tooltip
  'connectionUsb': 'USB 连接',
  'connectionTcp': 'TCP/IP 连接',
  'connectionWirelessDebug': 'WiFi 无线调试',

  // 无线调试弹窗多系统切换与鸿蒙无线调试
  'pairAndroid': 'Android 设备',
  'pairHarmony': '鸿蒙设备',
  'harmonyWirelessTitle': '鸿蒙设备 HDC 无线调试',
  'harmonyWirelessDesc': '将通过 USB 连接的鸿蒙设备切换为 TCP/IP 监听模式，或直接通过局域网 IP 与端口进行无线调试。',
  'harmonySelectDevice': '选择已接入的鸿蒙设备',
  'harmonyNoUsbDevice': '未检测到通过 USB 连接的鸿蒙设备',
  'harmonyIpPortLabel': '设备局域网 IP:端口',
  'harmonyIpPortPlaceholder': '192.168.1.100:5555',
  'harmonyEnablePort': '开启 TCP 端口 (5555)',
  'harmonyEnablePortSuccess': '已成功开启 5555 调试端口',
  'harmonyConnectWireless': '无线连接',
  'harmonyConnectSuccess': '鸿蒙设备无线连接成功',
  'harmonyConnectFailed': '鸿蒙设备无线连接失败',
  'harmonyDetectIp': '已自动检测到设备局域网 IP: ',
  'harmonyNoIpHint': '未检测到设备 WLAN IP，请确保设备与电脑在同一局域网并手动输入 IP',
  'harmonyGuideTip': '提示：首次开启无线调试需通过 USB 数据线连接电脑并授权，成功开启 5555 端口后即可拔出数据线。',
};

const deviceConnectionsEn = {
  // Connection Badges
  'connectionUsb': 'USB Connection',
  'connectionTcp': 'TCP/IP Connection',
  'connectionWirelessDebug': 'WiFi Wireless Debugging',

  // Wireless Debug Dialog & HarmonyOS Wireless
  'pairAndroid': 'Android Device',
  'pairHarmony': 'HarmonyOS Device',
  'harmonyWirelessTitle': 'HarmonyOS HDC Wireless Debugging',
  'harmonyWirelessDesc': 'Switch a USB-connected HarmonyOS device to TCP/IP mode or connect wirelessly via IP and port.',
  'harmonySelectDevice': 'Select Connected HarmonyOS Device',
  'harmonyNoUsbDevice': 'No USB-connected HarmonyOS device found',
  'harmonyIpPortLabel': 'Device LAN IP:Port',
  'harmonyIpPortPlaceholder': '192.168.1.100:5555',
  'harmonyEnablePort': 'Enable Port (5555)',
  'harmonyEnablePortSuccess': 'Port 5555 successfully opened',
  'harmonyConnectWireless': 'Connect Wireless',
  'harmonyConnectSuccess': 'HarmonyOS device connected wirelessly',
  'harmonyConnectFailed': 'Failed to connect HarmonyOS device',
  'harmonyDetectIp': 'Detected device LAN IP: ',
  'harmonyNoIpHint': 'No WLAN IP detected. Ensure device is on the same Wi-Fi and input IP manually',
  'harmonyGuideTip': 'Tip: Connect via USB first to open port 5555. Once opened, you can unplug the cable.',
};
