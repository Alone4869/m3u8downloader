import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:m3u8downloader/src/twitter_parser.dart';

void main() {
  test('extracts and normalizes an X status URL from shared text', () {
    const input =
        '看看这个 https://twitter.com/example/status/1790637656616943991?s=20';

    expect(TwitterParser.extractTweetId(input), '1790637656616943991');
    expect(
      TwitterParser.extractTweetUrl(input),
      'https://x.com/i/status/1790637656616943991',
    );
  });

  test('parses and sorts all MP4 quality variants from FxTwitter', () {
    final info = TwitterParser.parseFxResponse({
      'tweet': {
        'id': '1790637656616943991',
        'url': 'https://x.com/example/status/1790637656616943991',
        'text': 'Video tweet',
        'author': {
          'name': 'Example',
          'screen_name': 'example',
          'avatar_url': 'https://example.com/avatar.jpg',
        },
        'media': {
          'all': [
            {
              'id': 'video-1',
              'type': 'video',
              'thumbnail_url': 'https://example.com/thumb.jpg',
              'duration': 12.5,
              'formats': [
                {
                  'url': 'https://video.twimg.com/vid/272x270/low.mp4',
                  'bitrate': 288000,
                  'container': 'mp4',
                },
                {
                  'url': 'https://video.twimg.com/vid/728x720/high.mp4',
                  'bitrate': 2176000,
                  'container': 'mp4',
                },
                {
                  'url': 'https://video.twimg.com/video/master.m3u8',
                  'container': 'm3u8',
                },
              ],
            },
          ],
        },
      },
    }, sourceUrl: 'https://x.com/i/status/1790637656616943991');

    expect(info.authorUsername, 'example');
    expect(info.media, hasLength(1));
    expect(info.media.single.variants, hasLength(2));
    expect(info.media.single.variants.first.qualityLabel, '720p');
    expect(info.media.single.variants.last.qualityLabel, '270p');
    expect(info.media.single.variants.first.bitrate, 2176000);
  });

  test('matches a SnapCDN relay token to its original quality URL', () {
    const directUrl =
        'https://video.twimg.com/video/vid/avc1/1920x1080/video.mp4?tag=12';
    final payload = base64Url
        .encode(
          utf8.encode(
            jsonEncode({'url': directUrl, 'filename': 'video-1080p.mp4'}),
          ),
        )
        .replaceAll('=', '');
    final relayUrl =
        'https://dl.snapcdn.app/get?token=header.$payload.signature';

    expect(
      TwitterParser.parseSnapCdnResponse({
        'status': 'ok',
        'data': '<a href="$relayUrl">下载 MP4 (1080p)</a>',
      }, directUrl: directUrl),
      relayUrl,
    );
  });
}
