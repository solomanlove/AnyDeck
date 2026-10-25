# Android 与 HarmonyOS 共用遥控器

## 入口与界面

- Android 控制 Tab 继续使用原有“遥控器”操作；HarmonyOS 控制 Tab 的“快捷按键与文本控制”新增相同入口。
- 两个平台共用 `RemoteControllerDialog` 与 `RemoteDirectionPad`。方向盘用四个 90° 扇区绘制上下左右，每个扇区保留圆点，鼠标悬停或按下时整块扇区高亮，中心圆形区域发送 OK。
- 可点击区域按圆心距离及方向角判断，与绘制范围一致；超出外圆的角落不发送按键。同一条设备命令执行期间不重复发送方向按键。
- 颜色取自当前 `ThemeData.colorScheme`，方向 Tooltip 与“最近任务”使用中英文 l10n。

## 按键路由

`RemoteDirectionPad` 输出 Android 方向键码 19/20/21/22/23。弹窗调用 `DeviceActionService.keyEvent`：Android 走 `adb shell input keyevent`；HarmonyOS 经已有映射转换为 2012/2013/2014/2015/2016，再走 HDC `uinput -K`。电源、音量、Home、Back、最近任务沿用同一个 Service 的平台分流，电源成功后同步屏幕状态 Provider。

## 验证边界

- `test/remote_direction_pad_test.dart`：五个点击区域分别发送对应键码。
- `test/device_action_harmony_test.dart`：五个方向键码映射为 HDC 键码。
- 定向 `flutter test --no-pub` 已通过；定向静态检查仅报告 `dashboard_screen.dart` 原有的 `liquid_glass_background.dart` 未使用 import。
- 尚未在真实设备上逐一点击遥控器并确认焦点移动；设备界面状态和前台 App 会影响肉眼结果。
