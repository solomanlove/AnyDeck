part of '../dashboard_screen.dart';

/// 原生库名称与常用 SDK 说明的内置匹配规则。
const _commonNativeLibraryRules = [
  _LibRule('flutter', 'Flutter Engine', 'Google 开发的跨平台 UI 框架底层 C++ 引擎库'),
  _LibRule('reactnative', 'React Native', 'Meta 开发的跨平台开发框架核心 C++ 运行库'),
  _LibRule('unity', 'Unity 3D', 'Unity Technologies 开发的 3D 游戏引擎底层核心库'),
  _LibRule('mono', 'Xamarin Mono', 'Microsoft 开发的跨平台 .NET 运行时引擎'),
  _LibRule('sgmain', '阿里聚安全 (Security Guard)', '阿里巴巴提供的移动应用安全防护与加密 SDK'),
  _LibRule(
    'sgsecuritybody',
    '阿里聚安全 (Security Guard)',
    '阿里巴巴提供的移动应用设备指纹与人机识别 SDK',
  ),
  _LibRule('bugly', '腾讯 Bugly', '腾讯提供的应用崩溃日志上报、异常监控与运营统计 SDK'),
  _LibRule('turing', '腾讯御安全 (Turing Shield)', '腾讯提供的应用安全加固、防逆向与防篡改 SDK'),
  _LibRule('amap', '高德地图 SDK', '高德提供的地图渲染、路线规划与导航核心引擎库'),
  _LibRule('co-amap', '高德地图 SDK', '高德提供的地图定位与混合定位核心库'),
  _LibRule('lbs', '百度地图 SDK', '百度提供的地图渲染、导航与定位服务核心库'),
  _LibRule('baidumapsdk', '百度地图 SDK', '百度提供的地图引擎核心 C++ 运行库'),
  _LibRule(
    'c++_shared',
    'Android NDK C++ Runtime',
    'Google 官方提供的 NDK 共享 C++ 标准库运行时 (libc++)',
  ),
  _LibRule('sqlite', 'SQLite Database', '轻量级嵌入式关系型数据库核心引擎库'),
  _LibRule(
    'realm-jni',
    'Realm Database',
    'MongoDB 提供的移动端跨平台 NoSQL 数据库核心 C++ 引擎库',
  ),
  _LibRule('ffmpeg', 'FFmpeg', '开源开源跨平台多媒体音视频解码、格式转换与处理库'),
  _LibRule('weibosdkcore', '新浪微博 SDK', '新浪微博官方提供的社交分享、登录与开放平台核心库'),
  _LibRule('jpush', '极光推送 (JPush)', '极光提供的移动端消息推送与实时通知交互 SDK'),
  _LibRule('getui', '个推 (GeTui)', '个推官方提供的消息推送、用户画像与数据分析 SDK'),
  _LibRule('tencentloc', '腾讯定位 SDK', '腾讯官方提供的混合定位与地理围栏服务 C++ 库'),
  _LibRule('msc', '科大讯飞语音 SDK', '科大讯飞官方提供的语音识别、语音合成与声纹唤醒核心库'),
  _LibRule(
    'v8',
    'V8 JavaScript Engine',
    'Google 开发的高性能开源 JavaScript 与 WebAssembly 引擎库',
  ),
  _LibRule(
    'xposed',
    'Xposed Framework',
    '基于劫持 Android 系统 Zygote 进程的 Hook 框架核心库',
  ),
  _LibRule('yuv', 'libyuv', 'Google 开源的 YUV 视频格式缩放、旋转与颜色转换核心库'),
  _LibRule('webrtc', 'WebRTC', '开源实时音视频通信 (RTC) 核心协议与渲染引擎库'),
  _LibRule('unwind', 'libunwind', '高效用于获取程序调用栈与进行 Crash 回溯的开源库'),
  _LibRule('crypto', 'OpenSSL (libcrypto)', '开源密码学算法与安全加密传输协议核心库'),
  _LibRule('ssl', 'OpenSSL (libssl)', '开源网络安全传输层协议 (SSL/TLS) 握手与通信库'),
  _LibRule('opencv', 'OpenCV', '开源跨平台计算机视觉与机器学习算法核心库'),
  _LibRule('pdfium', 'PDFium', 'Google 开源的 PDF 文档渲染、阅读与解析引擎库'),
  _LibRule('gifimage', 'GIF Image Decoder', 'Facebook 提供的用于高效解码与渲染 GIF 动图的核心库'),
  _LibRule('mp3lame', 'LAME MP3 Encoder', '高保真 MP3 音频格式压缩与编码开源库'),
  _LibRule('vlc', 'VLC Media Player', 'VideoLAN 开发的万能媒体播放器底层解码与渲染核心库'),
];

class _LibRule {
  const _LibRule(this.keyword, this.name, this.desc);

  final String keyword;
  final String name;
  final String desc;
}
