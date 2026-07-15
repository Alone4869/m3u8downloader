import 'package:flutter_test/flutter_test.dart';
import 'package:m3u8downloader/src/browser_settings.dart';

void main() {
  test('normalizes a browser homepage without a scheme', () {
    expect(
      normalizeBrowserHomeUrl('example.com/path'),
      'https://example.com/path',
    );
  });

  test('preserves a valid HTTP homepage', () {
    expect(
      normalizeBrowserHomeUrl('http://192.168.1.2:8080/home'),
      'http://192.168.1.2:8080/home',
    );
  });

  test('rejects an invalid browser homepage', () {
    expect(() => normalizeBrowserHomeUrl('https://'), throwsFormatException);
  });
}
