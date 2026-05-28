import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 常用收藏命令模型。
class FavoriteCommand {
  final String id;
  final String title;
  final String command;
  final bool isCustom;
  final String? titleKey;

  const FavoriteCommand({
    required this.id,
    required this.title,
    required this.command,
    this.isCustom = false,
    this.titleKey,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'command': command,
    'isCustom': isCustom,
    if (titleKey != null) 'titleKey': titleKey,
  };

  factory FavoriteCommand.fromJson(Map<String, dynamic> json) =>
      FavoriteCommand(
        id: json['id'] as String,
        title: json['title'] as String,
        command: json['command'] as String,
        isCustom: json['isCustom'] as bool? ?? false,
        titleKey: json['titleKey'] as String?,
      );
}

/// 收藏命令管理器 Notifier。
class FavoriteCommandsNotifier extends Notifier<List<FavoriteCommand>> {
  static const _prefsKey = 'terminal.favorites';
  static const _deletedDefaultsKey = 'terminal.favorites.deleted_defaults';

  final List<FavoriteCommand> _defaultCommands = [
    const FavoriteCommand(
      id: 'default_packages',
      title: '',
      titleKey: 'favoritePackages',
      command: 'pm list packages',
    ),
    const FavoriteCommand(
      id: 'default_focus',
      title: '',
      titleKey: 'favoriteFocusActivity',
      command: 'dumpsys window | grep mCurrentFocus',
    ),
    const FavoriteCommand(
      id: 'default_screenshot',
      title: '',
      titleKey: 'favoriteScreenshot',
      command: 'screencap -p /sdcard/screenshot.png',
    ),
    const FavoriteCommand(
      id: 'default_version',
      title: '',
      titleKey: 'favoriteAndroidVersion',
      command: 'getprop ro.build.version.release',
    ),
    const FavoriteCommand(
      id: 'default_logcat_dump',
      title: '',
      titleKey: 'favoriteLogcatDump',
      command: 'logcat -d',
    ),
    const FavoriteCommand(
      id: 'default_ip',
      title: '',
      titleKey: 'favoriteIpInfo',
      command: 'ip addr show wlan0',
    ),
  ];

  @override
  List<FavoriteCommand> build() {
    _loadFavorites();
    return _defaultCommands;
  }

  Future<void> _loadFavorites() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final customJson = prefs.getStringList(_prefsKey);
      final deletedDefaults = prefs.getStringList(_deletedDefaultsKey) ?? [];

      final activeDefaults = _defaultCommands
          .where((cmd) => !deletedDefaults.contains(cmd.id))
          .toList();

      if (customJson == null) {
        state = activeDefaults;
        return;
      }

      final customList = customJson
          .map((item) {
            try {
              return FavoriteCommand.fromJson(
                jsonDecode(item) as Map<String, dynamic>,
              );
            } catch (_) {
              return null;
            }
          })
          .whereType<FavoriteCommand>()
          .toList();

      state = [...activeDefaults, ...customList];
    } catch (_) {}
  }

  Future<void> addFavorite(String title, String command) async {
    final newCmd = FavoriteCommand(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: title.trim(),
      command: command.trim(),
      isCustom: true,
    );

    state = [...state, newCmd];
    await _saveCustomFavorites();
  }

  Future<void> deleteFavorite(String id) async {
    final cmdToDelete = state.firstWhere(
      (cmd) => cmd.id == id,
      orElse: () => const FavoriteCommand(id: '', title: '', command: ''),
    );
    if (cmdToDelete.id.isEmpty) return;

    state = state.where((cmd) => cmd.id != id).toList();

    if (!cmdToDelete.isCustom) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final deletedDefaults = prefs.getStringList(_deletedDefaultsKey) ?? [];
        if (!deletedDefaults.contains(id)) {
          deletedDefaults.add(id);
          await prefs.setStringList(_deletedDefaultsKey, deletedDefaults);
        }
      } catch (_) {}
    } else {
      await _saveCustomFavorites();
    }
  }

  Future<void> resetFavorites() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_deletedDefaultsKey);
      await _loadFavorites();
    } catch (_) {}
  }

  Future<void> _saveCustomFavorites() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final customList = state.where((cmd) => cmd.isCustom).toList();
      final jsonList = customList
          .map((cmd) => jsonEncode(cmd.toJson()))
          .toList();
      await prefs.setStringList(_prefsKey, jsonList);
    } catch (_) {}
  }
}
