import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:m3u8downloader/src/theme_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('defaults to system mode', () async {
    expect(await ThemeModeStore.instance.load(), AppThemeMode.system);
    expect(ThemeModeStore.instance.mode.value, AppThemeMode.system);
  });

  test('loads persisted mode', () async {
    SharedPreferences.setMockInitialValues({'app.themeMode': 'dark'});
    expect(await ThemeModeStore.instance.load(), AppThemeMode.dark);
    expect(ThemeModeStore.instance.mode.value, AppThemeMode.dark);
  });

  test('save persists and notifies', () async {
    await ThemeModeStore.instance.save(AppThemeMode.light);
    expect(ThemeModeStore.instance.mode.value, AppThemeMode.light);
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('app.themeMode'), 'light');
    expect(await ThemeModeStore.instance.load(), AppThemeMode.light);
  });

  test('themeMode mapping', () {
    expect(AppThemeMode.system.themeMode, ThemeMode.system);
    expect(AppThemeMode.light.themeMode, ThemeMode.light);
    expect(AppThemeMode.dark.themeMode, ThemeMode.dark);
  });
}
