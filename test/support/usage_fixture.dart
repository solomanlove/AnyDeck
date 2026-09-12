/// 人工构造的跨自然日日桶，避免把手机上的真实使用数据提交进仓库。
Map<String, dynamic> usageFixture() => {
  'status': 'ok',
  'schemaVersion': 1,
  'installationId': 'test-installation',
  'androidUserId': 0,
  'generatedAtMs': 1789146000000,
  'requestedStartMs': 1789142400000,
  'rangeStartMs': 1789109400000,
  'rangeEndMs': 1789145900000,
  'timeZone': 'Asia/Shanghai',
  'utcOffsetMinutes': 480,
  'screenInteractiveMs': 1800000,
  'screenRangeStartMs': 1789109400000,
  'screenRangeEndMs': 1789145900000,
  'apps': [
    {
      'packageName': 'com.example.a',
      'foregroundMs': 2400000,
      'rangeStartMs': 1789109400000,
      'rangeEndMs': 1789145900000,
    },
    {
      'packageName': 'com.example.b',
      'foregroundMs': 600000,
      'rangeStartMs': 1789109400000,
      'rangeEndMs': 1789145900000,
    },
  ],
};
