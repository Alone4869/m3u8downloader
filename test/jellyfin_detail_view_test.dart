import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:m3u8downloader/src/jellyfin_client.dart';
import 'package:m3u8downloader/src/jellyfin_detail_view.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

const _jsonHeaders = {'content-type': 'application/json'};
final _originalLauncher = UrlLauncherPlatform.instance;

http.Response _ok(Object body) =>
    http.Response(jsonEncode(body), 200, headers: _jsonHeaders);

class _FakeLauncher extends UrlLauncherPlatform {
  String? launchedUrl;

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launchedUrl = url;
    return true;
  }

  @override
  Future<bool> supportsMode(PreferredLaunchMode mode) async => true;
}

JellyfinClient _detailClient() => JellyfinClient(
  httpClient: MockClient((request) async {
    final path = request.url.path;
    if (path.endsWith('/Items/d1/PlaybackInfo')) {
      return _ok({
        'MediaSources': [
          {'Id': 'ms1'},
        ],
      });
    }
    return _ok({
      'Id': 'd1',
      'Type': 'Movie',
      'Name': '星际穿越',
      'ProductionYear': 2014,
      'RunTimeTicks': 9000000000,
      'CommunityRating': 8.6,
      'Genres': ['科幻', '冒险'],
      'Overview': '一段跨越时空的旅程。',
      'ImageTags': {'Primary': 'p1'},
      'BackdropImageTags': ['b1'],
      'MediaSources': [
        {
          'MediaStreams': [
            {
              'Type': 'Video',
              'Codec': 'h264',
              'Width': 1920,
              'Height': 1080,
              'FrameRate': 23.976,
            },
            {'Type': 'Audio', 'Codec': 'aac'},
          ],
        },
      ],
      'People': [
        {'Id': 'p1', 'Name': '克里斯托弗·诺兰', 'Role': '导演'},
        {'Id': 'p2', 'Name': '马修·麦康纳', 'Role': '演员'},
      ],
    });
  }),
  baseUrl: 'http://192.168.1.10:8096',
  accessToken: 'tok',
  userId: 'u1',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final launcher = _FakeLauncher();

  setUp(() {
    launcher.launchedUrl = null;
    UrlLauncherPlatform.instance = launcher;
    addTearDown(() => UrlLauncherPlatform.instance = _originalLauncher);
  });

  testWidgets('detail shows info, people and play launches stream', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: JellyfinDetailView(itemId: 'd1', client: _detailClient()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('星际穿越'), findsWidgets);
    expect(find.text('2014'), findsOneWidget);
    expect(find.text('15 分钟'), findsOneWidget);
    expect(find.text('一段跨越时空的旅程。'), findsOneWidget);
    expect(find.text('克里斯托弗·诺兰'), findsOneWidget);
    expect(find.text('导演'), findsOneWidget);
    expect(find.text('媒体信息'), findsOneWidget);
    expect(find.text('1920x1080'), findsOneWidget);
    expect(find.text('h264'), findsOneWidget);
    expect(find.text('aac'), findsOneWidget);
    expect(find.text('23.976 fps'), findsOneWidget);

    await tester.tap(find.text('播放'));
    await tester.pumpAndSettle();

    expect(launcher.launchedUrl, isNotNull);
    expect(launcher.launchedUrl, contains('stream.mp4'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('401 pops with token expired result', (tester) async {
    String? result;
    final client = JellyfinClient(
      httpClient: MockClient((request) async => http.Response('', 401)),
      baseUrl: 'http://192.168.1.10:8096',
      accessToken: 'tok',
      userId: 'u1',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () async {
                result = await Navigator.push<String>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => JellyfinDetailView(itemId: 'd1', client: client),
                  ),
                );
              },
              child: const Text('go'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    expect(result, 'expired');
  });

  testWidgets('play path 401 pops with expired result', (tester) async {
    String? result;
    final client = JellyfinClient(
      httpClient: MockClient((request) async {
        final path = request.url.path;
        if (path.endsWith('/Items/d1/PlaybackInfo')) {
          return http.Response('', 401);
        }
        return _ok({
          'Id': 'd1',
          'Type': 'Movie',
          'Name': '星际穿越',
          'ProductionYear': 2014,
          'RunTimeTicks': 9000000000,
          'CommunityRating': 8.6,
          'Genres': ['科幻', '冒险'],
          'Overview': '一段跨越时空的旅程。',
          'ImageTags': {'Primary': 'p1'},
          'BackdropImageTags': ['b1'],
          'People': [
            {'Id': 'p1', 'Name': '克里斯托弗·诺兰', 'Role': '导演'},
          ],
        });
      }),
      baseUrl: 'http://192.168.1.10:8096',
      accessToken: 'tok',
      userId: 'u1',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () async {
                result = await Navigator.push<String>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => JellyfinDetailView(itemId: 'd1', client: client),
                  ),
                );
              },
              child: const Text('go'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('播放'));
    await tester.pumpAndSettle();

    expect(result, 'expired');
  });
}
