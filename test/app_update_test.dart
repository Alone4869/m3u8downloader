import 'package:flutter_test/flutter_test.dart';
import 'package:m3u8downloader/src/app_update.dart';

void main() {
  test('compares dotted release versions', () {
    expect(compareVersions('1.2.0', '1.1.9'), isPositive);
    expect(compareVersions('v1.2', '1.2.0+24'), 0);
    expect(compareVersions('1.0.9', '1.1.0'), isNegative);
  });

  test('parses a GitHub release and prefers its APK asset', () {
    final release = parseGitHubRelease({
      'tag_name': 'v1.2.0',
      'name': 'Version 1.2.0',
      'body': 'Changes',
      'html_url': 'https://github.com/example/releases/tag/v1.2.0',
      'assets': [
        {
          'name': 'm3u8-downloader-v1.2.0.apk',
          'browser_download_url': 'https://example.com/app.apk',
        },
      ],
    });

    expect(release.version, '1.2.0');
    expect(release.notes, 'Changes');
    expect(release.preferredUrl, Uri.parse('https://example.com/app.apk'));
    expect(
      release.isNewerThan(const AppVersion(version: '1.1.6', buildNumber: 23)),
      isTrue,
    );
  });

  test('selects the APK matching the first supported device ABI', () {
    final release = parseGitHubRelease(
      {
        'tag_name': 'v1.2.1',
        'html_url': 'https://github.com/example/releases/tag/v1.2.1',
        'assets': [
          {
            'name': 'm3u8-downloader-v1.2.1-armeabi-v7a.apk',
            'browser_download_url': 'https://example.com/armv7.apk',
          },
          {
            'name': 'm3u8-downloader-v1.2.1-arm64-v8a.apk',
            'browser_download_url': 'https://example.com/arm64.apk',
          },
          {
            'name': 'm3u8-downloader-v1.2.1-x86_64.apk',
            'browser_download_url': 'https://example.com/x86_64.apk',
          },
        ],
      },
      supportedAbis: const ['arm64-v8a', 'armeabi-v7a'],
    );

    expect(release.downloadUrl, Uri.parse('https://example.com/arm64.apk'));
  });

  test('opens the release page when none of multiple APKs match', () {
    final release = parseGitHubRelease(
      {
        'tag_name': 'v1.2.1',
        'html_url': 'https://github.com/example/releases/tag/v1.2.1',
        'assets': [
          {
            'name': 'm3u8-downloader-v1.2.1-arm64-v8a.apk',
            'browser_download_url': 'https://example.com/arm64.apk',
          },
          {
            'name': 'm3u8-downloader-v1.2.1-x86_64.apk',
            'browser_download_url': 'https://example.com/x86_64.apk',
          },
        ],
      },
      supportedAbis: const ['riscv64'],
    );

    expect(release.downloadUrl, isNull);
    expect(
      release.preferredUrl,
      Uri.parse('https://github.com/example/releases/tag/v1.2.1'),
    );
  });
}
