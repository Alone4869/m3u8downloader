import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:m3u8downloader/src/jellyfin_client.dart';

const _jsonHeaders = {'content-type': 'application/json'};

http.Response _ok(Object body) =>
    http.Response(jsonEncode(body), 200, headers: _jsonHeaders);

JellyfinClient _client(Future<http.Response> Function(http.Request) handler) =>
    JellyfinClient(
      httpClient: MockClient(handler),
      baseUrl: 'http://192.168.1.10:8096',
      accessToken: 'tok',
      userId: 'u1',
    );

void main() {
  test('login succeeds and stores token and user id', () async {
    final client = JellyfinClient(
      httpClient: MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/Users/AuthenticateByName');
        return _ok({'User': {'Id': 'u1'}, 'AccessToken': 'abc'});
      }),
    );
    await client.login(
      baseUrl: 'http://192.168.1.10:8096/',
      username: 'alice',
      password: 'pw',
    );
    expect(client.baseUrl, 'http://192.168.1.10:8096');
    expect(client.accessToken, 'abc');
    expect(client.userId, 'u1');
  });

  test('login with wrong password throws 401 message', () async {
    final client = JellyfinClient(
      httpClient: MockClient((request) async => http.Response('', 401)),
    );
    await expectLater(
      client.login(baseUrl: 'http://a', username: 'a', password: 'b'),
      throwsA(
        isA<JellyfinException>().having(
          (e) => e.message,
          'message',
          '账号或密码错误',
        ),
      ),
    );
  });

  test('login network failure throws connection message', () async {
    final client = JellyfinClient(
      httpClient: MockClient((request) async => throw Exception('boom')),
    );
    await expectLater(
      client.login(baseUrl: 'http://a', username: 'a', password: 'b'),
      throwsA(
        isA<JellyfinException>().having(
          (e) => e.message,
          'message',
          '无法连接服务器，请检查地址和网络',
        ),
      ),
    );
  });

  test('fetchViews parses views', () async {
    final client = _client((request) async => _ok({
          'Items': [
            {
              'Id': 'v1',
              'Name': '电影',
              'CollectionType': 'movies',
              'ImageTags': {'Primary': 't1'},
            },
            {'Id': 'v2', 'Name': '剧集', 'CollectionType': 'tvshows'},
          ],
        }));
    final views = await client.fetchViews();
    expect(views, hasLength(2));
    expect(views.first.id, 'v1');
    expect(views.first.name, '电影');
    expect(views.first.collectionType, 'movies');
    expect(views.first.primaryImageTag, 't1');
  });

  test('fetchResume parses progress percentage', () async {
    final client = _client((request) async => _ok({
          'Items': [
            {
              'Id': 'r1',
              'Type': 'Movie',
              'Name': '继续片',
              'UserData': {'PlayedPercentage': 42},
            },
          ],
        }));
    final items = await client.fetchResume();
    expect(items.single.name, '继续片');
    expect(items.single.progress, closeTo(0.42, 0.001));
  });

  test('fetchLatest sends parent and limit params', () async {
    Uri? seen;
    final client = _client((request) async {
      seen = request.url;
      return _ok([
        {
          'Id': 'm1',
          'Type': 'Movie',
          'Name': '新电影',
          'ProductionYear': 2026,
          'CommunityRating': 8.5,
          'Genres': ['科幻'],
          'ImageTags': {'Primary': 'p1'},
          'BackdropImageTags': ['b1'],
          'RunTimeTicks': 9000000000,
        },
      ]);
    });
    final items = await client.fetchLatest(parentId: 'v1', limit: 5);
    expect(seen!.queryParameters['ParentId'], 'v1');
    expect(seen!.queryParameters['Limit'], '5');
    expect(items.single.name, '新电影');
    expect(items.single.year, 2026);
    expect(items.single.runtimeMs, 900000);
    expect(items.single.genres, ['科幻']);
    expect(items.single.backdropImageTag, 'b1');
  });

  test('fetchViewCount reads TotalRecordCount', () async {
    final client = _client(
      (request) async => _ok({'TotalRecordCount': 128}),
    );
    expect(await client.fetchViewCount('v1', itemType: 'Movie'), 128);
  });

  test('fetchItem parses detail', () async {
    final client = _client(
      (request) async => _ok({
        'Id': 'd1',
        'Type': 'Movie',
        'Name': '星际穿越',
        'Overview': '一段旅程。',
        'ImageTags': {'Primary': 'p1'},
      }),
    );
    final item = await client.fetchItem('d1');
    expect(item.name, '星际穿越');
    expect(item.overview, '一段旅程。');
  });

  test('fetchPeople parses cast', () async {
    final client = _client(
      (request) async => _ok([
        {'Id': 'p1', 'Name': '诺兰', 'Role': '导演', 'PrimaryImageTag': 'pp1'},
        {'Id': 'p2', 'Name': '马修', 'Role': '演员'},
      ]),
    );
    final people = await client.fetchPeople('d1');
    expect(people, hasLength(2));
    expect(people.first.role, '导演');
    expect(people.last.imageTag, isNull);
  });

  test('fetchPlaybackUrl builds m3u8 url from media source', () async {
    final client = _client((request) async {
      expect(request.method, 'POST');
      expect(request.url.path, '/Items/d1/PlaybackInfo');
      return _ok({'MediaSources': [{'Id': 'ms1'}]});
    });
    final url = await client.fetchPlaybackUrl('d1');
    expect(
      url,
      'http://192.168.1.10:8096/videos/d1/master.m3u8'
      '?api_key=tok&MediaSourceId=ms1&UserId=u1',
    );
  });

  test('fetchPlaybackUrl throws when no media source', () async {
    final client = _client((request) async => _ok({'MediaSources': []}));
    await expectLater(
      client.fetchPlaybackUrl('d1'),
      throwsA(isA<JellyfinException>()),
    );
  });

  test('fetchPlaybackUrl wraps malformed body as exception', () async {
    final client = _client(
      (request) async => http.Response('not json', 200),
    );
    await expectLater(
      client.fetchPlaybackUrl('d1'),
      throwsA(
        isA<JellyfinException>().having(
          (e) => e.message,
          'message',
          '无法获取播放地址，请检查网络',
        ),
      ),
    );
  });

  test('401 responses throw statusCode 401 exception', () async {
    final client = _client((request) async => http.Response('', 401));
    await expectLater(
      client.fetchViews(),
      throwsA(
        isA<JellyfinException>().having(
          (e) => e.statusCode,
          'statusCode',
          401,
        ),
      ),
    );
  });

  test('imageUrl appends api key and tag', () async {
    final client = _client((request) async => _ok(const {}));
    expect(
      client.imageUrl('m1', tag: 'p1', maxWidth: 300),
      contains('api_key=tok'),
    );
    expect(client.imageUrl('m1', tag: 'p1'), contains('tag=p1'));
  });
}
