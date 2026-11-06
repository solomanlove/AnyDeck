# AnyDeck 设置页说明书入口移除

## 需求与实现

- 设置页“关于与说明”卡片不再显示“软件说明书”入口，也不再提供对应弹框。
- 删除专用正文 Widget、弹框类及中英文专用文案；保留设置页版本、开发者选项和意见反馈入口。
- 该入口只涉及本地 UI，无 Provider、SharedPreferences、MethodChannel 或设备命令变更。

## 回归范围

1. 打开设置页，确认“关于与说明”卡片中没有“软件说明书”，版本、开发者选项和意见反馈仍可见。
2. 在中文和英文、Light 和 Dark 主题下检查设置页，确认无说明书弹框入口。
3. 运行 `flutter test --no-pub test/settings_review_test.dart` 和相关静态检查，确认画质预设与设置文案回归通过。
