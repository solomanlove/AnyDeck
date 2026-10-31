/// 将 Android dumpsys battery 转为带单位与枚举含义的数据，保留旧原始字段。
class McpBatterySnapshot {
  static Map<String, dynamic> parse(String output) {
    final raw = <String, String>{};
    for (final line in output.split('\n')) {
      final colon = line.indexOf(':');
      if (colon > 0) {
        raw[line.substring(0, colon).trim()] = line.substring(colon + 1).trim();
      }
    }
    int? number(String key) => int.tryParse(raw[key] ?? '');
    final level = number('level');
    final scale = number('scale');
    final percent =
        level != null &&
            scale != null &&
            scale > 0 &&
            level >= 0 &&
            level <= scale
        ? level * 100 / scale
        : null;
    final temperature = number('temperature');
    final voltage = number('voltage');
    return {
      for (final key in [
        'level',
        'scale',
        'status',
        'health',
        'temperature',
        'voltage',
      ])
        key: raw[key],
      'normalized': {
        'levelPercent': percent,
        'temperatureCelsius': temperature == null ? null : temperature / 10,
        'voltageVolts': voltage != null && voltage > 0 ? voltage / 1000 : null,
        'status': switch (number('status')) {
          2 => 'charging',
          3 => 'discharging',
          4 => 'notCharging',
          5 => 'full',
          _ => 'unknown',
        },
        'health': switch (number('health')) {
          2 => 'good',
          3 => 'overheat',
          4 => 'dead',
          5 => 'overVoltage',
          6 => 'unspecifiedFailure',
          7 => 'cold',
          _ => 'unknown',
        },
      },
      'rawUnits': {'temperature': '0.1 °C', 'voltage': 'mV'},
      'raw': output,
    };
  }
}
