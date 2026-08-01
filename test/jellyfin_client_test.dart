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
    expect(seen!.queryParameters['Fields'], 'BackdropImageTags,Genres');
    expect(items.single.name, '新电影');
    expect(items.single.year, 2026);
    expect(items.single.runtimeMs, 900000);
    expect(items.single.genres, ['科幻']);
    expect(items.single.backdropImageTag, 'b1');
  });

  test('fetchItems pages through a library', () async {
    Uri? seen;
    final client = _client((request) async {
      seen = request.url;
      return _ok({
        'Items': [
          {'Id': 'i1', 'Type': 'Movie', 'Name': '第一页'},
          {'Id': 'i2', 'Type': 'Movie', 'Name': '第二页'},
        ],
      });
    });
    final items = await client.fetchItems(
      parentId: 'v1',
      limit: 48,
      startIndex: 48,
    );
    expect(items, hasLength(2));
    expect(items.first.name, '第一页');
    expect(seen!.path, '/Users/u1/Items');
    expect(seen!.queryParameters['ParentId'], 'v1');
    expect(seen!.queryParameters['Recursive'], 'true');
    expect(seen!.queryParameters['Limit'], '48');
    expect(seen!.queryParameters['StartIndex'], '48');
  });

  test('fetchItem parses media sources into media info', () async {
    final client = _client(
      (request) async => _ok({
        'Id': 'd1',
        'Type': 'Movie',
        'Name': '星际穿越',
        'ImageTags': {'Primary': 'p1'},
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
              {'Type': 'Audio', 'Codec': 'aac', 'Channels': 2},
            ],
          },
        ],
      }),
    );
    final item = await client.fetchItem('d1');
    expect(item.resolution, '1920x1080');
    expect(item.videoCodec, 'h264');
    expect(item.audioCodec, 'aac');
    expect(item.frameRate, closeTo(23.976, 0.001));
  });

  test('fetchItem tolerates missing media sources', () async {
    final client = _client(
      (request) async => _ok({'Id': 'd1', 'Type': 'Movie', 'Name': '无媒体源'}),
    );
    final item = await client.fetchItem('d1');
    expect(item.resolution, isNull);
    expect(item.videoCodec, isNull);
    expect(item.audioCodec, isNull);
  });

  test('fetchViewCount reads TotalRecordCount', () async {    final client = _client(
      (request) async => _ok({'TotalRecordCount': 128}),
    );
    expect(await client.fetchViewCount('v1', itemType: 'Movie'), 128);
  });

  test('fetchItem requests fields and parses detail with people', () async {
    Uri? seen;
    final client = _client((request) async {
      seen = request.url;
      return _ok({
        'Id': 'd1',
        'Type': 'Movie',
        'Name': '星际穿越',
        'Overview': '一段旅程。',
        'ImageTags': {'Primary': 'p1'},
        'People': [
          {'Id': 'p1', 'Name': '诺兰', 'Role': '导演', 'PrimaryImageTag': 'pp1'},
          {'Id': 'p2', 'Name': '马修', 'Role': '演员'},
        ],
      });
    });
    final item = await client.fetchItem('d1');
    expect(
      seen!.queryParameters['Fields'],
      'People,Genres,Overview,BackdropImageTags,MediaSources',
    );
    expect(item.name, '星际穿越');
    expect(item.overview, '一段旅程。');
    expect(item.people, hasLength(2));
    expect(item.people.first.name, '诺兰');
    expect(item.people.first.role, '导演');
    expect(item.people.first.imageTag, 'pp1');
    expect(item.people.last.imageTag, isNull);
  });

  test('fetchItem tolerates missing people field', () async {
    final client = _client(
      (request) async => _ok({'Id': 'd1', 'Type': 'Movie', 'Name': '无演职员'}),
    );
    final item = await client.fetchItem('d1');
    expect(item.people, isEmpty);
  });

  test('fetchPlaybackUrl builds progressive mp4 stream url', () async {
    final client = _client((request) async {
      expect(request.method, 'POST');
      expect(request.url.path, '/Items/d1/PlaybackInfo');
      return _ok({'MediaSources': [{'Id': 'ms1'}]});
    });
    final url = await client.fetchPlaybackUrl('d1');
    expect(
      url,
      'http://192.168.1.10:8096/videos/d1/stream.mp4'
      '?api_key=tok&MediaSourceId=ms1&UserId=u1&Static=false',
    );
  });

  test('fetchPlaybackUrl uses static stream for mp4 sources', () async {
    final client = _client(
      (request) async => _ok({
        'MediaSources': [
          {
            'Id': 'ms1',
            'Container': 'mov,mp4,m4a,3gp,3g2,mj2',
            'SupportsDirectStream': true,
          },
        ],
      }),
    );
    final url = await client.fetchPlaybackUrl('d1');
    expect(url, contains('Static=true'));
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
