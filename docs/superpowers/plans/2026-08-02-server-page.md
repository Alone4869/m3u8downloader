# 服务器页（Jellyfin）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为 M3U8 下载器新增「服务器」Tab（第 4 个 Tab），支持添加/删除 Jellyfin 服务器（Emby/SMB 仅展示占位卡片），点击进入 Jellyfin 原生 UI：巨幕轮播、继续观看、媒体库卡片、各库最新影片，影片详情页支持唤起系统播放器播放（不做下载）。

**Architecture:** 纯 Dart 轻量 Jellyfin API 客户端（`http` 包，可注入 `MockClient` 测试）+ 原生 Flutter UI（服务器列表页、Jellyfin 深色影院首页、详情页）。凭据存储沿用 `smb_settings.dart` 模式（shared_preferences + flutter_secure_storage），密码与 Token 进安全存储。播放通过 `url_launcher` 调系统播放器打开 Jellyfin HLS 流地址。所有网络图片 `Image.network` 均带 `errorBuilder`。

**Tech Stack:** Flutter Material 3、`http`、`url_launcher`、`flutter_secure_storage`（已有）、`shared_preferences`（已有）。

## Global Constraints

- 界面文案全部使用简体中文（沿用现有风格，如「添加你的第一个服务器」「账号或密码错误」）。
- 代码不写注释（项目约定）。
- 依赖版本：`http: ^1.2.0`、`url_launcher: ^6.3.0`；dev 依赖 `url_launcher_platform_interface: ^2.3.0`。
- Flutter 命令使用 FVM：`export PATH="$PATH:/Users/alone/fvm/versions/stable/bin"`。
- 存储 key 前缀：非敏感字段 `server.`，Token 在安全存储中 key 为 `server.<id>.token`。
- Jellyfin 品牌色：`#00A4DC`（紫蓝色）、Emby 绿 `#52B54B`、SMB 琥珀 `#F59E0B`。
- Jellyfin 深色影院主题：背景 `#0B0B0F`（见 `jellyfin_theme.dart`）。
- 所有 Jellyfin 图片请求带 `api_key` 查询参数（Image.network 无法带 header）。
- 不做：Emby/SMB 实际功能、下载、播放进度上报、离线缓存、自动发现。

---
## 文件结构

| 文件 | 职责 |
|---|---|
| `lib/src/jellyfin_client.dart` | Jellyfin API 客户端 + 模型（JellyfinItem/View/Person/Exception） |
| `lib/src/server_settings.dart` | ServerType/ServerConfig/ServerSettingsStore + SecureKeyValueStore 抽象 |
| `lib/src/jellyfin_theme.dart` | 深色影院主题 + 占位组件（首页/详情页共用） |
| `lib/src/server_home_view.dart` | 服务器 Tab：列表、添加弹层（协议选择→表单→连接）、删除、重新连接 |
| `lib/src/jellyfin_home_view.dart` | Jellyfin 首页：巨幕轮播、继续观看、媒体库、最新添加 |
| `lib/src/jellyfin_detail_view.dart` | 影片详情页 + 播放 |
| `lib/src/app.dart` | 第 4 个 Tab 接入 |
| `test/jellyfin_client_test.dart` | 客户端单测（MockClient） |
| `test/server_settings_test.dart` | 存储单测（内存安全存储） |
| `test/server_home_view_test.dart` | 服务器列表/添加/删除 widget 测试 |
| `test/jellyfin_home_view_test.dart` | 首页 widget 测试 |
| `test/jellyfin_detail_view_test.dart` | 详情页 widget 测试 |
| `test/server_tab_test.dart` | HomeScreen 第 4 Tab 测试 |

---

### Task 1: 添加依赖

**Files:**
- Modify: `pubspec.yaml`

**Interfaces:** 无

- [ ] **Step 1: 编辑 pubspec.yaml**

在 `dependencies:` 中 `liquid_glass_easy: ^3.3.0` 之后添加两行：

```yaml
  http: ^1.2.0
  url_launcher: ^6.3.0
```

在 `dev_dependencies:` 中 `flutter_lints: ^6.0.0` 之后添加：

```yaml
  url_launcher_platform_interface: ^2.3.0
```

- [ ] **Step 2: 执行 pub get**

```bash
export PATH="$PATH:/Users/alone/fvm/versions/stable/bin"
flutter pub get
```

Expected: `Got dependencies!` 且无报错。

- [ ] **Step 3: Commit**

```bash
git add pubspec.yaml pubspec.lock
git commit -m "chore: add http and url_launcher dependencies"
```

---

### Task 2: Jellyfin API 客户端

**Files:**
- Create: `lib/src/jellyfin_client.dart`
- Test: `test/jellyfin_client_test.dart`

**Interfaces:**
- Produces:
  - `class JellyfinException implements Exception { const JellyfinException(this.message, {this.statusCode}); final String message; final int? statusCode; @override String toString() => message; }`
  - `class JellyfinItem { final String id; final String type; final String name; final String overview; final int? year; final int? runtimeMs; final double? communityRating; final List<String> genres; final String? primaryImageTag; final String? backdropImageTag; final double progress; final int? indexNumber; final int? parentIndexNumber; final String? seriesName; }`
  - `class JellyfinPerson { final String id; final String name; final String role; final String? imageTag; }`
  - `class JellyfinView { final String id; final String name; final String collectionType; final String? primaryImageTag; }`
  - `class JellyfinClient { JellyfinClient({http.Client? httpClient, String baseUrl = '', String accessToken = '', String userId = ''}); String baseUrl; String accessToken; String userId; void configure({String? baseUrl, String? accessToken, String? userId}); Future<void> login({required String baseUrl, required String username, required String password}); Future<List<JellyfinView>> fetchViews(); Future<List<JellyfinItem>> fetchResume(); Future<List<JellyfinItem>> fetchLatest({required String parentId, int limit = 12}); Future<int?> fetchViewCount(String parentId, {String? itemType}); Future<JellyfinItem> fetchItem(String id); Future<List<JellyfinPerson>> fetchPeople(String id); Future<String> fetchPlaybackUrl(String id); String imageUrl(String id, {String? tag, int? maxWidth}); String backdropUrl(String id, {String? tag, int? maxWidth}); }`
- Consumes: 无（仅依赖 `http` 包）

- [ ] **Step 1: 编写失败测试**

创建 `test/jellyfin_client_test.dart`：

```dart
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
```

- [ ] **Step 2: 运行测试验证失败**

```bash
export PATH="$PATH:/Users/alone/fvm/versions/stable/bin"
flutter test test/jellyfin_client_test.dart
```

Expected: FAIL —— 无法导入 `src/jellyfin_client.dart`（文件不存在）。

- [ ] **Step 3: 实现 `lib/src/jellyfin_client.dart`**

```dart
import 'dart:convert';

import 'package:http/http.dart' as http;

const jellyfinDeviceId = 'm3u8-downloader-2026';
const jellyfinDeviceName = 'M3U8 Downloader';
const jellyfinClientVersion = '1.3.2';

class JellyfinException implements Exception {
  const JellyfinException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class JellyfinItem {
  const JellyfinItem({
    required this.id,
    required this.type,
    required this.name,
    this.overview = '',
    this.year,
    this.runtimeMs,
    this.communityRating,
    this.genres = const [],
    this.primaryImageTag,
    this.backdropImageTag,
    this.progress = 0,
    this.indexNumber,
    this.parentIndexNumber,
    this.seriesName,
  });

  final String id;
  final String type;
  final String name;
  final String overview;
  final int? year;
  final int? runtimeMs;
  final double? communityRating;
  final List<String> genres;
  final String? primaryImageTag;
  final String? backdropImageTag;
  final double progress;
  final int? indexNumber;
  final int? parentIndexNumber;
  final String? seriesName;
}

class JellyfinPerson {
  const JellyfinPerson({
    required this.id,
    required this.name,
    required this.role,
    this.imageTag,
  });

  final String id;
  final String name;
  final String role;
  final String? imageTag;
}

class JellyfinView {
  const JellyfinView({
    required this.id,
    required this.name,
    required this.collectionType,
    this.primaryImageTag,
  });

  final String id;
  final String name;
  final String collectionType;
  final String? primaryImageTag;
}

class JellyfinClient {
  JellyfinClient({
    http.Client? httpClient,
    this.baseUrl = '',
    this.accessToken = '',
    this.userId = '',
  }) : _http = httpClient ?? http.Client();

  final http.Client _http;
  String baseUrl;
  String accessToken;
  String userId;

  void configure({String? baseUrl, String? accessToken, String? userId}) {
    if (baseUrl != null) this.baseUrl = baseUrl;
    if (accessToken != null) this.accessToken = accessToken;
    if (userId != null) this.userId = userId;
  }

  Map<String, String> get _authHeaders => {
    'Content-Type': 'application/json',
    'X-Emby-Token': accessToken,
    'X-Emby-Authorization':
        'MediaBrowser Client="$jellyfinDeviceName", '
        'Device="Phone", DeviceId="$jellyfinDeviceId", '
        'Version="$jellyfinClientVersion"',
  };

  String get _base => baseUrl.endsWith('/')
      ? baseUrl.substring(0, baseUrl.length - 1)
      : baseUrl;

  Uri _uri(String path, [Map<String, String>? query]) {
    final uri = Uri.parse('$_base$path');
    return uri.replace(
      queryParameters: {
        ...?query,
        if (accessToken.isNotEmpty) 'api_key': accessToken,
      },
    );
  }

  Future<void> login({
    required String baseUrl,
    required String username,
    required String password,
  }) async {
    final normalized = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    try {
      final response = await _http
          .post(
            Uri.parse('$normalized/Users/AuthenticateByName'),
            headers: _authHeaders,
            body: jsonEncode({'Username': username, 'Pw': password}),
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 401) {
        throw const JellyfinException('账号或密码错误', statusCode: 401);
      }
      if (response.statusCode != 200) {
        throw JellyfinException(
          '服务器返回错误（${response.statusCode}）',
          statusCode: response.statusCode,
        );
      }
      final data =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      final token = data['AccessToken'] as String?;
      final user = data['User'] as Map<String, dynamic>?;
      final id = user?['Id'] as String? ?? data['Id'] as String?;
      if (token == null || token.isEmpty || id == null || id.isEmpty) {
        throw const JellyfinException('服务器返回了无法识别的登录信息');
      }
      this.baseUrl = normalized;
      accessToken = token;
      userId = id;
    } on JellyfinException {
      rethrow;
    } catch (_) {
      throw const JellyfinException('无法连接服务器，请检查地址和网络');
    }
  }

  Future<dynamic> _getJson(String path, [Map<String, String>? query]) async {
    try {
      final response = await _http
          .get(_uri(path, query))
          .timeout(const Duration(seconds: 15));
      if (response.statusCode == 401) {
        throw const JellyfinException('登录已过期，请重新连接', statusCode: 401);
      }
      if (response.statusCode != 200) {
        throw JellyfinException(
          '服务器返回错误（${response.statusCode}）',
          statusCode: response.statusCode,
        );
      }
      return jsonDecode(utf8.decode(response.bodyBytes));
    } on JellyfinException {
      rethrow;
    } catch (_) {
      throw const JellyfinException('无法连接服务器，请检查网络');
    }
  }

  Future<List<JellyfinView>> fetchViews() async {
    final data = await _getJson('/Users/$userId/Views') as Map<String, dynamic>;
    return [
      for (final item in data['Items'] as List<dynamic>? ?? const [])
        if (item is Map<String, dynamic>)
          JellyfinView(
            id: item['Id'] as String? ?? '',
            name: item['Name'] as String? ?? '',
            collectionType: item['CollectionType'] as String? ?? 'mixed',
            primaryImageTag:
                (item['ImageTags'] as Map<String, dynamic>?)?['Primary']
                    as String?,
          ),
    ];
  }

  Future<List<JellyfinItem>> fetchResume() async {
    final data =
        await _getJson('/Users/$userId/Items/Resume') as Map<String, dynamic>;
    return _parseItems(data['Items']);
  }

  Future<List<JellyfinItem>> fetchLatest({
    required String parentId,
    int limit = 12,
  }) async {
    final data = await _getJson(
      '/Users/$userId/Items/Latest',
      {'ParentId': parentId, 'Limit': '$limit'},
    );
    return _parseItems(data);
  }

  Future<int?> fetchViewCount(String parentId, {String? itemType}) async {
    final data = await _getJson('/Users/$userId/Items', {
      'ParentId': parentId,
      'Recursive': 'true',
      'Limit': '0',
      if (itemType != null) 'IncludeItemTypes': itemType,
    }) as Map<String, dynamic>;
    return data['TotalRecordCount'] as int?;
  }

  Future<JellyfinItem> fetchItem(String id) async {
    final data = await _getJson('/Users/$userId/Items/$id')
        as Map<String, dynamic>;
    return _parseItem(data);
  }

  Future<List<JellyfinPerson>> fetchPeople(String id) async {
    final data = await _getJson('/Items/$id/People') as List<dynamic>;
    return [
      for (final entry in data)
        if (entry is Map<String, dynamic>)
          JellyfinPerson(
            id: entry['Id'] as String? ?? '',
            name: entry['Name'] as String? ?? '',
            role: entry['Role'] as String? ?? entry['Type'] as String? ?? '',
            imageTag: entry['PrimaryImageTag'] as String?,
          ),
    ];
  }

  Future<String> fetchPlaybackUrl(String id) async {
    final http.Response response;
    try {
      response = await _http
          .post(
            _uri('/Items/$id/PlaybackInfo', {'UserId': userId}),
            headers: _authHeaders,
            body: jsonEncode({
              'UserId': userId,
              'DeviceId': jellyfinDeviceId,
              'AutoOpenLiveStream': true,
              'MediaSourceId': '',
            }),
          )
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      throw const JellyfinException('无法获取播放地址，请检查网络');
    }
    if (response.statusCode == 401) {
      throw const JellyfinException('登录已过期，请重新连接', statusCode: 401);
    }
    if (response.statusCode != 200) {
      throw JellyfinException('无法获取播放地址（${response.statusCode}）');
    }
    final data =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    final sources = data['MediaSources'] as List<dynamic>? ?? const [];
    if (sources.isEmpty) {
      throw const JellyfinException('该影片没有可播放的媒体源');
    }
    final mediaSourceId = (sources.first as Map<String, dynamic>)['Id'];
    if (mediaSourceId is! String || mediaSourceId.isEmpty) {
      throw const JellyfinException('该影片没有可播放的媒体源');
    }
    return '$_base/videos/$id/master.m3u8'
        '?api_key=$accessToken&MediaSourceId=$mediaSourceId&UserId=$userId';
  }

  String imageUrl(String id, {String? tag, int? maxWidth}) => _imageUrl(
    '/Items/$id/Images/Primary',
    tag,
    maxWidth,
  );

  String backdropUrl(String id, {String? tag, int? maxWidth}) => _imageUrl(
    '/Items/$id/Images/Backdrop/0',
    tag,
    maxWidth,
  );

  String _imageUrl(String path, String? tag, int? maxWidth) {
    final params = <String, String>{
      'api_key': accessToken,
      if (tag != null && tag.isNotEmpty) 'tag': tag,
      if (maxWidth != null) 'maxWidth': '$maxWidth',
    };
    return '$_base$path?${Uri(queryParameters: params).query}';
  }

  List<JellyfinItem> _parseItems(dynamic raw) {
    return [
      for (final item in raw as List<dynamic>? ?? const [])
        if (item is Map<String, dynamic>) _parseItem(item),
    ];
  }

  JellyfinItem _parseItem(Map<String, dynamic> data) {
    final imageTags = data['ImageTags'] as Map<String, dynamic>? ?? const {};
    final backdrops = data['BackdropImageTags'] as List<dynamic>? ?? const [];
    final userData = data['UserData'] as Map<String, dynamic>? ?? const {};
    final runTimeTicks = data['RunTimeTicks'] as int?;
    final playbackTicks = userData['PlaybackPositionTicks'] as int? ?? 0;
    final playedPercent = userData['PlayedPercentage'] as num?;
    final progress = playedPercent != null
        ? playedPercent.toDouble() / 100
        : (runTimeTicks != null &&
              runTimeTicks > 0 &&
              playbackTicks > 0)
        ? playbackTicks / runTimeTicks
        : 0;
    return JellyfinItem(
      id: data['Id'] as String? ?? '',
      type: data['Type'] as String? ?? '',
      name: data['Name'] as String? ?? '',
      overview: data['Overview'] as String? ?? '',
      year: data['ProductionYear'] as int?,
      runtimeMs: runTimeTicks != null ? runTimeTicks ~/ 10000 : null,
      communityRating: (data['CommunityRating'] as num?)?.toDouble(),
      genres: [
        for (final genre in data['Genres'] as List<dynamic>? ?? const [])
          genre as String,
      ],
      primaryImageTag: imageTags['Primary'] as String?,
      backdropImageTag: backdrops.isNotEmpty
          ? backdrops.first as String?
          : null,
      progress: progress.clamp(0.0, 1.0).toDouble(),
      indexNumber: data['IndexNumber'] as int?,
      parentIndexNumber: data['ParentIndexNumber'] as int?,
      seriesName: data['SeriesName'] as String?,
    );
  }
}
```

- [ ] **Step 4: 运行测试验证通过**

```bash
export PATH="$PATH:/Users/alone/fvm/versions/stable/bin"
flutter test test/jellyfin_client_test.dart
```

Expected: `All tests passed!`（13 个测试）。

- [ ] **Step 5: Commit**

```bash
git add lib/src/jellyfin_client.dart test/jellyfin_client_test.dart
git commit -m "feat: add jellyfin api client"
```

---

### Task 3: 服务器配置存储

**Files:**
- Create: `lib/src/server_settings.dart`
- Test: `test/server_settings_test.dart`

**Interfaces:**
- Produces:
  - `enum ServerType { jellyfin, emby, smb }`
  - `class ServerConfig { const ServerConfig({required String id, required ServerType type, String name = '', String url = '', String username = '', String userId = '', String accessToken = '', required DateTime createdAt}); final String id; final ServerType type; final String name; final String url; final String username; final String userId; final String accessToken; final DateTime createdAt; bool get hasToken; ServerConfig copyWith({String? name, String? url, String? username, String? userId, String? accessToken}); }`
  - `abstract class SecureKeyValueStore { Future<String?> read(String key); Future<void> write(String key, String value); }`
  - `class ServerSettingsStore { ServerSettingsStore({SecureKeyValueStore? secureStorage}); static final ServerSettingsStore instance; Future<List<ServerConfig>> loadAll(); Future<void> save(ServerConfig config); Future<void> remove(String id); }`
- Consumes: 无（依赖 flutter_secure_storage、shared_preferences）

- [ ] **Step 1: 编写失败测试**

创建 `test/server_settings_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:m3u8downloader/src/server_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MemorySecureStore implements SecureKeyValueStore {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

class _FailingSecureStore implements SecureKeyValueStore {
  @override
  Future<String?> read(String key) async => throw Exception('unavailable');

  @override
  Future<void> write(String key, String value) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('save, load and remove roundtrip', () async {
    SharedPreferences.setMockInitialValues({});
    final secure = _MemorySecureStore();
    final store = ServerSettingsStore(secureStorage: secure);

    expect(await store.loadAll(), isEmpty);

    final config = ServerConfig(
      id: 'srv-1',
      type: ServerType.jellyfin,
      name: '家庭影院',
      url: 'http://192.168.1.10:8096',
      username: 'alice',
      userId: 'u1',
      accessToken: 'token-abc',
      createdAt: DateTime.parse('2026-08-02T10:00:00'),
    );
    await store.save(config);

    final loaded = await store.loadAll();
    expect(loaded, hasLength(1));
    expect(loaded.first.id, 'srv-1');
    expect(loaded.first.type, ServerType.jellyfin);
    expect(loaded.first.name, '家庭影院');
    expect(loaded.first.accessToken, 'token-abc');
    expect(secure.values['server.srv-1.token'], 'token-abc');

    await store.save(config.copyWith(accessToken: ''));
    expect((await store.loadAll()).single.accessToken, '');
    expect(secure.values['server.srv-1.token'], '');

    await store.remove('srv-1');
    expect(await store.loadAll(), isEmpty);
  });

  test('multiple servers sort by createdAt descending', () async {
    SharedPreferences.setMockInitialValues({});
    final store = ServerSettingsStore(secureStorage: _MemorySecureStore());
    await store.save(
      ServerConfig(
        id: 'a',
        type: ServerType.jellyfin,
        createdAt: DateTime.parse('2026-08-01T10:00:00'),
      ),
    );
    await store.save(
      ServerConfig(
        id: 'b',
        type: ServerType.jellyfin,
        createdAt: DateTime.parse('2026-08-02T10:00:00'),
      ),
    );
    final loaded = await store.loadAll();
    expect(loaded.map((c) => c.id).toList(), ['b', 'a']);
  });

  test('secure storage read failure is tolerated', () async {
    SharedPreferences.setMockInitialValues({});
    final store = ServerSettingsStore(secureStorage: _FailingSecureStore());
    await store.save(
      ServerConfig(
        id: 'srv-2',
        type: ServerType.jellyfin,
        accessToken: 'tok',
        createdAt: DateTime.parse('2026-08-02T10:00:00'),
      ),
    );
    final loaded = await store.loadAll();
    expect(loaded.single.id, 'srv-2');
    expect(loaded.single.accessToken, '');
  });
}
```

- [ ] **Step 2: 运行测试验证失败**

```bash
export PATH="$PATH:/Users/alone/fvm/versions/stable/bin"
flutter test test/server_settings_test.dart
```

Expected: FAIL —— 无法导入 `src/server_settings.dart`。

- [ ] **Step 3: 实现 `lib/src/server_settings.dart`**

```dart
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ServerType { jellyfin, emby, smb }

class ServerConfig {
  const ServerConfig({
    required this.id,
    required this.type,
    this.name = '',
    this.url = '',
    this.username = '',
    this.userId = '',
    this.accessToken = '',
    required this.createdAt,
  });

  final String id;
  final ServerType type;
  final String name;
  final String url;
  final String username;
  final String userId;
  final String accessToken;
  final DateTime createdAt;

  bool get hasToken => accessToken.isNotEmpty;

  ServerConfig copyWith({
    String? name,
    String? url,
    String? username,
    String? userId,
    String? accessToken,
  }) => ServerConfig(
    id: id,
    type: type,
    name: name ?? this.name,
    url: url ?? this.url,
    username: username ?? this.username,
    userId: userId ?? this.userId,
    accessToken: accessToken ?? this.accessToken,
    createdAt: createdAt,
  );
}

abstract class SecureKeyValueStore {
  Future<String?> read(String key);

  Future<void> write(String key, String value);
}

class FlutterSecureStorageAdapter implements SecureKeyValueStore {
  FlutterSecureStorageAdapter(this._storage);

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);
}

class ServerSettingsStore {
  ServerSettingsStore({SecureKeyValueStore? secureStorage})
    : _secureStorage =
          secureStorage ?? FlutterSecureStorageAdapter(const FlutterSecureStorage());

  static final ServerSettingsStore instance = ServerSettingsStore();

  final SecureKeyValueStore _secureStorage;
  static const _idsKey = 'server.ids';

  String _typeKey(String id) => 'server.$id.type';
  String _nameKey(String id) => 'server.$id.name';
  String _urlKey(String id) => 'server.$id.url';
  String _usernameKey(String id) => 'server.$id.username';
  String _userIdKey(String id) => 'server.$id.userId';
  String _createdAtKey(String id) => 'server.$id.createdAt';
  String _tokenKey(String id) => 'server.$id.token';

  Future<List<ServerConfig>> loadAll() async {
    final preferences = await SharedPreferences.getInstance();
    final ids = preferences.getStringList(_idsKey) ?? const [];
    final configs = <ServerConfig>[];
    for (final id in ids) {
      final type = preferences.getString(_typeKey(id));
      if (type == null) continue;
      String? token;
      try {
        token = await _secureStorage.read(_tokenKey(id));
      } catch (_) {
        token = null;
      }
      configs.add(
        ServerConfig(
          id: id,
          type: ServerType.values.firstWhere(
            (t) => t.name == type,
            orElse: () => ServerType.jellyfin,
          ),
          name: preferences.getString(_nameKey(id)) ?? '',
          url: preferences.getString(_urlKey(id)) ?? '',
          username: preferences.getString(_usernameKey(id)) ?? '',
          userId: preferences.getString(_userIdKey(id)) ?? '',
          accessToken: token ?? '',
          createdAt:
              DateTime.tryParse(preferences.getString(_createdAtKey(id)) ?? '') ??
              DateTime.fromMillisecondsSinceEpoch(0),
        ),
      );
    }
    configs.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return configs;
  }

  Future<void> save(ServerConfig config) async {
    final preferences = await SharedPreferences.getInstance();
    final ids = preferences.getStringList(_idsKey) ?? <String>[];
    if (!ids.contains(config.id)) ids.add(config.id);
    await Future.wait([
      preferences.setStringList(_idsKey, ids),
      preferences.setString(_typeKey(config.id), config.type.name),
      preferences.setString(_nameKey(config.id), config.name),
      preferences.setString(_urlKey(config.id), config.url),
      preferences.setString(_usernameKey(config.id), config.username),
      preferences.setString(_userIdKey(config.id), config.userId),
      preferences.setString(
        _createdAtKey(config.id),
        config.createdAt.toIso8601String(),
      ),
      _secureStorage.write(_tokenKey(config.id), config.accessToken),
    ]);
  }

  Future<void> remove(String id) async {
    final preferences = await SharedPreferences.getInstance();
    final ids = preferences.getStringList(_idsKey) ?? <String>[];
    ids.remove(id);
    await Future.wait([
      preferences.setStringList(_idsKey, ids),
      preferences.remove(_typeKey(id)),
      preferences.remove(_nameKey(id)),
      preferences.remove(_urlKey(id)),
      preferences.remove(_usernameKey(id)),
      preferences.remove(_userIdKey(id)),
      preferences.remove(_createdAtKey(id)),
      _secureStorage.write(_tokenKey(id), ''),
    ]);
  }
}
```

- [ ] **Step 4: 运行测试验证通过**

```bash
export PATH="$PATH:/Users/alone/fvm/versions/stable/bin"
flutter test test/server_settings_test.dart
```

Expected: `All tests passed!`（3 个测试）。

- [ ] **Step 5: Commit**

```bash
git add lib/src/server_settings.dart test/server_settings_test.dart
git commit -m "feat: add server settings store"
```

---

### Task 4: 服务器 Tab 根视图（列表 + 添加/删除/重新连接）

**Files:**
- Create: `lib/src/server_home_view.dart`
- Test: `test/server_home_view_test.dart`

**Interfaces:**
- Consumes:
  - `JellyfinClient`（Task 2）：`JellyfinClient({http.Client? httpClient, String baseUrl, String accessToken, String userId})`、`void configure({String? baseUrl, String? accessToken, String? userId})`、`Future<void> login({required String baseUrl, required String username, required String password})`、`String baseUrl`、`String accessToken`、`String userId`
  - `ServerSettingsStore` / `ServerConfig` / `ServerType`（Task 3）
  - `JellyfinHomeView(config: ..., client: ...)`（Task 5，本任务最后一步才使用；先以最终签名为准）：
    - `const JellyfinHomeView({super.key, required ServerConfig config, required JellyfinClient client})`
- Produces:
  - `class ServerHomeView extends StatefulWidget { const ServerHomeView({super.key, this.clientFactory, this.store}); final JellyfinClient Function()? clientFactory; final ServerSettingsStore? store; }`
  - 行为契约：点击有 Token 的服务器卡片 → push `JellyfinHomeView`；push 返回 `true` 表示 Token 过期 → 保存 `config.copyWith(accessToken: '')` 并提示「登录已过期，请重新连接」。点击无 Token 的卡片 → 打开添加弹层（预填表单）重新连接。添加成功 → 保存并直接进入 Jellyfin 首页。

- [ ] **Step 1: 编写失败测试**

创建 `test/server_home_view_test.dart`：

```dart
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:m3u8downloader/src/jellyfin_client.dart';
import 'package:m3u8downloader/src/server_home_view.dart';
import 'package:m3u8downloader/src/server_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _jsonHeaders = {'content-type': 'application/json'};

class _MemorySecureStore implements SecureKeyValueStore {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

ServerSettingsStore _store() =>
    ServerSettingsStore(secureStorage: _MemorySecureStore());

JellyfinClient _loginClient() => JellyfinClient(
  httpClient: MockClient((request) async {
    if (request.url.path.endsWith('/Users/AuthenticateByName')) {
      return http.Response(
        jsonEncode({'User': {'Id': 'u1'}, 'AccessToken': 'tok'}),
        200,
        headers: _jsonHeaders,
      );
    }
    if (request.url.path.endsWith('/Views')) {
      return http.Response('{"Items": []}', 200, headers: _jsonHeaders);
    }
    if (request.url.path.endsWith('/Items/Resume')) {
      return http.Response('{"Items": []}', 200, headers: _jsonHeaders);
    }
    return http.Response('[]', 200, headers: _jsonHeaders);
  }),
);

Future<void> _pumpServerView(
  WidgetTester tester, {
  required ServerSettingsStore store,
  JellyfinClient Function()? clientFactory,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ServerHomeView(store: store, clientFactory: clientFactory),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('empty state shows guide and add sheet with protocol cards', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await _pumpServerView(tester, store: _store());

    expect(find.text('添加你的第一个服务器'), findsOneWidget);

    await tester.tap(find.text('添加服务器'));
    await tester.pumpAndSettle();

    expect(find.text('选择服务器类型'), findsOneWidget);
    expect(find.text('Jellyfin'), findsOneWidget);
    expect(find.text('Emby'), findsOneWidget);
    expect(find.text('SMB'), findsOneWidget);
    expect(find.text('即将支持'), findsNWidgets(2));
  });

  testWidgets('connect flow saves server and enters jellyfin home', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final store = _store();
    await _pumpServerView(tester, store: store, clientFactory: _loginClient);

    await tester.tap(find.text('添加服务器'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Jellyfin'));
    await tester.pumpAndSettle();

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), '家庭影院');
    await tester.enterText(fields.at(1), 'http://192.168.1.10:8096');
    await tester.enterText(fields.at(2), 'alice');
    await tester.enterText(fields.at(3), 'secret');
    await tester.tap(find.text('测试并连接'));
    await tester.pumpAndSettle();

    expect(find.text('已连接 家庭影院'), findsOneWidget);
    final saved = await store.loadAll();
    expect(saved, hasLength(1));
    expect(saved.first.name, '家庭影院');
    expect(saved.first.accessToken, 'tok');
    expect(saved.first.userId, 'u1');
  });

  testWidgets('saved server card opens, delete removes it', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = _store();
    await store.save(
      ServerConfig(
        id: 'srv-1',
        type: ServerType.jellyfin,
        name: '家庭影院',
        url: 'http://192.168.1.10:8096',
        accessToken: 'tok',
        createdAt: DateTime.parse('2026-08-02T10:00:00'),
      ),
    );
    await _pumpServerView(tester, store: store);

    expect(find.text('家庭影院'), findsOneWidget);
    expect(find.text('192.168.1.10:8096'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    expect(find.text('删除服务器「家庭影院」？'), findsOneWidget);
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();

    expect(find.text('添加你的第一个服务器'), findsOneWidget);
    expect(await store.loadAll(), isEmpty);
  });

  testWidgets('server without token shows reconnect badge', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = _store();
    await store.save(
      ServerConfig(
        id: 'srv-2',
        type: ServerType.jellyfin,
        name: '旧服务器',
        url: 'http://192.168.1.10:8096',
        createdAt: DateTime.parse('2026-08-02T10:00:00'),
      ),
    );
    await _pumpServerView(tester, store: store);

    expect(find.text('需重新连接'), findsOneWidget);

    await tester.tap(find.text('旧服务器'));
    await tester.pumpAndSettle();
    expect(find.text('连接 Jellyfin'), findsOneWidget);
    expect(find.text('192.168.1.10:8096'), findsOneWidget);
  });
}
```

- [ ] **Step 2: 运行测试验证失败**

```bash
export PATH="$PATH:/Users/alone/fvm/versions/stable/bin"
flutter test test/server_home_view_test.dart
```

Expected: FAIL —— 无法导入 `src/server_home_view.dart`。

- [ ] **Step 3: 实现 `lib/src/server_home_view.dart`**

```dart
import 'package:flutter/material.dart';

import 'glass_surface.dart';
import 'jellyfin_client.dart';
import 'jellyfin_home_view.dart';
import 'server_settings.dart';

class ServerHomeView extends StatefulWidget {
  const ServerHomeView({super.key, this.clientFactory, this.store});

  final JellyfinClient Function()? clientFactory;
  final ServerSettingsStore? store;

  @override
  State<ServerHomeView> createState() => _ServerHomeViewState();
}

class _ServerHomeViewState extends State<ServerHomeView> {
  late final ServerSettingsStore _store;
  late final JellyfinClient Function() _clientFactory;
  List<ServerConfig> _servers = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _store = widget.store ?? ServerSettingsStore.instance;
    _clientFactory = widget.clientFactory ?? JellyfinClient.new;
    _reload();
  }

  Future<void> _reload() async {
    final servers = await _store.loadAll();
    if (!mounted) return;
    setState(() {
      _servers = servers;
      _loading = false;
    });
  }

  Future<void> _openSheet({ServerConfig? initial}) async {
    final result = await showModalBottomSheet<ServerConfig>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddServerSheet(
        clientFactory: _clientFactory,
        initial: initial,
      ),
    );
    if (result == null || !mounted) return;
    await _store.save(result);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('已连接 ${result.name}')));
    await _reload();
    if (!mounted) return;
    final client = _clientFactory()
      ..configure(
        baseUrl: result.url,
        accessToken: result.accessToken,
        userId: result.userId,
      );
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => JellyfinHomeView(config: result, client: client),
      ),
    );
    await _reload();
  }

  Future<void> _openServer(ServerConfig server) async {
    if (!server.hasToken) {
      await _openSheet(initial: server);
      return;
    }
    final client = _clientFactory()
      ..configure(
        baseUrl: server.url,
        accessToken: server.accessToken,
        userId: server.userId,
      );
    final tokenExpired = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => JellyfinHomeView(config: server, client: client),
      ),
    );
    if (tokenExpired == true && mounted) {
      await _store.save(server.copyWith(accessToken: ''));
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('登录已过期，请重新连接')));
    }
    await _reload();
  }

  Future<void> _deleteServer(ServerConfig server) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('删除服务器「${server.name}」？'),
        content: const Text('删除后需要重新登录才能连接。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _store.remove(server.id);
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 118),
          children: [
            _ServerHeader(onAdd: () => _openSheet()),
            const SizedBox(height: 14),
            if (_loading)
              const Padding(
                padding: EdgeInsets.only(top: 120),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_servers.isEmpty)
              _EmptyServers(onAdd: () => _openSheet())
            else
              for (final server in _servers) ...[
                _ServerCard(
                  server: server,
                  onTap: () => _openServer(server),
                  onDelete: () => _deleteServer(server),
                ),
                const SizedBox(height: 12),
              ],
          ],
        ),
      ),
    );
  }
}

class _ServerHeader extends StatelessWidget {
  const _ServerHeader({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '服务器',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '连接 Jellyfin、Emby 或 SMB 媒体库',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        FilledButton.tonalIcon(
          onPressed: onAdd,
          icon: const Icon(Icons.add_rounded),
          label: const Text('添加'),
        ),
      ],
    );
  }
}

class _ServerCard extends StatelessWidget {
  const _ServerCard({
    required this.server,
    required this.onTap,
    required this.onDelete,
  });

  final ServerConfig server;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AppSurface(
      borderRadius: 22,
      elevated: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 8, 16),
          child: Row(
            children: [
              _ProtocolBadge(type: server.type),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            server.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        if (!server.hasToken) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: colors.tertiaryContainer,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              '需重新连接',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: colors.onTertiaryContainer,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      server.url.replaceAll(RegExp(r'^https?://'), ''),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: '删除',
                onPressed: onDelete,
                icon: Icon(Icons.delete_outline, color: colors.outline),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProtocolBadge extends StatelessWidget {
  const _ProtocolBadge({required this.type});

  final ServerType type;

  @override
  Widget build(BuildContext context) {
    final (color, icon) = switch (type) {
      ServerType.jellyfin => (const Color(0xFF00A4DC), Icons.play_arrow_rounded),
      ServerType.emby => (const Color(0xFF52B54B), Icons.live_tv_rounded),
      ServerType.smb => (const Color(0xFFF59E0B), Icons.folder_rounded),
    };
    return Container(
      width: 50,
      height: 50,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.35),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Icon(icon, color: Colors.white, size: 27),
    );
  }
}

class _EmptyServers extends StatelessWidget {
  const _EmptyServers({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        children: [
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              color: colors.primaryContainer,
              borderRadius: BorderRadius.circular(28),
            ),
            child: Icon(Icons.dns_outlined, size: 40, color: colors.onPrimaryContainer),
          ),
          const SizedBox(height: 18),
          Text(
            '添加你的第一个服务器',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '支持 Jellyfin、Emby 和 SMB 协议',
            style: TextStyle(color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add_rounded),
            label: const Text('添加服务器'),
          ),
        ],
      ),
    );
  }
}

class _AddServerSheet extends StatefulWidget {
  const _AddServerSheet({required this.clientFactory, this.initial});

  final JellyfinClient Function() clientFactory;
  final ServerConfig? initial;

  @override
  State<_AddServerSheet> createState() => _AddServerSheetState();
}

class _AddServerSheetState extends State<_AddServerSheet> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _url = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  ServerType? _type;
  bool _connecting = false;
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    if (initial != null) {
      _type = initial.type;
      _name.text = initial.name;
      _url.text = initial.url;
      _username.text = initial.username;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _connecting = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final client = widget.clientFactory();
      await client.login(
        baseUrl: _url.text.trim(),
        username: _username.text.trim(),
        password: _password.text,
      );
      if (!mounted) return;
      final id = widget.initial?.id ??
          DateTime.now().millisecondsSinceEpoch.toString();
      final name = _name.text.trim().isEmpty
          ? _hostOf(_url.text.trim())
          : _name.text.trim();
      Navigator.pop(
        context,
        ServerConfig(
          id: id,
          type: _type ?? ServerType.jellyfin,
          name: name,
          url: client.baseUrl,
          username: _username.text.trim(),
          userId: client.userId,
          accessToken: client.accessToken,
          createdAt: widget.initial?.createdAt ?? DateTime.now(),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            error is JellyfinException ? error.message : '连接失败：$error',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  String _hostOf(String url) {
    final uri = Uri.tryParse(url);
    if (uri != null && uri.host.isNotEmpty) return uri.host;
    return url.replaceAll(RegExp(r'^https?://'), '');
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: AppSurface(
        borderRadius: 28,
        child: SafeArea(
          top: false,
          child: _type == null ? _buildTypePicker() : _buildForm(),
        ),
      ),
    );
  }

  Widget _buildTypePicker() {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: colors.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '选择服务器类型',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 16),
          for (final type in ServerType.values) ...[
            _ProtocolOption(
              type: type,
              enabled: type == ServerType.jellyfin,
              onTap: () => setState(() => _type = type),
            ),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }

  Widget _buildForm() {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                _ProtocolBadge(type: _type ?? ServerType.jellyfin),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '连接 Jellyfin',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: '返回选择类型',
                  onPressed: () => setState(() => _type = null),
                  icon: const Icon(Icons.arrow_back_rounded),
                ),
              ],
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: '名称（可选）',
                hintText: '家庭影院',
                prefixIcon: Icon(Icons.badge_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _url,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: '服务器地址',
                hintText: 'http://192.168.1.10:8096',
                prefixIcon: Icon(Icons.dns_outlined),
              ),
              validator: (value) {
                final v = value?.trim() ?? '';
                if (v.isEmpty) return '不能为空';
                if (!v.startsWith('http://') && !v.startsWith('https://')) {
                  return '请以 http:// 或 https:// 开头';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _username,
              decoration: const InputDecoration(
                labelText: '用户名',
                prefixIcon: Icon(Icons.person_outline_rounded),
              ),
              validator: (value) =>
                  value == null || value.trim().isEmpty ? '不能为空' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _password,
              obscureText: _obscure,
              decoration: InputDecoration(
                labelText: '密码',
                prefixIcon: const Icon(Icons.key_outlined),
                suffixIcon: IconButton(
                  tooltip: _obscure ? '显示密码' : '隐藏密码',
                  onPressed: () => setState(() => _obscure = !_obscure),
                  icon: Icon(
                    _obscure
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _connecting ? null : _connect,
              icon: _connecting
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.network_check_rounded),
              label: Text(_connecting ? '正在连接…' : '测试并连接'),
            ),
            const SizedBox(height: 6),
            Text(
              '密码仅保存在设备安全存储中',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProtocolOption extends StatelessWidget {
  const _ProtocolOption({
    required this.type,
    required this.enabled,
    required this.onTap,
  });

  final ServerType type;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final name = switch (type) {
      ServerType.jellyfin => 'Jellyfin',
      ServerType.emby => 'Emby',
      ServerType.smb => 'SMB',
    };
    final description = switch (type) {
      ServerType.jellyfin => '开源的媒体服务器，浏览电影、剧集与音乐',
      ServerType.emby => '商业媒体服务器，功能与 Jellyfin 相近',
      ServerType.smb => '局域网文件共享，浏览 NAS 上的视频文件',
    };
    return Material(
      color: enabled ? colors.surfaceContainerLow : colors.surfaceContainerHighest.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            children: [
              _ProtocolBadge(type: type),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      description,
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (!enabled)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '即将支持',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                )
              else
                Icon(Icons.chevron_right_rounded, color: colors.outline),
            ],
          ),
        ),
      ),
    );
  }
}
```

注意：本任务中 `jellyfin_home_view.dart` 尚未创建，`flutter analyze` 会报 `import 'jellyfin_home_view.dart'` 找不到。Step 4 只运行 `server_home_view_test.dart`（该测试在连接成功后会 push JellyfinHomeView——无法编译）。**因此先创建占位文件**：

- [ ] **Step 3b: 创建 `lib/src/jellyfin_home_view.dart` 占位**

```dart
import 'package:flutter/material.dart';

import 'jellyfin_client.dart';
import 'server_settings.dart';

class JellyfinHomeView extends StatefulWidget {
  const JellyfinHomeView({super.key, required this.config, required this.client});

  final ServerConfig config;
  final JellyfinClient client;

  @override
  State<JellyfinHomeView> createState() => _JellyfinHomeViewState();
}

class _JellyfinHomeViewState extends State<JellyfinHomeView> {
  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: Text('加载中…')));
  }
}
```

- [ ] **Step 4: 运行测试验证通过**

```bash
export PATH="$PATH:/Users/alone/fvm/versions/stable/bin"
flutter test test/server_home_view_test.dart
```

Expected: `All tests passed!`（4 个测试）。

- [ ] **Step 5: Commit**

```bash
git add lib/src/server_home_view.dart lib/src/jellyfin_home_view.dart test/server_home_view_test.dart
git commit -m "feat: add server home view with jellyfin connect flow"
```

---

### Task 5: Jellyfin 首页（巨幕轮播 + 继续观看 + 媒体库 + 最新添加）

**Files:**
- Create: `lib/src/jellyfin_theme.dart`
- Rewrite: `lib/src/jellyfin_home_view.dart`（替换 Task 4 的占位实现）
- Test: `test/jellyfin_home_view_test.dart`

**Interfaces:**
- Consumes:
  - `JellyfinClient`（Task 2）：`fetchViews()`、`fetchResume()`、`fetchLatest({required String parentId, int limit})`、`fetchViewCount(String parentId, {String? itemType})`、`fetchPlaybackUrl(String id)`、`imageUrl(id, {tag, maxWidth})`、`backdropUrl(id, {tag, maxWidth})`、`JellyfinException.statusCode`
  - `JellyfinItem` / `JellyfinView`（Task 2）
  - `ServerConfig`（Task 3）
  - `JellyfinDetailView({required String itemId, required JellyfinClient client})`（Task 6，本任务最后一步使用；先以最终签名为准）
- Produces:
  - `class JellyfinHomeView extends StatefulWidget { const JellyfinHomeView({super.key, required this.config, required this.client}); final ServerConfig config; final JellyfinClient client; }`
  - 行为契约：加载失败且 `statusCode == 401` 时 `Navigator.pop(context, true)`（Token 过期）；详情页返回 `'expired'` 时同样 `Navigator.pop(context, true)`。点击继续观看卡片直接调 `_play`。
  - `lib/src/jellyfin_theme.dart`：`const jellyfinBackground = Color(0xFF0B0B0F);`、`const jellyfinAccent = Color(0xFF00A4DC);`、`ThemeData jellyfinCinemaTheme()`、`class JellyfinPlaceholder extends StatelessWidget { const JellyfinPlaceholder({super.key, this.icon = Icons.movie_outlined}); final IconData icon; }`

- [ ] **Step 1: 编写失败测试**

创建 `test/jellyfin_home_view_test.dart`：

```dart
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

    expect(find.text('加载失败，请重试'), findsOneWidget);

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
}
```

- [ ] **Step 2: 运行测试验证失败**

```bash
export PATH="$PATH:/Users/alone/fvm/versions/stable/bin"
flutter test test/jellyfin_home_view_test.dart
```

Expected: FAIL —— 占位实现没有轮播/分区文案。

- [ ] **Step 3: 创建 `lib/src/jellyfin_theme.dart`**

```dart
import 'package:flutter/material.dart';

const jellyfinBackground = Color(0xFF0B0B0F);
const jellyfinAccent = Color(0xFF00A4DC);

ThemeData jellyfinCinemaTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: jellyfinAccent,
    brightness: Brightness.dark,
  );
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: jellyfinBackground,
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
  );
}

class JellyfinPlaceholder extends StatelessWidget {
  const JellyfinPlaceholder({super.key, this.icon = Icons.movie_outlined});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF16161C),
      child: Center(child: Icon(icon, size: 44, color: Colors.white24)),
    );
  }
}
```

- [ ] **Step 4: 重写 `lib/src/jellyfin_home_view.dart`**

```dart
import 'dart:async';

import 'package:flutter/material.dart';

import 'jellyfin_client.dart';
import 'jellyfin_detail_view.dart';
import 'jellyfin_theme.dart';
import 'server_settings.dart';

class JellyfinHomeView extends StatefulWidget {
  const JellyfinHomeView({
    super.key,
    required this.config,
    required this.client,
  });

  final ServerConfig config;
  final JellyfinClient client;

  @override
  State<JellyfinHomeView> createState() => _JellyfinHomeViewState();
}

class _JellyfinHomeViewState extends State<JellyfinHomeView> {
  bool _loading = true;
  String? _error;
  List<JellyfinView> _views = [];
  List<JellyfinItem> _resume = [];
  Map<String, List<JellyfinItem>> _latest = {};
  Map<String, int?> _viewCounts = {};
  List<JellyfinItem> _carousel = [];

  final _carouselController = PageController();
  Timer? _carouselTimer;
  bool _carouselDragging = false;
  int _carouselIndex = 0;

  JellyfinClient get _client => widget.client;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _carouselTimer?.cancel();
    _carouselController.dispose();
    super.dispose();
  }

  Future<void> _load({bool refresh = false}) async {
    if (!refresh) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final views = await _client.fetchViews();
      final results = await Future.wait([
        _client.fetchResume(),
        for (final view in views)
          _client.fetchLatest(parentId: view.id, limit: 12),
        for (final view in views)
          _client.fetchViewCount(
            view.id,
            itemType: switch (view.collectionType) {
              'movies' => 'Movie',
              'tvshows' => 'Series',
              _ => null,
            },
          ),
      ]);
      if (!mounted) return;
      final resume = results.first as List<JellyfinItem>;
      final latest = <String, List<JellyfinItem>>{};
      final counts = <String, int?>{};
      for (var i = 0; i < views.length; i++) {
        latest[views[i].id] = results[i + 1] as List<JellyfinItem>;
        counts[views[i].id] = results[1 + views.length + i] as int?;
      }
      setState(() {
        _views = views;
        _resume = resume;
        _latest = latest;
        _viewCounts = counts;
        _carousel = _pickCarousel(latest);
        _loading = false;
      });
      _startCarouselTimer();
    } catch (error) {
      if (!mounted) return;
      if (error is JellyfinException && error.statusCode == 401) {
        Navigator.pop(context, true);
        return;
      }
      final message = error is JellyfinException
          ? error.message
          : '加载失败，请重试';
      if (refresh) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      } else {
        setState(() {
          _error = message;
          _loading = false;
        });
      }
    }
  }

  List<JellyfinItem> _pickCarousel(Map<String, List<JellyfinItem>> latest) {
    final all = [for (final list in latest.values) ...list];
    final withBackdrop = all
        .where((item) => item.backdropImageTag != null)
        .toList();
    final candidates = withBackdrop.isEmpty ? all : withBackdrop;
    final seen = <String>{};
    return [
      for (final item in candidates)
        if (seen.add(item.id)) item,
    ].take(8).toList();
  }

  void _startCarouselTimer() {
    _carouselTimer?.cancel();
    if (_carousel.length < 2) return;
    _carouselTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted || _carouselDragging) return;
      final next = (_carouselIndex + 1) % _carousel.length;
      _carouselController.animateToPage(
        next,
        duration: const Duration(milliseconds: 550),
        curve: Curves.easeOutCubic,
      );
    });
  }

  Future<void> _play(JellyfinItem item) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final url = await _client.fetchPlaybackUrl(item.id);
      final launched = await _launchExternal(url);
      if (!launched && mounted) {
        messenger.showSnackBar(
          const SnackBar(content: Text('未找到可播放的应用')),
        );
      }
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            error is JellyfinException ? error.message : '无法播放：$error',
          ),
        ),
      );
    }
  }

  Future<bool> _launchExternal(String url) async {
    return launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  void _openDetail(JellyfinItem item) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => JellyfinDetailView(itemId: item.id, client: _client),
      ),
    ).then((result) {
      if (result == 'expired' && mounted) {
        Navigator.pop(context, true);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: jellyfinCinemaTheme(),
      child: Scaffold(
        backgroundColor: jellyfinBackground,
        body: SafeArea(
          bottom: false,
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
              ? _ErrorView(message: _error!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: () => _load(refresh: true),
                  child: CustomScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      SliverToBoxAdapter(child: _buildCarousel()),
                      if (_resume.isNotEmpty) ...[
                        const SliverToBoxAdapter(
                          child: _SectionTitle('继续观看'),
                        ),
                        SliverToBoxAdapter(child: _buildResumeRow()),
                      ],
                      if (_views.isNotEmpty) ...[
                        const SliverToBoxAdapter(
                          child: _SectionTitle('媒体库'),
                        ),
                        SliverToBoxAdapter(child: _buildViewsRow()),
                      ],
                      for (final view in _views)
                        if (_latest[view.id]?.isNotEmpty == true) ...[
                          SliverToBoxAdapter(
                            child: _SectionTitle('${view.name} · 最新添加'),
                          ),
                          SliverToBoxAdapter(
                            child: _buildLatestRow(view.id),
                          ),
                        ],
                      const SliverToBoxAdapter(child: SizedBox(height: 120)),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildCarousel() {
    if (_carousel.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: MediaQuery.sizeOf(context).width * 0.78,
      child: Stack(
        children: [
          NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              if (notification is ScrollStartNotification &&
                  notification.dragDetails != null) {
                _carouselDragging = true;
              } else if (notification is ScrollEndNotification) {
                _carouselDragging = false;
                _startCarouselTimer();
              }
              return false;
            },
            child: PageView.builder(
              controller: _carouselController,
              itemCount: _carousel.length,
              onPageChanged: (index) {
                setState(() => _carouselIndex = index);
              },
              itemBuilder: (context, index) {
                final item = _carousel[index];
                return _CarouselItem(
                  item: item,
                  client: _client,
                  onPlay: () => _play(item),
                  onOpen: () => _openDetail(item),
                );
              },
            ),
          ),
          if (_carousel.length > 1)
            Positioned(
              bottom: 14,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < _carousel.length; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: i == _carouselIndex ? 18 : 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: i == _carouselIndex
                            ? Colors.white
                            : Colors.white38,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildResumeRow() {
    return SizedBox(
      height: 185,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemCount: _resume.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final item = _resume[index];
          return _ResumeCard(item: item, client: _client, onTap: () => _play(item));
        },
      ),
    );
  }

  Widget _buildViewsRow() {
    return SizedBox(
      height: 118,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemCount: _views.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final view = _views[index];
          final count = _viewCounts[view.id];
          return _LibraryCard(
            view: view,
            count: count,
            onTap: () {
              final items = _latest[view.id] ?? const [];
              if (items.isNotEmpty) _openDetail(items.first);
            },
          );
        },
      ),
    );
  }

  Widget _buildLatestRow(String viewId) {
    final items = _latest[viewId] ?? const [];
    return SizedBox(
      height: 230,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final item = items[index];
          return _PosterCard(
            item: item,
            client: _client,
            onTap: () => _openDetail(item),
          );
        },
      ),
    );
  }
}

class _CarouselItem extends StatelessWidget {
  const _CarouselItem({
    required this.item,
    required this.client,
    required this.onPlay,
    required this.onOpen,
  });

  final JellyfinItem item;
  final JellyfinClient client;
  final VoidCallback onPlay;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final backdrop = item.backdropImageTag != null
        ? client.backdropUrl(item.id, tag: item.backdropImageTag, maxWidth: 1600)
        : null;
    return GestureDetector(
      onTap: onOpen,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (backdrop != null)
            Image.network(
              backdrop,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const JellyfinPlaceholder(),
            )
          else
            const JellyfinPlaceholder(),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.transparent,
                  jellyfinBackground,
                ],
              ),
            ),
          ),
          Positioned(
            left: 20,
            right: 20,
            bottom: 38,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.6,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    if (item.year != null) ...[
                      _CarouselChip(label: '${item.year}'),
                      const SizedBox(width: 8),
                    ],
                    if (item.communityRating != null) ...[
                      _CarouselChip(
                        label: item.communityRating!.toStringAsFixed(1),
                        icon: Icons.star_rounded,
                        iconColor: const Color(0xFFFFB020),
                      ),
                      const SizedBox(width: 8),
                    ],
                    if (item.genres.isNotEmpty)
                      Flexible(
                        child: Text(
                          item.genres.take(2).join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 22,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: onPlay,
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text(
                    '播放',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CarouselChip extends StatelessWidget {
  const _CarouselChip({required this.label, this.icon, this.iconColor});

  final String label;
  final IconData? icon;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: iconColor ?? Colors.white),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _ResumeCard extends StatelessWidget {
  const _ResumeCard({
    required this.item,
    required this.client,
    required this.onTap,
  });

  final JellyfinItem item;
  final JellyfinClient client;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final thumb = item.primaryImageTag != null
        ? client.imageUrl(item.id, tag: item.primaryImageTag, maxWidth: 480)
        : null;
    final subtitle = item.seriesName != null
        ? '${item.seriesName} · S${item.parentIndexNumber ?? '?'}E${item.indexNumber ?? '?'}'
        : item.year?.toString() ?? '';
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 230,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: thumb != null
                        ? Image.network(
                            thumb,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) =>
                                const JellyfinPlaceholder(),
                          )
                        : const JellyfinPlaceholder(),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      bottom: Radius.circular(14),
                    ),
                    child: LinearProgressIndicator(
                      value: item.progress,
                      minHeight: 3.5,
                      backgroundColor: Colors.white24,
                      color: jellyfinAccent,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              item.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (subtitle.isNotEmpty)
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
          ],
        ),
      ),
    );
  }
}

class _LibraryCard extends StatelessWidget {
  const _LibraryCard({required this.view, required this.count, required this.onTap});

  final JellyfinView view;
  final int? count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final icon = switch (view.collectionType) {
      'movies' => Icons.movie_filter_rounded,
      'tvshows' => Icons.live_tv_rounded,
      'music' => Icons.music_note_rounded,
      'photos' => Icons.photo_library_rounded,
      'homevideos' => Icons.video_library_rounded,
      'books' => Icons.menu_book_rounded,
      _ => Icons.grid_view_rounded,
    };
    final accent = switch (view.collectionType) {
      'movies' => const Color(0xFF00A4DC),
      'tvshows' => const Color(0xFF7C4DFF),
      'music' => const Color(0xFF26A69A),
      _ => const Color(0xFF8E8E99),
    };
    final countLabel = switch (view.collectionType) {
      'movies' => count == null ? '电影库' : '$count 部',
      'tvshows' => count == null ? '剧集库' : '$count 部',
      'music' => '音乐',
      'photos' => '照片',
      'homevideos' => '家庭视频',
      'books' => '图书',
      _ => '媒体库',
    };
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 150,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [accent.withValues(alpha: 0.30), accent.withValues(alpha: 0.10)],
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Icon(icon, color: Colors.white, size: 30),
            const Spacer(),
            Text(
              view.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              countLabel,
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _PosterCard extends StatelessWidget {
  const _PosterCard({
    required this.item,
    required this.client,
    required this.onTap,
  });

  final JellyfinItem item;
  final JellyfinClient client;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final poster = item.primaryImageTag != null
        ? client.imageUrl(item.id, tag: item.primaryImageTag, maxWidth: 300)
        : null;
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 120,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: AspectRatio(
                aspectRatio: 2 / 3,
                child: poster != null
                    ? Image.network(
                        poster,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) =>
                            const JellyfinPlaceholder(),
                      )
                    : const JellyfinPlaceholder(),
              ),
            ),
            const SizedBox(height: 7),
            Text(
              item.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (item.year != null)
              Text(
                '${item.year}',
                style: const TextStyle(color: Colors.white54, fontSize: 11),
              ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 22, 16, 10),
      child: Text(
        title,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.3,
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off_rounded, size: 44, color: Colors.white38),
          const SizedBox(height: 14),
          Text(message, style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 14),
          FilledButton.tonal(onPressed: onRetry, child: const Text('重试')),
        ],
      ),
    );
  }
}
```

注意：`_play` 中 `await _launchExternal(url)` 依赖 `package:url_launcher/url_launcher.dart` 的 `launchUrl`——上面完整实现已包含该 import 与 `_launchExternal` 方法体，直接复制即可。

- [ ] **Step 5: 运行测试验证通过**

```bash
export PATH="$PATH:/Users/alone/fvm/versions/stable/bin"
flutter test test/jellyfin_home_view_test.dart
```

Expected: `All tests passed!`（4 个测试）。若报 `jellyfin_detail_view.dart` 导入失败，执行 Step 5b 后重跑。

- [ ] **Step 5b: 创建 `lib/src/jellyfin_detail_view.dart` 占位**

```dart
import 'package:flutter/material.dart';

import 'jellyfin_client.dart';

class JellyfinDetailView extends StatefulWidget {
  const JellyfinDetailView({
    super.key,
    required this.itemId,
    required this.client,
  });

  final String itemId;
  final JellyfinClient client;

  @override
  State<JellyfinDetailView> createState() => _JellyfinDetailViewState();
}

class _JellyfinDetailViewState extends State<JellyfinDetailView> {
  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: Text('详情')));
  }
}
```

- [ ] **Step 6: Commit**

```bash
git add lib/src/jellyfin_theme.dart lib/src/jellyfin_home_view.dart lib/src/jellyfin_detail_view.dart test/jellyfin_home_view_test.dart
git commit -m "feat: add jellyfin cinematic home view"
```

---

### Task 6: Jellyfin 详情页（信息 + 系统播放器播放）

**Files:**
- Rewrite: `lib/src/jellyfin_detail_view.dart`（替换 Task 5 的占位实现）
- Test: `test/jellyfin_detail_view_test.dart`

**Interfaces:**
- Consumes: `JellyfinClient`（Task 2）：`fetchItem`、`fetchPeople`、`fetchPlaybackUrl`、`imageUrl`、`backdropUrl`；`JellyfinItem` / `JellyfinPerson` / `JellyfinException`
- Produces:
  - `class JellyfinDetailView extends StatefulWidget { const JellyfinDetailView({super.key, required this.itemId, required this.client}); final String itemId; final JellyfinClient client; }`
  - 行为契约：401 → `Navigator.pop(context, 'expired')`；播放 → `fetchPlaybackUrl` + `launchUrl(mode: externalApplication)`；`launchUrl` 返回 false → SnackBar「未找到可播放的应用」。

- [ ] **Step 1: 编写失败测试**

创建 `test/jellyfin_detail_view_test.dart`：

```dart
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:m3u8downloader/src/jellyfin_client.dart';
import 'package:m3u8downloader/src/jellyfin_detail_view.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

const _jsonHeaders = {'content-type': 'application/json'};

http.Response _ok(Object body) =>
    http.Response(jsonEncode(body), 200, headers: _jsonHeaders);

class _FakeLauncher extends Fake implements LauncherPlatform {
  String? launchedUrl;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launchedUrl = url;
    return true;
  }

  @override
  Future<bool> supportsMode(LaunchMode mode) async => true;
}

JellyfinClient _detailClient() => JellyfinClient(
  httpClient: MockClient((request) async {
    final path = request.url.path;
    if (path.endsWith('/Items/d1/People')) {
      return _ok([
        {
          'Id': 'p1',
          'Name': '克里斯托弗·诺兰',
          'Role': '导演',
          'PrimaryImageTag': 'pp1',
        },
        {'Id': 'p2', 'Name': '马修·麦康纳', 'Role': '演员'},
      ]);
    }
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
    LauncherPlatform.instance = launcher;
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

    await tester.tap(find.text('播放'));
    await tester.pumpAndSettle();

    expect(launcher.launchedUrl, isNotNull);
    expect(launcher.launchedUrl, contains('master.m3u8'));
    expect(tester.takeException(), isNull);
  });
}
```

- [ ] **Step 2: 运行测试验证失败**

```bash
export PATH="$PATH:/Users/alone/fvm/versions/stable/bin"
flutter test test/jellyfin_detail_view_test.dart
```

Expected: FAIL —— 占位实现无「星际穿越」等文案。

- [ ] **Step 3: 重写 `lib/src/jellyfin_detail_view.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'jellyfin_client.dart';
import 'jellyfin_theme.dart';

class JellyfinDetailView extends StatefulWidget {
  const JellyfinDetailView({
    super.key,
    required this.itemId,
    required this.client,
  });

  final String itemId;
  final JellyfinClient client;

  @override
  State<JellyfinDetailView> createState() => _JellyfinDetailViewState();
}

class _JellyfinDetailViewState extends State<JellyfinDetailView> {
  JellyfinItem? _item;
  List<JellyfinPerson> _people = [];
  bool _loading = true;
  String? _error;
  bool _expanded = false;
  bool _playing = false;

  JellyfinClient get _client => widget.client;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _client.fetchItem(widget.itemId),
        _client.fetchPeople(widget.itemId),
      ]);
      if (!mounted) return;
      setState(() {
        _item = results.first as JellyfinItem;
        _people = results.last as List<JellyfinPerson>;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      if (error is JellyfinException && error.statusCode == 401) {
        Navigator.pop(context, 'expired');
        return;
      }
      setState(() {
        _error = error is JellyfinException ? error.message : '加载失败，请重试';
        _loading = false;
      });
    }
  }

  Future<void> _play() async {
    final item = _item;
    if (item == null || _playing) return;
    setState(() => _playing = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final url = await _client.fetchPlaybackUrl(item.id);
      final launched = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
      if (!launched && mounted) {
        messenger.showSnackBar(
          const SnackBar(content: Text('未找到可播放的应用')),
        );
      }
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            error is JellyfinException ? error.message : '无法播放：$error',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _playing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = _item;
    return Theme(
      data: jellyfinCinemaTheme(),
      child: Scaffold(
        backgroundColor: jellyfinBackground,
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? _DetailErrorView(message: _error!, onRetry: _load)
            : item == null
            ? const SizedBox.shrink()
            : Stack(
                children: [
                  CustomScrollView(
                    slivers: [
                      _buildAppBar(item),
                      SliverToBoxAdapter(child: _buildBody(item)),
                    ],
                  ),
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 20,
                    child: SafeArea(
                      top: false,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.black,
                          minimumSize: const Size.fromHeight(52),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        onPressed: _playing ? null : _play,
                        icon: _playing
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.black,
                                ),
                              )
                            : const Icon(Icons.play_arrow_rounded),
                        label: Text(
                          _playing ? '正在获取播放地址…' : '播放',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildAppBar(JellyfinItem item) {
    final backdrop = item.backdropImageTag != null
        ? _client.backdropUrl(item.id, tag: item.backdropImageTag, maxWidth: 1600)
        : null;
    return SliverAppBar(
      expandedHeight: 300,
      pinned: true,
      backgroundColor: jellyfinBackground,
      foregroundColor: Colors.white,
      title: Text(
        item.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 17,
          fontWeight: FontWeight.w800,
        ),
      ),
      flexibleSpace: FlexibleSpaceBar(
        background: Stack(
          fit: StackFit.expand,
          children: [
            if (backdrop != null)
              Image.network(
                backdrop,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const JellyfinPlaceholder(),
              )
            else
              const JellyfinPlaceholder(),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [jellyfinBackground, Colors.transparent],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(JellyfinItem item) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 130),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: SizedBox(
                  width: 110,
                  child: AspectRatio(
                    aspectRatio: 2 / 3,
                    child: item.primaryImageTag != null
                        ? Image.network(
                            _client.imageUrl(
                              item.id,
                              tag: item.primaryImageTag,
                              maxWidth: 300,
                            ),
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) =>
                                const JellyfinPlaceholder(),
                          )
                        : const JellyfinPlaceholder(),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.4,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _InfoChip(
                          icon: Icons.calendar_today_outlined,
                          label: item.year?.toString() ?? '未知年份',
                        ),
                        if (item.runtimeMs != null)
                          _InfoChip(
                            icon: Icons.schedule_outlined,
                            label: _formatDuration(item.runtimeMs!),
                          ),
                        if (item.communityRating != null)
                          _InfoChip(
                            icon: Icons.star_rounded,
                            label: item.communityRating!.toStringAsFixed(1),
                            iconColor: const Color(0xFFFFB020),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (item.genres.isNotEmpty) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final genre in item.genres) _GenreChip(genre),
              ],
            ),
          ],
          if (item.overview.isNotEmpty) ...[
            const SizedBox(height: 18),
            const Text(
              '简介',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              item.overview,
              maxLines: _expanded ? null : 4,
              overflow: _expanded ? null : TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 14,
                height: 1.6,
              ),
            ),
            if (item.overview.length > 80)
              TextButton(
                onPressed: () => setState(() => _expanded = !_expanded),
                child: Text(_expanded ? '收起' : '展开'),
              ),
          ],
          if (_people.isNotEmpty) ...[
            const SizedBox(height: 18),
            const Text(
              '演职员',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 118,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _people.length,
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (context, index) =>
                    _PersonCard(person: _people[index], client: _client),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PersonCard extends StatelessWidget {
  const _PersonCard({required this.person, required this.client});

  final JellyfinPerson person;
  final JellyfinClient client;

  @override
  Widget build(BuildContext context) {
    final image = person.imageTag != null
        ? client.imageUrl(person.id, tag: person.imageTag, maxWidth: 200)
        : null;
    return SizedBox(
      width: 76,
      child: Column(
        children: [
          CircleAvatar(
            radius: 32,
            backgroundColor: const Color(0xFF1D1D24),
            foregroundImage: image != null ? NetworkImage(image) : null,
            child: const Icon(Icons.person_rounded, color: Colors.white38),
          ),
          const SizedBox(height: 6),
          Text(
            person.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (person.role.isNotEmpty)
            Text(
              person.role,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white54, fontSize: 11),
            ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({
    required this.icon,
    required this.label,
    this.iconColor,
  });

  final IconData icon;
  final String label;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: iconColor ?? Colors.white70),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _GenreChip extends StatelessWidget {
  const _GenreChip(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: jellyfinAccent.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: jellyfinAccent.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: jellyfinAccent,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _DetailErrorView extends StatelessWidget {
  const _DetailErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off_rounded, size: 44, color: Colors.white38),
          const SizedBox(height: 14),
          Text(message, style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 14),
          FilledButton.tonal(onPressed: onRetry, child: const Text('重试')),
        ],
      ),
    );
  }
}

String _formatDuration(int milliseconds) {
  final minutes = (milliseconds / 60000).round();
  if (minutes < 60) return '$minutes 分钟';
  return '${minutes ~/ 60} 小时 ${minutes % 60} 分钟';
}
```

- [ ] **Step 4: 运行测试验证通过**

```bash
export PATH="$PATH:/Users/alone/fvm/versions/stable/bin"
flutter test test/jellyfin_detail_view_test.dart
```

Expected: `All tests passed!`（1 个测试）。

- [ ] **Step 5: Commit**

```bash
git add lib/src/jellyfin_detail_view.dart test/jellyfin_detail_view_test.dart
git commit -m "feat: add jellyfin item detail view with external playback"
```

---

### Task 7: 接入底部导航 + 全量验证

**Files:**
- Modify: `lib/src/app.dart`
- Test: `test/server_tab_test.dart`

**Interfaces:**
- Consumes: `ServerHomeView`（Task 4，`const ServerHomeView()` 无参可用）
- Produces: 底部导航第 4 个 Tab「服务器」（位于「下载」之后、「设置」之前）

- [ ] **Step 1: 编写失败测试**

创建 `test/server_tab_test.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3u8downloader/src/app.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('home screen shows servers tab', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('首页'), findsOneWidget);
    expect(find.text('服务器'), findsOneWidget);
    expect(find.text('设置'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
```

- [ ] **Step 2: 运行测试验证失败**

```bash
export PATH="$PATH:/Users/alone/fvm/versions/stable/bin"
flutter test test/server_tab_test.dart
```

Expected: FAIL —— `find.text('服务器')` 找不到（尚无该 Tab）。

- [ ] **Step 3: 修改 `lib/src/app.dart`**

在 `HomeScreen.build` 的 `FullScreenPageStack` children 中，「下载」之后插入：

```dart
                  const ServerHomeView(),
```

具体位置（`app.dart` 第 229-243 行附近）：

```dart
                  children: [
                    const TwitterHomeView(),
                    DownloadsView(
                      key: _downloadsKey,
                      onCountChanged: (count) {
                        if (mounted && count != _taskCount) {
                          setState(() => _taskCount = count);
                        }
                      },
                    ),
                    const ServerHomeView(),
                    const SettingsView(),
                  ],
```

在 `_buildLiquidNavigationBar` 的 items 中，「下载」item 之后插入：

```dart
        const LiquidGlassTabBarItem(
          icon: Icons.dns_outlined,
          selectedIcon: Icons.dns_rounded,
          label: '服务器',
        ),
```

具体位置（`app.dart` 第 311-327 行附近）：

```dart
        LiquidGlassTabBarItem(
          icon: Icons.download_outlined,
          selectedIcon: Icons.download_rounded,
          label: downloadLabel,
        ),
        const LiquidGlassTabBarItem(
          icon: Icons.dns_outlined,
          selectedIcon: Icons.dns_rounded,
          label: '服务器',
        ),
        const LiquidGlassTabBarItem(
          icon: Icons.settings_outlined,
          selectedIcon: Icons.settings_rounded,
          label: '设置',
        ),
```

在文件顶部 import 区（`app.dart` 第 9-14 行）添加：

```dart
import 'server_home_view.dart';
```

- [ ] **Step 4: 运行测试验证通过**

```bash
export PATH="$PATH:/Users/alone/fvm/versions/stable/bin"
flutter test test/server_tab_test.dart
```

Expected: `All tests passed!`

- [ ] **Step 5: 全量测试 + 静态分析**

```bash
export PATH="$PATH:/Users/alone/fvm/versions/stable/bin"
flutter test
flutter analyze
```

Expected:
- `flutter test`：`All tests passed!`（原有 8 个测试文件 + 新增 6 个）。
- `flutter analyze`：`No issues found!`。

如 `flutter analyze` 报 `depend_on_referenced_packages` 之类问题，按提示修正（例如把 `url_launcher_platform_interface` 保留在 dev_dependencies 已满足）。

- [ ] **Step 6: Commit**

```bash
git add lib/src/app.dart test/server_tab_test.dart
git commit -m "feat: add servers tab to bottom navigation"
```

---

## Self-Review

- **Spec 覆盖核对**：
  - 服务器 Tab 第 4 位 ✓（Task 7）
  - Jellyfin/Emby/SMB 协议卡片 + 图标 ✓（Task 4 `_ProtocolOption`/`_ProtocolBadge`，Emby/SMB「即将支持」）
  - 添加流程（选协议→表单→测试并连接）✓（Task 4 `_AddServerSheet`）
  - 凭据安全存储 ✓（Task 3，密码/Token 走 SecureKeyValueStore）
  - 巨幕轮播（backdrop + 渐变 + 标题 + 胶囊 + 自动轮播 + 圆点）✓（Task 5 `_CarouselItem`/`_buildCarousel`）
  - 继续观看（进度条、点击直接播）✓（Task 5 `_ResumeCard`/`_play`）
  - 媒体库卡片 ✓（Task 5 `_LibraryCard` + `fetchViewCount`）
  - 各库最新添加 ✓（Task 5 `_buildLatestRow`）
  - 详情页（海报/年份/片长/评分/简介/演职员）+ 播放 ✓（Task 6）
  - 401 处理链（首页 pop true → 服务器页清除 Token 提示重连；详情页 'expired' → 首页转发）✓（Task 4/5/6）
  - 错误处理表全部落地 ✓（客户端 message 文案 + 各视图重试 + SnackBar）
- **Placeholder 扫描**：无 TBD/TODO；Task 5 中「`_launch` 尚未定义」段落已在 Step 4 内以「替换为直接调用 launchUrl」的方式消除歧义。
- **类型一致性**：`JellyfinHomeView(config:, client:)`、`JellyfinDetailView(itemId:, client:)`、`ServerHomeView(store:, clientFactory:)`、`JellyfinClient.configure(...)` 在 Task 4→7 间签名一致；`ServerSettingsStore.instance` 无参构造（Task 3 定义 `ServerSettingsStore({SecureKeyValueStore? secureStorage})`，`instance` 用无参形式创建，Task 4 测试用 `ServerSettingsStore(secureStorage: ...)` 注入，一致）。
