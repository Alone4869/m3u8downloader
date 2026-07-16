import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum TwitterDownloadRoute { direct, snapCdn }

extension TwitterDownloadRouteText on TwitterDownloadRoute {
  String get title => switch (this) {
    TwitterDownloadRoute.direct => 'X 官方直连',
    TwitterDownloadRoute.snapCdn => 'SnapCDN 中转',
  };

  String get description => switch (this) {
    TwitterDownloadRoute.direct => '直接连接 video.twimg.com，速度更高但部分网络需要代理',
    TwitterDownloadRoute.snapCdn => '通过 SaveTwitter/SnapVid 获取临时链接，通常无需代理',
  };
}

class TwitterDownloadSettingsStore {
  TwitterDownloadSettingsStore._();

  static final TwitterDownloadSettingsStore instance =
      TwitterDownloadSettingsStore._();
  static const _routeKey = 'twitter.downloadRoute';

  final ValueNotifier<TwitterDownloadRoute> route = ValueNotifier(
    TwitterDownloadRoute.direct,
  );

  Future<TwitterDownloadRoute> load() async {
    final preferences = await SharedPreferences.getInstance();
    final stored = preferences.getString(_routeKey);
    final value = TwitterDownloadRoute.values.firstWhere(
      (item) => item.name == stored,
      orElse: () => TwitterDownloadRoute.direct,
    );
    if (route.value != value) route.value = value;
    return value;
  }

  Future<void> save(TwitterDownloadRoute value) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_routeKey, value.name);
    if (route.value != value) route.value = value;
  }
}
