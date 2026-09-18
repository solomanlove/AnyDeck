# Dashboard 手机 Root 状态标识

## 展示位置

- Android 主页 Tab 的设备摘要卡在在线状态下方显示“已 Root”“未 Root”或“Root 状态未知”。iOS 与 HarmonyOS NEXT 不显示。
- 控制 Tab 不再显示 Root 切换按钮。主页刷新同时重新检测 Root 状态；离线时显示未知，不复用上次在线结果。
- 标识使用现有中英文 l10n 文案与主题色，属于只读状态，不触发 `adb root` 或 `adb unroot`。

## 检测链路

`deviceRootStatusProvider(deviceId)` 在设备在线时按顺序读取：

1. `adb -s <deviceId> shell id` 返回 `uid=0(root)`：已 Root。
2. 普通 shell 下执行 `command -v su`：确认无 `su` 时显示未 Root。
3. 存在 `su` 时执行 `su -c id`，5 秒内返回 `uid=0(root)`：已 Root；授权被拒、超时或其他异常：状态未知。

现有 `isDeviceRootProvider` 仅判断 ADB shell 当前是否为 root，仍供 Wi-Fi 密码与证书等权限功能使用，不承担手机 Root 标识的语义。

## 验证边界

`test/device_root_status_provider_test.dart` 覆盖 ADB shell 已提权、普通 shell 通过 `su` 提权、无 `su`、授权拒绝四种路径。已执行定向 `flutter analyze` 和该测试；未启动桌面项目，实际设备授权弹窗与 UI 布局需手动验收。
