import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

const updateRepository = String.fromEnvironment(
  'UPDATE_REPOSITORY',
  defaultValue: 'Alone4869/m3u8downloader',
);

class AppVersion {
  const AppVersion({required this.version, required this.buildNumber});

  final String version;
  final int buildNumber;

  String get display => '$version ($buildNumber)';
}

class AppRelease {
  const AppRelease({
    required this.version,
    required this.title,
    required this.notes,
    required this.pageUrl,
    required this.downloadUrl,
  });

  final String version;
  final String title;
  final String notes;
  final Uri pageUrl;
  final Uri? downloadUrl;

  bool isNewerThan(AppVersion current) =>
      compareVersions(version, current.version) > 0;

  Uri get preferredUrl => downloadUrl ?? pageUrl;
}

class UpdateNotConfiguredException implements Exception {
  const UpdateNotConfiguredException();

  @override
  String toString() => '未配置公开的 GitHub 更新仓库';
}

class AppUpdateService {
  AppUpdateService({this.client});

  static const _methods = MethodChannel('m3u8_downloader/methods');
  final HttpClient? client;
  HttpClient? _createdClient;

  Future<AppVersion> getCurrentVersion() async {
    final value = await _methods.invokeMapMethod<String, Object?>('getAppInfo');
    return AppVersion(
      version: value?['versionName'] as String? ?? '0.0.0',
      buildNumber: value?['versionCode'] as int? ?? 0,
    );
  }

  Future<AppRelease> fetchLatestRelease() async {
    if (updateRepository.trim().isEmpty) {
      throw const UpdateNotConfiguredException();
    }

    final uri = Uri.https(
      'api.github.com',
      '/repos/$updateRepository/releases/latest',
    );
    final httpClient =
        client ??
        (_createdClient ??= HttpClient()
          ..connectionTimeout = const Duration(seconds: 15));
    final request = await httpClient.getUrl(uri);
    request.headers
      ..set(HttpHeaders.acceptHeader, 'application/vnd.github+json')
      ..set(HttpHeaders.userAgentHeader, 'M3U8-Downloader')
      ..set('X-GitHub-Api-Version', '2022-11-28');
    final response = await request.close().timeout(const Duration(seconds: 15));
    final body = await utf8.decoder.bind(response).join();
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException(
        response.statusCode == HttpStatus.notFound
            ? '未找到公开的 GitHub Release'
            : 'GitHub 返回 HTTP ${response.statusCode}',
        uri: uri,
      );
    }
    return parseGitHubRelease(jsonDecode(body) as Map<String, Object?>);
  }

  Future<void> openRelease(AppRelease release) => _methods.invokeMethod<void>(
    'openUrl',
    {'url': release.preferredUrl.toString()},
  );

  void close() => _createdClient?.close(force: true);
}

AppRelease parseGitHubRelease(Map<String, Object?> json) {
  final tag = (json['tag_name'] as String? ?? '').trim();
  final pageUrl = Uri.tryParse(json['html_url'] as String? ?? '');
  if (!RegExp(r'^[vV]?\d+(?:\.\d+){1,2}(?:[-+].*)?$').hasMatch(tag) ||
      pageUrl == null ||
      pageUrl.scheme != 'https') {
    throw const FormatException('GitHub Release 缺少版本号或页面地址');
  }

  Uri? apkUrl;
  final assets = json['assets'];
  if (assets is List) {
    for (final asset in assets.whereType<Map>()) {
      final name = (asset['name'] as String? ?? '').toLowerCase();
      final candidate = Uri.tryParse(
        asset['browser_download_url'] as String? ?? '',
      );
      if (name.endsWith('.apk') && candidate?.hasScheme == true) {
        apkUrl = candidate;
        break;
      }
    }
  }

  return AppRelease(
    version: tag.replaceFirst(RegExp(r'^[vV]'), ''),
    title: (json['name'] as String?)?.trim().isNotEmpty == true
        ? (json['name'] as String).trim()
        : tag,
    notes: (json['body'] as String? ?? '').trim(),
    pageUrl: pageUrl,
    downloadUrl: apkUrl,
  );
}

int compareVersions(String left, String right) {
  List<int> parts(String value) {
    final normalized = value
        .replaceFirst(RegExp(r'^[vV]'), '')
        .split(RegExp(r'[-+]'))
        .first;
    return normalized
        .split('.')
        .map((part) => int.tryParse(part) ?? 0)
        .toList(growable: false);
  }

  final leftParts = parts(left);
  final rightParts = parts(right);
  final length = leftParts.length > rightParts.length
      ? leftParts.length
      : rightParts.length;
  for (var index = 0; index < length; index++) {
    final leftPart = index < leftParts.length ? leftParts[index] : 0;
    final rightPart = index < rightParts.length ? rightParts[index] : 0;
    if (leftPart != rightPart) return leftPart.compareTo(rightPart);
  }
  return 0;
}
