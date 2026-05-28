import 'dart:io';

/// Android AVD 模拟器的本地配置摘要。
class AndroidEmulator {
  const AndroidEmulator({
    required this.name,
    this.avdDirectory,
    this.resolution,
    this.sdkVersion,
    this.abi,
    this.memory,
    this.storage,
  });

  final String name;
  final Directory? avdDirectory;
  final String? resolution;
  final String? sdkVersion;
  final String? abi;
  final String? memory;
  final String? storage;

  String get displayName => name.replaceAll('_', ' ');

  String get resolutionLabel => _labelOrDash(resolution);

  String get sdkVersionLabel => _labelOrDash(sdkVersion);

  String get abiLabel => _labelOrDash(abi);

  String get memoryLabel => _labelOrDash(memory);

  String get storageLabel => _labelOrDash(storage);

  String get searchableText {
    return [
      name,
      displayName,
      resolution,
      sdkVersion,
      abi,
      memory,
      storage,
    ].whereType<String>().join(' ').toLowerCase();
  }

  static String _labelOrDash(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return '-';
    }
    return trimmed;
  }
}
