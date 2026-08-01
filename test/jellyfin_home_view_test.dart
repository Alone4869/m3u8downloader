import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:m3u8downloader/src/jellyfin_client.dart';
import 'package:m3u8downloader/src/jellyfin_home_view.dart';
import 'package:m3u8downloader/src/server_settings.dart';

const _jsonHeaders = {'content-type': 'application/json'};

http.Response _ok(Object body) =>
    http.Response(jsonEncode(body), 200, headers: _jsonHeaders);

ServerConfig _config() => ServerConfig(
  id: 'srv',
  type: ServerType.jellyfin,
  name: '家庭影院',
  url: 'http://192.168.1.10:8096',
  userId: 'u1',
  accessToken: 'tok',
  createdAt: DateTime.parse('2026-08-02T10:00:00'),
);

JellyfinClient _client(MockClient mock) => JellyfinClient(
  httpClient: mock,
  baseUrl: 'http://192.168.1.10:8096',
  accessToken: 'tok',
  userId: 'u1',
);

MockClient _homeMock() => MockClient((request) async {
  final path = request.url.path;
  final query = request.url.queryParameters;
  if (path.endsWith('/Views')) {
    return _ok({
      'Items': [
        {
          'Id': 'v1',
          'Name': '电影',
          'CollectionType': 'movies',
          'ImageTags': {'Primary': 'vt1'},
        },
        {'Id': 'v2', 'Name': '剧集', 'CollectionType': 'tvshows'},
      ],
    });
  }
  if (path.endsWith('/Items/Resume')) {
    return _ok({
      'Items': [
        {
          'Id': 'r1',
          'Type': 'Movie',
          'Name': '继续片',
          'ProductionYear': 2020,
          'UserData': {'PlayedPercentage': 42},
          'ImageTags': {'Primary': 'rt1'},
        },
      ],
    });
  }
  if (path.contains('/Items/Latest')) {
    if (query['ParentId'] == 'v1') {
      return _ok([
        {
          'Id': 'm1',
          'Type': 'Movie',
          'Name': '新电影',
          'ProductionYear': 2026,
          'CommunityRating': 8.5,
          'Genres': ['科幻', '动作'],
          'ImageTags': {'Primary': 'p1'},
          'BackdropImageTags': ['b1'],
          'Overview': '简介文本',
          'RunTimeTicks': 9000000000,
        },
      ]);
    }
    return _ok(<Object>[]);
  }
  if (path.endsWith('/Items')) {
    if (query['ParentId'] == 'v1') return _ok({'TotalRecordCount': 128});
    return _ok({'TotalRecordCount': 45});
  }
  return http.Response('not found', 404);
});

Future<void> _pumpHome(WidgetTester tester, JellyfinClient client) async {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: JellyfinHomeView(config: _config(), client: client),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('home renders carousel, resume, libraries and latest', (
    tester,
  ) async {
    await _pumpHome(tester, _client(_homeMock()));

    expect(find.text('新电影'), findsWidgets);
    expect(find.text('继续观看'), findsOneWidget);
    expect(find.text('继续片'), findsOneWidget);
    expect(find.text('媒体库'), findsOneWidget);
    expect(find.text('电影'), findsOneWidget);
    expect(find.text('128 部'), findsOneWidget);
    expect(find.text('45 部'), findsOneWidget);
    expect(find.text('电影 · 最新添加'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('empty server shows friendly message', (tester) async {
    final client = _client(
      MockClient(
        (request) async => _ok({'Items': <Object>[]}),
      ),
    );
    await _pumpHome(tester, client);

    expect(find.text('这个服务器上还没有媒体库'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('load failure shows retry and retry succeeds', (tester) async {
    var failing = true;
    final client = _client(
      MockClient((request) async {
        if (failing) throw Exception('boom');
        return _ok({'Items': <Object>[]});
      }),
    );
    await _pumpHome(tester, client);

    expect(find.text('无法连接服务器，请检查网络'), findsOneWidget);

    failing = false;
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();

    expect(find.text('这个服务器上还没有媒体库'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('401 pops with token expired result', (tester) async {
    bool? result;
    final client = _client(
      MockClient((request) async => http.Response('', 401)),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () async {
                result = await Navigator.push<bool>(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        JellyfinHomeView(config: _config(), client: client),
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

    expect(result, true);
  });

  testWidgets('detail expired result pops with true', (tester) async {
    bool? result;
    final client = _client(
      MockClient((request) async {
        final path = request.url.path;
        final query = request.url.queryParameters;
        if (path.endsWith('/Views')) {
          return _ok({
            'Items': [
              {
                'Id': 'v1',
                'Name': '电影',
                'CollectionType': 'movies',
                'ImageTags': {'Primary': 'vt1'},
              },
              {'Id': 'v2', 'Name': '剧集', 'CollectionType': 'tvshows'},
            ],
          });
        }
        if (path.endsWith('/Items/Resume')) {
          return _ok({
            'Items': [
              {
                'Id': 'r1',
                'Type': 'Movie',
                'Name': '继续片',
                'ProductionYear': 2020,
                'UserData': {'PlayedPercentage': 42},
                'ImageTags': {'Primary': 'rt1'},
              },
            ],
          });
        }
        if (path.contains('/Items/Latest')) {
          if (query['ParentId'] == 'v1') {
            return _ok([
              {
                'Id': 'm1',
                'Type': 'Movie',
                'Name': '新电影',
                'ProductionYear': 2026,
                'CommunityRating': 8.5,
                'Genres': ['科幻', '动作'],
                'ImageTags': {'Primary': 'p1'},
                'BackdropImageTags': ['b1'],
                'Overview': '简介文本',
                'RunTimeTicks': 9000000000,
              },
            ]);
          }
          return _ok(<Object>[]);
        }
        if (path.endsWith('/Items')) {
          if (query['ParentId'] == 'v1') return _ok({'TotalRecordCount': 128});
          return _ok({'TotalRecordCount': 45});
        }
        if (path.contains('m1')) return http.Response('', 401);
        return http.Response('not found', 404);
      }),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () async {
                result = await Navigator.push<bool>(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        JellyfinHomeView(config: _config(), client: client),
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

    await tester.tap(find.text('新电影').first);
    await tester.pumpAndSettle();

    expect(result, true);
  });
}
