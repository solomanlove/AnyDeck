# AdbManage

AdbManage 是一个轻量级 Flutter Desktop 工具箱，面向 Android 开发和 QA 调试流程。

首版实现遵循 `FLUTTER_ADB_DESKTOP_TECH_PLAN.md`：

```text
Flutter Desktop UI
  -> Dart Process 调用 adb
  -> Dart Process 启动外部 scrcpy
  -> Riverpod 管理设备、会话和长生命周期进程
```


## 最近更新

在本次更新中，我们对应用程序进行了全面的汉化、界面重构以及多项核心功能的增强：

1. **应用全面汉化**
   - 将全平台（macOS、Windows、Linux、Flutter 应用）显示名称统一重命名为**“安卓手机管理”**。
   - 丰富了 UI 中文本地化字符串，确保界面文案完全汉化且符合中文使用习惯。
2. **隐藏侧边栏与顶部状态显示**
   - 在选中设备后，自动隐藏左侧边栏以释放更多内容空间。
   - 顶部导航栏动态显示当前选中的设备名称。
3. **设备管理 UI 重构**
   - 重新设计了设备管理界面，移除原先无设备选中时的空白占位状态面板。
   - 引入支持排序的设备信息表格，可展示设备标识、自定义名称、连接状态等。
   - 支持编辑修改设备昵称/别名。
   - 支持一键重新连接、断开连接及删除离线设备记录。
4. **设备信息本地持久化缓存**
   - 成功加载的设备硬件及系统属性（品牌、型号、内存、分辨率等）会被自动写入本地持久化缓存。
   - 当设备离线或再次切换加载时，能够实现零延迟即时展示。
5. **拼音支持应用过滤搜索**
   - 应用管理列表的搜索框不仅支持中文和包名搜索，还全面支持**拼音首字母**和**全拼**的过滤匹配（例如输入“wx”或“weixin”即可快速筛选出“微信”）。
6. **详细应用信息弹窗展示**
   - 点击应用列表中任一应用，可打开“应用信息”详细对话框。
   - 支持查看：包名、版本、是否系统应用、最小 SDK、目标 SDK、首次安装时间、最后更新时间、安装包大小。
   - 支持动态加载获取应用大小、数据大小及缓存大小（通过 `dumpsys diskstats` 和 `dumpsys package` 等命令解析）。
   - 支持显示并一键复制**签名 MD5 校验码**。
7. **应用安装包（APK）导出**
   - 列表操作栏新增**“导出安装包”**按钮，可一键通过 `adb pull` 将设备上已安装的 APK 安装包导出并保存到本地电脑。

## 当前范围

| 模块 | 状态 | 说明 |
|---|---:|---|
| 设备列表 | 初版 | 通过 `AdbService` 轮询 `adb devices -l` |
| TCP/IP 连接 | 初版 | 调用 `adb connect <ip>:<port>` |
| scrcpy 启动器 | 初版 | 使用默认 MVP 参数启动外部 `scrcpy` |
| 设备操作 | 初版 | 文本输入、Home/Back/Power、音量、Wi-Fi 开关 |
| 布局辅助 | 初版 | 布局边界、深色/浅色模式 |
| 应用管理 | 初版 | 安装 APK、应用列表、启动、强停、清数据、卸载 |
| 文件管理 | 初版 | 浏览 `/sdcard/`、拖拽上传、下载、删除 |
| Logcat | 初版 | 启停日志流、保留最近 1000 行、关键字筛选 |
| Shell / 性能 | 规划中 | 目录结构已预留，后续可扩展 |

拖拽行为：

| 拖入文件 | 动作 |
|---|---|
| `.apk` | `adb install -r <apk>` |
| 其他文件 | `adb push <file> <current remote path>` |

## 项目结构

```text
lib/
  app/
    router/
    theme/
  core/
    adb/
    apps/
    device_actions/
    files/
    logcat/
    providers/
    scrcpy/
  features/
    dashboard/
      presentation/
```

## 开发命令

```bash
flutter pub get
flutter analyze
flutter test
```

本地手动检查运行命令：

```bash
flutter run -d macos
```

## 本地依赖

| 工具 | 用途 |
|---|---|
| `adb` | 设备发现和 shell 命令 |
| `scrcpy` | 外部投屏能力 |
| Flutter Desktop | macOS、Windows、Linux 桌面目标 |

## 代码约定

| 类型 | 约定 |
|---|---|
| 代码注释 | 使用中文描述意图、边界和非显然逻辑 |
| 文档 | 使用中文编写，必要的 API、CLI、类名和协议名保留英文 |
| UI 文案 | 优先走本地化字符串表，避免在 Widget 中散落硬编码文案 |

ADB 和 scrcpy 路径自定义能力后续放入设置模块。
