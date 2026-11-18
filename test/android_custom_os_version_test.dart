import 'package:any_deck/core/device_info/android_version_helper.dart';
import 'package:flutter_test/flutter_test.dart';

/// 使用明确的 ROM 属性验证各品牌版本、优先级和未知值回退。
void main() {
  const cases =
      <({String name, Map<String, String> properties, String? expected})>[
        (
          name: 'ColorOS 支持新版 Oplus 属性',
          properties: {'ro.build.version.oplusrom': '15.0'},
          expected: 'ColorOS 15.0',
        ),
        (
          name: 'ColorOS 优先展示 Oplus 完整版本',
          properties: {
            'ro.build.version.oplusrom': '15.0',
            'ro.build.version.oplusrom.display': '15.0.1',
          },
          expected: 'ColorOS 15.0.1',
        ),
        (
          name: 'OnePlus 保留旧版 Oppo ROM 专用属性识别',
          properties: {
            'ro.product.brand': 'OnePlus',
            'ro.build.version.opporom': 'V11.1',
          },
          expected: 'ColorOS V11.1',
        ),
        (
          name: 'OnePlus 保留 ColorOS 专用属性识别',
          properties: {
            'ro.product.brand': 'OnePlus',
            'ro.build.version.coloros': '14.0',
          },
          expected: 'ColorOS 14.0',
        ),
        (
          name: 'OnePlus 无明确系统身份时不将 Oplus 属性当作 ColorOS',
          properties: {
            'ro.product.brand': 'OnePlus',
            'ro.build.version.oplusrom': '13.0',
          },
          expected: null,
        ),
        (
          name: 'OnePlus export 标记将共享 Oplus 版本归为 OxygenOS',
          properties: {
            'ro.oplus.image.my_stock.type': 'export_OnePlus',
            'ro.build.version.oplusrom': '13.0',
          },
          expected: 'OxygenOS 13.0',
        ),
        (
          name: 'OnePlus GDPR 标记将共享 Oplus 版本归为 OxygenOS',
          properties: {
            'ro.oplus.image.my_stock.type': 'GDPR_OnePlus',
            'ro.build.version.oplusrom': '13.0',
          },
          expected: 'OxygenOS 13.0',
        ),
        (
          name: 'Oxygen OS 显式名称归一为 OxygenOS',
          properties: {'ro.rom.version': 'Oxygen OS 11.2.1.1.LE15BA'},
          expected: 'OxygenOS 11.2.1.1.LE15BA',
        ),
        (
          name: 'HydrogenOS 保留显式系统名称',
          properties: {'ro.rom.version': 'HydrogenOS 11.0'},
          expected: 'HydrogenOS 11.0',
        ),
        (
          name: 'H2OS 保留显式系统名称',
          properties: {'ro.rom.version': 'H2OS 10.0'},
          expected: 'H2OS 10.0',
        ),
        (
          name: 'OnePlus 裸固件号不推测 HydrogenOS',
          properties: {
            'ro.product.brand': 'OnePlus',
            'ro.rom.version': '11.2.1.1.LE15BA',
          },
          expected: null,
        ),
        (
          name: 'HyperOS 专用完整版本优先简称',
          properties: {
            'ro.mi.os.version.incremental': 'OS1.0.10.0.TLDCNXM',
            'ro.mi.os.version.name': 'OS1.0',
          },
          expected: 'HyperOS OS1.0.10.0.TLDCNXM',
        ),
        (
          name: 'HyperOS 专用完整版本无效时回退有效简称',
          properties: {
            'ro.mi.os.version.incremental': 'OSUNKNOWN',
            'ro.mi.os.version.name': 'OS2.0',
          },
          expected: 'HyperOS OS2.0',
        ),
        (
          name: '通用 V816 build 版本不能单独判断为 HyperOS',
          properties: {'ro.build.version.incremental': 'V816.0.1.0.TMCCNXM'},
          expected: null,
        ),
        (
          name: 'MIUI 内部 code 不能直接作为营销版本',
          properties: {'ro.miui.ui.version.code': '9'},
          expected: null,
        ),
        (
          name: 'OriginOS 显示版本优先于兼容 Funtouch 属性',
          properties: {
            'ro.vivo.os.build.display.id': 'OriginOS 6',
            'ro.vivo.os.name': 'Funtouch',
            'ro.vivo.os.version': '16.0',
          },
          expected: 'OriginOS 6',
        ),
        (
          name: 'Funtouch 显示版本清理下划线分隔符',
          properties: {'ro.vivo.os.build.display.id': 'Funtouch OS_10'},
          expected: 'Funtouch OS 10',
        ),
        (
          name: 'vivo 显示属性为普通 Build ID 时回退系统名称和版本',
          properties: {
            'ro.vivo.os.build.display.id': 'BP1A.250505.005',
            'ro.vivo.os.name': 'OriginOS',
            'ro.vivo.os.version': '5',
          },
          expected: 'OriginOS 5',
        ),
        (
          name: 'vivo 显示属性为 unknown 时回退系统名称和版本',
          properties: {
            'ro.vivo.os.build.display.id': 'unknown',
            'ro.vivo.os.name': 'OriginOS',
            'ro.vivo.os.version': '5',
          },
          expected: 'OriginOS 5',
        ),
        (
          name: 'MagicOS 清理重复系统名前缀',
          properties: {'ro.honor.build.version.magic': 'MagicOS_9.0'},
          expected: 'MagicOS 9.0',
        ),
        (
          name: '旧荣耀保留 MagicUI 名称',
          properties: {'ro.build.version.magic': 'MagicUI_6.1'},
          expected: 'MagicUI 6.1',
        ),
        (
          name: 'Flyme 支持独立版本属性',
          properties: {'ro.flyme.version.id': 'Flyme 10.5.0.1A'},
          expected: 'Flyme 10.5.0.1A',
        ),
        (
          name: 'Flyme 属性只有普通 build 值时不误认系统',
          properties: {
            'ro.product.brand': 'Meizu',
            'ro.flyme.version.id': 'BP1A.250505.005',
          },
          expected: null,
        ),
        (
          name: 'Flyme 保留 display 版本回退',
          properties: {'ro.build.display.id': 'Flyme 10.5.0.1A'},
          expected: 'Flyme 10.5.0.1A',
        ),
        (
          name: '普通显示值中的 Flyme 字符串不构成系统名前缀',
          properties: {'ro.build.display.id': 'NotFlyme'},
          expected: null,
        ),
        (
          name: '显示值中间嵌入 Flyme 字符串不误认系统',
          properties: {'ro.build.display.id': 'foo_Flyme_123'},
          expected: null,
        ),
        (
          name: 'ZUI 读取专用版本属性',
          properties: {'ro.com.zui.version': '14.0'},
          expected: 'ZUI 14.0',
        ),
        (
          name: 'ZUI 从完整 build 中提取系统版本',
          properties: {
            'ro.com.zui.version': '14.0',
            'ro.build.display.id':
                'L71091_CN_SECURE_USER_Q00041.0_S_ZUI_14.0.697_ST_221216',
          },
          expected: 'ZUI 14.0.697',
        ),
        (
          name: 'ZUXOS 不沿用兼容 ZUI 版本名称',
          properties: {
            'ro.com.zui.version': '17.0',
            'ro.build.display.id':
                'TB321FU_CN_OPEN_USER_Q00011.0_V_ZUXOS_1.1.10.138_ST_250626',
          },
          expected: 'ZUXOS 1.1.10.138',
        ),
        (
          name: 'SmartisanOS 读取专用版本',
          properties: {'ro.smartisan.version': '7.2.0'},
          expected: 'SmartisanOS 7.2.0',
        ),
        (
          name: 'TECNO 从明确的 HiOS 版本属性识别系统',
          properties: {'ro.tranos.version': 'hios12.0.0'},
          expected: 'HiOS 12.0.0',
        ),
        (
          name: 'Infinix 从明确的 XOS 版本属性识别系统',
          properties: {'ro.tranos.version': 'xos14.0.0'},
          expected: 'XOS 14.0.0',
        ),
        (
          name: '传音只有普通版本号时不推测 HiOS 或 XOS',
          properties: {'ro.tranos.version': '14.0.0'},
          expected: null,
        ),
        (
          name: 'SmartisanOS 完整发行版本排除日期和构建后缀',
          properties: {'ro.smartisan.version': '2.1.2-2015120822-user-511'},
          expected: 'SmartisanOS 2.1.2',
        ),
        (
          name: 'SmartisanOS TNT 发行版本排除桌面构建后缀',
          properties: {
            'ro.smartisan.version': '6.6.6.2_TNT-201904101033-user-oce',
          },
          expected: 'SmartisanOS 6.6.6.2',
        ),
        (
          name: 'MyOS 从系统显示版本中排除硬件型号',
          properties: {
            'ro.product.brand': 'ZTE',
            'ro.build.display.id': 'MyOS12.0.14_A2121',
          },
          expected: 'MyOS 12.0.14',
        ),
        (
          name: 'RedMagicOS 从系统显示版本中排除硬件型号',
          properties: {
            'ro.product.brand': 'nubia',
            'ro.build.display.id': 'RedMagicOS10.0.24_NX779J',
          },
          expected: 'RedMagicOS 10.0.24',
        ),
        (
          name: 'NebulaAIOS 显式名称优先于旧 MiFavor 兼容属性',
          properties: {
            'ro.build.display.id': 'NebulaAIOS12.0_A2121',
            'ro.build.MiFavor_version': '4.0',
          },
          expected: 'NebulaAIOS 12.0',
        ),
        (
          name: 'nubiaUI 保留专用名称与版本',
          properties: {
            'ro.build.nubia.rom.name': 'nubiaUI',
            'ro.build.nubia.rom.code': 'V1.6',
          },
          expected: 'nubiaUI V1.6',
        ),
        (
          name: 'JOYUI 优先于底层兼容 MIUI 属性',
          properties: {
            'ro.product.brand': 'blackshark',
            'ro.build.version.incremental': 'V11.0.4.0.JOYUI',
            'ro.miui.ui.version.name': 'V11',
          },
          expected: 'JOYUI 11.0.4.0',
        ),
        (
          name: 'LineageOS 独立版本优先于残留 MIUI 属性',
          properties: {
            'ro.lineage.build.version': '22.2',
            'ro.lineage.version': '22.2-20260920-NIGHTLY-perseus',
            'ro.miui.ui.version.name': 'V14',
          },
          expected: 'LineageOS 22.2',
        ),
        (
          name: 'LineageOS 独立版本优先于残留 One UI 属性',
          properties: {
            'ro.lineage.build.version': '22.2',
            'ro.build.version.oneui': '90000',
          },
          expected: 'LineageOS 22.2',
        ),
        (
          name: 'LineageOS 无独立版本时保留完整发行版本',
          properties: {'ro.lineage.version': '22.2-20260920-NIGHTLY-perseus'},
          expected: 'LineageOS 22.2-20260920-NIGHTLY-perseus',
        ),
        (
          name: 'HarmonyOS 保留专用版本识别',
          properties: {'ro.huawei.build.version.harmony': '4.2.0'},
          expected: 'HarmonyOS 4.2.0',
        ),
        (
          name: 'HarmonyOS 明确系统身份时不将 EMUI 兼容号当作版本',
          properties: {
            'ro.build.ohos.devicetype': 'phone',
            'ro.build.version.emui': 'EmotionUI_14.2.0',
          },
          expected: 'HarmonyOS',
        ),
        (
          name: 'MagicOS 保留普通数字版本',
          properties: {'ro.honor.build.version.magic': '9.0'},
          expected: 'MagicOS 9.0',
        ),
        (
          name: 'MIUI 保留旧版属性',
          properties: {'ro.miui.ui.version.name': 'V14'},
          expected: 'MIUI V14',
        ),
        (
          name: 'OxygenOS 优先于共享 ColorOS 属性',
          properties: {
            'ro.oxygen.version': '14.0',
            'ro.build.version.oplusrom': '14.0',
          },
          expected: 'OxygenOS 14.0',
        ),
        (
          name: 'realme UI 优先于共享 ColorOS 属性',
          properties: {
            'ro.build.version.realmeui': '6.0',
            'ro.build.version.oplusrom': '15.0',
          },
          expected: 'realme UI 6.0',
        ),
        (
          name: 'ColorOS 保留旧版 Oppo 属性',
          properties: {'ro.build.version.opporom': 'V11.1'},
          expected: 'ColorOS V11.1',
        ),
        (
          name: 'HarmonyOS 空主属性回退平台版本',
          properties: {
            'ro.huawei.build.version.harmony': '',
            'hw_sc.build.platform.version': '4.2.0',
          },
          expected: 'HarmonyOS 4.2.0',
        ),
        (
          name: 'OxygenOS unknown 属性回退显示版本',
          properties: {
            'ro.oxygen.version': 'unknown',
            'ro.oxygen.version.display': 'OxygenOS 14.0',
          },
          expected: 'OxygenOS 14.0',
        ),
        (
          name: 'Oplus unknown 显示属性回退系统版本',
          properties: {
            'ro.build.version.oplusrom.display': 'unknown',
            'ro.build.version.oplusrom': '15.0',
          },
          expected: 'ColorOS 15.0',
        ),
        (
          name: 'LineageOS 空独立版本回退完整发行版本',
          properties: {
            'ro.lineage.build.version': '',
            'ro.lineage.version': '22.2-20260920-NIGHTLY-perseus',
          },
          expected: 'LineageOS 22.2-20260920-NIGHTLY-perseus',
        ),
        (
          name: '无有效 ROM 属性时交给 UI 展示原生 Android',
          properties: {
            'ro.smartisan.version': 'unknown',
            'ro.lineage.build.version': '',
            'ro.build.version.oplusrom': '   ',
          },
          expected: null,
        ),
      ];

  group('AndroidVersionHelper 多品牌厂商系统版本', () {
    for (final scenario in cases) {
      test(scenario.name, () {
        expect(
          AndroidVersionHelper.getCustomOsVersion(scenario.properties),
          scenario.expected,
        );
      });
    }

    // 硬件品牌和普通 build ID 不足以确定当前 ROM，避免刷机后误报。
    for (final brand in ['Sony', 'ASUS', 'motorola', 'Nothing', 'samsung']) {
      test('$brand 无显式 ROM 属性时不根据品牌或 Android 版本猜测', () {
        expect(
          AndroidVersionHelper.getCustomOsVersion({
            'ro.product.brand': brand,
            'ro.build.version.release': '16',
            'ro.build.version.sdk': '36',
            'ro.build.display.id': 'BP2A.250605.031',
          }),
          isNull,
        );
      });
    }
  });
}
