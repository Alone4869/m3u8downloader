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
}
