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
    this.people = const [],
    this.resolution,
    this.videoCodec,
    this.audioCodec,
    this.frameRate,
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
  final List<JellyfinPerson> people;
  final String? resolution;
  final String? videoCodec;
  final String? audioCodec;
  final double? frameRate;
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
    final data = await _getJson('/Users/$userId/Items/Resume', {
      'Fields': 'BackdropImageTags,Genres',
    }) as Map<String, dynamic>;
    return _parseItems(data['Items']);
  }

  Future<List<JellyfinItem>> fetchLatest({
    required String parentId,
    int limit = 12,
  }) async {
    final data = await _getJson(
      '/Users/$userId/Items/Latest',
      {
        'ParentId': parentId,
        'Limit': '$limit',
        'Fields': 'BackdropImageTags,Genres',
      },
    );
    return _parseItems(data);
  }

  Future<int?> fetchViewCount(String parentId, {String? itemType}) async {
    final data = await _getJson('/Users/$userId/Items', {
      'ParentId': parentId,
      'Recursive': 'true',
      'Limit': '0',
      'IncludeItemTypes': ?itemType,
    }) as Map<String, dynamic>;
    return data['TotalRecordCount'] as int?;
  }

  Future<List<JellyfinItem>> fetchItems({
    required String parentId,
    int limit = 48,
    int startIndex = 0,
  }) async {
    final data = await _getJson('/Users/$userId/Items', {
      'ParentId': parentId,
      'Recursive': 'true',
      'Limit': '$limit',
      'StartIndex': '$startIndex',
      'Fields': 'BackdropImageTags,Genres',
    }) as Map<String, dynamic>;
    return _parseItems(data['Items']);
  }

  Future<JellyfinItem> fetchItem(String id) async {
    final data = await _getJson(
      '/Users/$userId/Items/$id',
      {'Fields': 'People,Genres,Overview,BackdropImageTags,MediaSources'},
    ) as Map<String, dynamic>;
    return _parseItem(data);
  }

  Future<String> fetchPlaybackUrl(String id) async {
    try {
      final response = await _http
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
      final mediaSource = sources.first as Map<String, dynamic>;
      final mediaSourceId = mediaSource['Id'];
      if (mediaSourceId is! String || mediaSourceId.isEmpty) {
        throw const JellyfinException('该影片没有可播放的媒体源');
      }
      final direct =
          mediaSource['SupportsDirectStream'] == true &&
          ((mediaSource['Container'] as String? ?? '').toLowerCase())
              .contains('mp4');
      return '$_base/videos/$id/stream.mp4'
          '?api_key=$accessToken&MediaSourceId=$mediaSourceId'
          '&UserId=$userId&Static=$direct';
    } on JellyfinException {
      rethrow;
    } catch (_) {
      throw const JellyfinException('无法获取播放地址，请检查网络');
    }
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
    final media = _parseMediaInfo(data);
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
      people: [
        for (final person in data['People'] as List<dynamic>? ?? const [])
          if (person is Map<String, dynamic>)
            JellyfinPerson(
              id: person['Id'] as String? ?? '',
              name: person['Name'] as String? ?? '',
              role: person['Role'] as String? ?? '',
              imageTag: person['PrimaryImageTag'] as String?,
            ),
      ],
      resolution: media.resolution,
      videoCodec: media.videoCodec,
      audioCodec: media.audioCodec,
      frameRate: media.frameRate,
    );
  }

  ({String? resolution, String? videoCodec, String? audioCodec, double? frameRate}) _parseMediaInfo(
    Map<String, dynamic> data,
  ) {
    final sources = data['MediaSources'] as List<dynamic>? ?? const [];
    final streams = sources.isEmpty
        ? const <dynamic>[]
        : (sources.first as Map<String, dynamic>?)?['MediaStreams']
              as List<dynamic>?
          ?? const <dynamic>[];
    int? width;
    int? height;
    double? frameRate;
    String? videoCodec;
    String? audioCodec;
    for (final stream in streams) {
      if (stream is! Map<String, dynamic>) continue;
      final type = stream['Type'] as String?;
      if (type == 'Video') {
        width = stream['Width'] as int?;
        height = stream['Height'] as int?;
        videoCodec = stream['Codec'] as String?;
        frameRate = (stream['FrameRate'] as num?)?.toDouble();
      } else if (type == 'Audio' && audioCodec == null) {
        audioCodec = stream['Codec'] as String?;
      }
    }
    return (
      resolution: width != null && height != null
          ? '${width}x$height'
          : null,
      videoCodec: videoCodec,
      audioCodec: audioCodec,
      frameRate: frameRate,
    );
  }
}
