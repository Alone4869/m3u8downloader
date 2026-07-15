import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

const defaultBrowserHomeUrl = 'https://savetwitter.net/zh-cn3';

String normalizeBrowserHomeUrl(String input) {
  var value = input.trim();
  if (value.isEmpty) throw const FormatException('网址不能为空');
  if (!value.startsWith(RegExp(r'https?://', caseSensitive: false))) {
    value = 'https://$value';
  }
  final uri = Uri.tryParse(value);
  if (uri == null ||
      !uri.hasAuthority ||
      uri.host.isEmpty ||
      (uri.scheme != 'http' && uri.scheme != 'https')) {
    throw const FormatException('请输入有效的 HTTP 或 HTTPS 网址');
  }
  return uri.toString();
}

class BrowserSettingsStore {
  BrowserSettingsStore._();

  static final BrowserSettingsStore instance = BrowserSettingsStore._();
  static const _homeUrlKey = 'browser.homeUrl';

  final ValueNotifier<String> homeUrl = ValueNotifier(defaultBrowserHomeUrl);

  Future<String> load() async {
    final preferences = await SharedPreferences.getInstance();
    final stored = preferences.getString(_homeUrlKey);
    final value = stored == null
        ? defaultBrowserHomeUrl
        : _normalizeOrDefault(stored);
    if (homeUrl.value != value) homeUrl.value = value;
    return value;
  }

  Future<void> save(String input) async {
    final value = normalizeBrowserHomeUrl(input);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_homeUrlKey, value);
    if (homeUrl.value != value) homeUrl.value = value;
  }

  String _normalizeOrDefault(String value) {
    try {
      return normalizeBrowserHomeUrl(value);
    } on FormatException {
      return defaultBrowserHomeUrl;
    }
  }
}
