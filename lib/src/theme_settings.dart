import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppThemeMode { system, light, dark }

extension AppThemeModeText on AppThemeMode {
  String get title => switch (this) {
    AppThemeMode.system => '跟随系统',
    AppThemeMode.light => '浅色模式',
    AppThemeMode.dark => '深色模式',
  };

  String get description => switch (this) {
    AppThemeMode.system => '根据系统外观自动切换',
    AppThemeMode.light => '始终使用浅色外观',
    AppThemeMode.dark => '始终使用深色外观',
  };

  IconData get icon => switch (this) {
    AppThemeMode.system => Icons.brightness_auto_outlined,
    AppThemeMode.light => Icons.light_mode_outlined,
    AppThemeMode.dark => Icons.dark_mode_outlined,
  };

  ThemeMode get themeMode => switch (this) {
    AppThemeMode.system => ThemeMode.system,
    AppThemeMode.light => ThemeMode.light,
    AppThemeMode.dark => ThemeMode.dark,
  };
}

class ThemeModeStore {
  ThemeModeStore._();

  static final ThemeModeStore instance = ThemeModeStore._();
  static const _modeKey = 'app.themeMode';

  final ValueNotifier<AppThemeMode> mode = ValueNotifier(AppThemeMode.system);

  Future<AppThemeMode> load() async {
    final preferences = await SharedPreferences.getInstance();
    final stored = preferences.getString(_modeKey);
    final value = AppThemeMode.values.firstWhere(
      (item) => item.name == stored,
      orElse: () => AppThemeMode.system,
    );
    if (mode.value != value) mode.value = value;
    return value;
  }

  Future<void> save(AppThemeMode value) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_modeKey, value.name);
    if (mode.value != value) mode.value = value;
  }
}
