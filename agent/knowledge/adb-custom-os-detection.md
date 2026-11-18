# Knowledge: adb-custom-os-detection（Android 厂商系统版本识别）

## 目标与数据链路

AnyDeck 概览同时展示 Android release/API 与当前 ROM 的名称、版本。品牌 Logo 根据硬件身份选择，不参与 ROM 判断；刷入 LineageOS 的小米设备仍展示小米品牌，厂商系统显示 LineageOS。

`DeviceInfoService.loadOverview` 复用已有整包 `getprop`，调用 `AndroidVersionHelper.getCustomOsVersion`，将结果写入 `DeviceOverview.customOs` 和原有缓存。没有命中时 helper 返回 `null`、模型存储 `-`；按用户 2026-11-17 的要求，UI 继续使用 `customOsUnknown` 显示“原生 Android / Stock Android”。此文案是展示兜底约定，不参与系统版本推断。

## 品牌巡检与修复（2026-11-17）

| 系统/品牌 | 已确认的遗漏或误标 | 当前规则 |
| --- | --- | --- |
| Huawei | 明确 HarmonyOS 身份但缺少版本时，原逻辑可能回落到 EMUI 兼容号 | 优先专用 HarmonyOS 版本；存在 `ro.build.ohos.devicetype` 时至少显示 HarmonyOS；否则沿用 EMUI |
| Honor | `MagicUI_6.1` 可能显示为 `MagicOS MagicUI_6.1` | 保留明确的 MagicUI/MagicOS 前缀，清理下划线；原数字版本逻辑保留 |
| Xiaomi/Redmi/POCO | 只读 HyperOS 简称属性，遗漏专用完整版本 | 优先以 `OS` 加数字开头的 `ro.mi.os.version.incremental`，再回退 `ro.mi.os.version.name`；MIUI 保留原属性 |
| OPPO | 没有读取新版 Oplus 属性 | 依次读取 `ro.build.version.oplusrom.display`、`ro.build.version.oplusrom`，并保留旧 ColorOS 属性回退 |
| OnePlus | 新机可能没有 `ro.oxygen.version`，旧机也可能只在 `ro.rom.version` 写 Oxygen OS | 明确名称优先；共享 Oplus 版本配合 `export_OnePlus`/`GDPR_OnePlus` 才归为 OxygenOS；不凭品牌猜国内/国际系统，保留旧 `opporom/coloros` 识别 |
| realme | 与 ColorOS 共用 Oplus 属性 | 独立 `ro.build.version.realmeui` 优先；仅有共享属性时不推算 realme UI 营销版本 |
| vivo/iQOO | 旧 `os.name/version` 可能仍为 Funtouch 兼容值 | 优先识别 `ro.vivo.os.build.display.id` 中明确的 OriginOS/Funtouch 名称与版本，再回退旧字段 |
| Meizu | 独立 Flyme 属性遗漏，旧 `contains` 还可能误认 `NotFlyme` | display 与 `ro.flyme.version.id` 都要求明确 Flyme/Flyme OS 名称前缀；普通 Build ID 不拼接 Flyme |
| Lenovo/Motorola | ZUI 与新 ZUXOS 缺失 | 优先 display 内明确的 `_ZUI_版本`/`_ZUXOS_版本`，再回退 `ro.com.zui.version`；不将 ZUXOS 的内部 ZUI 兼容号当作产品版本 |
| ZTE/nubia/RedMagic | MyOS、RedMagicOS、NebulaAIOS、nubiaUI、MiFavor 未覆盖 | 明确 display 名称优先，排除型号后缀；再回退 `ro.build.nubia.rom.name/code` 与 `ro.build.MiFavor_version` |
| Black Shark | JOYUI 可能被 MIUI 兼容属性覆盖 | 仅从增量版本明确的 `.JOYUI` 后缀提取版本，检查顺序先于 MIUI |
| Smartisan | 没有读取专用版本 | 读取 `ro.smartisan.version`，去除日期、user、TNT 等构建后缀 |
| TECNO/Infinix | HiOS/XOS 缺失 | 只识别 `ro.tranos.version` 中明确的 HiOS/XOS 前缀，不按品牌或普通数字版本猜测 |
| LineageOS | 原厂品牌仍在，当前刷机系统未识别 | `ro.lineage.build.version` 优先，回退 `ro.lineage.version`；先于可能残留的厂商属性 |
| Samsung | One UI 曾未覆盖，本次保持已修复行为 | 保留 `ro.build.version.oneui` 的十进制编码解析与非法值保护 |

ASUS/ROG、Nothing/CMF、Motorola MyUI 在本轮尚未找到足够可靠的独立版本属性及原始值依据；仅有品牌、Android/API 或通用 Build ID 时继续走“原生 Android”兜底，不维护猜测机型表。MIUI `ro.miui.ui.version.code` 与营销版本并非固定对应，不用它生成版本。

## 证据与实现边界

- 主流属性、名称格式和兼容关系交叉核对 [Fastfetch 官方识别源码](https://github.com/fastfetch-cli/fastfetch/blob/dev/src/detection/displayserver/displayserver_android.c) 与 [AndroidUtilCode 原始识别代码](https://github.com/Blankj/AndroidUtilCode/blob/master/lib/utilcode/src/main/java/com/blankj/utilcode/util/RomUtils.java)。
- OnePlus 国际版读取 [11R 印度版原始属性](https://github.com/oxygen-updater/build-props/blob/master/op11r/india/CPH2487_11_A.07.prop)、[10 Pro 欧洲版属性](https://github.com/oxygen-updater/build-props/blob/master/op10pro/eea/NE2213_11_C.01.prop) 和 [9 Pro Oxygen OS 名称样例](https://github.com/oxygen-updater/build-props/blob/master/op9pro/eea/11.2.1.1.LE15BA_210307.oem_build.prop)。
- HyperOS 专属属性见 [小米官方文档](https://dev.mi.com/xiaomihyperos/documentation/detail?pId=2161)；OriginOS/Funtouch 冲突见 [iQOO 实机属性查询记录](https://github.com/jackwener/DSH-Android/issues/55)。
- LineageOS 版本含义来自 [官方属性生成代码](https://github.com/LineageOS/android_vendor_lineage/blob/lineage-23.0/config/version.mk)；Smartisan 日期后缀见 [原始属性样例](https://github.com/czy1121/settingscompat/blob/master/roms/smartisan.txt)，nubiaUI 见 [原始 device tree](https://github.com/omnirom/android_device_nubia_nx609j/blob/android-9.0/system.prop)。
- HiOS/XOS 分别核对 [TECNO LG8n 原始属性](https://gitlab.com/rama-firmware-dumps/tecno/lg8n/-/blob/sys_tssi_64_armv82_tecno-user-12-SP1A.210812.016-336942-release-keys/product/etc/build.prop?ref_type=heads) 和 [Infinix X6739 原始属性](https://gitlab.com/rama-firmware-dumps/infinix/Infinix-X6739_dump/-/blob/master/product/etc/build.prop)。
- 修改限于共享解析 helper、兜底 l10n 和测试；没有新增 ADB 请求、后台轮询、依赖、Provider、缓存字段或跨窗口协议，不涉及投屏或设备写操作。UI 保留原有主题和语言切换机制。

## 验证与交接

- `android_custom_os_version_test.dart` 覆盖多品牌真实属性形态、优先级、非法输入和无依据时的回退；原有 `android_version_helper_test.dart` 继续覆盖 One UI 和 API 映射。
- `overview_custom_os_test.dart` 覆盖中英文、Light/Dark、未知系统显示原生 Android，以及 HarmonyOS/iOS 不展示 Android 厂商字段；同时回归概览缓存、查询失败保护、身份和布局。
- 自动验证：8 个相关测试文件共 145 项通过，其中多品牌新增用例 60 项；4 个修改/新增 Dart 文件定向 `flutter analyze --no-pub --no-fatal-infos` 通过，无 error/warning，仅有原 Widget 测试的 3 项 Flutter SDK 弃用 info。全仓检查无 error，仍有未改动逻辑的 5 项 warning 与其他 info；本任务修改未包含它们。`git diff --check` 与新测试文件格式检查通过。
- 只读查询当前连接的 Mi MIX 3：`ro.lineage.build.version=22.2`、Android 15/API 35；使用修复后的 Dart helper 解析实际属性，得到 `LineageOS 22.2`。其他新增品牌依靠原始属性样例与自动回归验证，未声称逐台真机验收。
- 人工回归：更新运行包后打开概览并刷新；检查已识别系统的名称与版本、Android/API 独立展示、未知状态的中英文兜底，切换主题并断线重连检查缓存。按仓库约定未启动桌面 App。
