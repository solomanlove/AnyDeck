import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../model/harmony_version_distribution_data.dart';

/// HarmonyOS 工程配置建议与 build-profile.json5 代码块展示卡片。
///
/// 包含 targetSdkVersion、compatibleSdkVersion 与 DevEco Studio 推荐配置，
/// 以及支持一键复制的 build-profile.json5 代码预览。
class HarmonyProfileConfigCard extends StatelessWidget {
  /// 构造函数
  const HarmonyProfileConfigCard({
    super.key,
    required this.item,
    required this.cardBg,
    required this.cardBorder,
    required this.textPrimary,
  });

  /// 当前选中的鸿蒙版本明细
  final HarmonyDistributionItem item;

  /// 卡片背景色
  final Color cardBg;

  /// 卡片边框色
  final Color cardBorder;

  /// 主标题文字色
  final Color textPrimary;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '工程配置建议（可直接复制）',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: textPrimary,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.copy_rounded, size: 14),
                tooltip: '复制 build-profile.json5 配置',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () {
                  Clipboard.setData(
                    ClipboardData(text: item.buildProfileConfig),
                  );
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('已复制 HarmonyOS 工程配置到剪贴板'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          _buildConfigRow('targetSdkVersion', item.target),
          _buildConfigRow('compatibleSdkVersion', item.compatible),
          _buildConfigRow('DevEco Studio', item.ide),
          const SizedBox(height: 8),
          // 代码块
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF1E2024),
              borderRadius: BorderRadius.circular(6),
            ),
            child: SelectableText(
              item.buildProfileConfig,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 10.5,
                color: Color(0xFF81C784),
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 配置键值行
  Widget _buildConfigRow(String key, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              key,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                color: Color(0xFF6E7781),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
