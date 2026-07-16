import 'dart:async';
import 'dart:convert';
import 'dart:io';

class TwitterVideoVariant {
  const TwitterVideoVariant({
    required this.url,
    required this.bitrate,
    required this.width,
    required this.height,
  });

  final String url;
  final int bitrate;
  final int width;
  final int height;

  String get qualityLabel {
    if (height >= 2160) return '4K';
    if (height >= 1440) return '2K';
    if (height > 0) return '${height}p';
    if (bitrate >= 8000000) return '4K';
    if (bitrate >= 4000000) return '2K';
    if (bitrate >= 2000000) return 'HD';
    return 'SD';
  }

  String get resolutionLabel =>
      width > 0 && height > 0 ? '$width × $height' : '';

  String get bitrateLabel =>
      bitrate > 0 ? '${(bitrate / 1000000).toStringAsFixed(2)} Mbps' : '';

  String get detailsLabel {
    final parts = [resolutionLabel, bitrateLabel]
      ..removeWhere((part) => part.isEmpty);
    return parts.join(' · ');
  }
}

class TwitterVideoMedia {
  const TwitterVideoMedia({
    required this.id,
    required this.thumbnailUrl,
    required this.durationSeconds,
    required this.variants,
  });

  final String id;
  final String thumbnailUrl;
  final double durationSeconds;
  final List<TwitterVideoVariant> variants;
}

class TwitterVideoInfo {
  const TwitterVideoInfo({
    required this.tweetId,
    required this.tweetUrl,
    required this.authorName,
    required this.authorUsername,
    required this.avatarUrl,
    required this.text,
    required this.media,
  });

  final String tweetId;
  final String tweetUrl;
  final String authorName;
  final String authorUsername;
  final String avatarUrl;
  final String text;
  final List<TwitterVideoMedia> media;
}

class TwitterParseException implements Exception {
  const TwitterParseException(this.message);

  final String message;

  @override
  String toString() => message;
}

class TwitterParser {
  TwitterParser({HttpClient? client}) : _client = client ?? HttpClient();

  final HttpClient _client;

  static final RegExp _tweetPattern = RegExp(
    r'(?:https?://)?(?:www\.|mobile\.)?(?:x|twitter)\.com/[^\s/]+/status/(\d+)',
    caseSensitive: false,
  );

  static String? extractTweetId(String input) =>
      _tweetPattern.firstMatch(input)?.group(1);

  static String? extractTweetUrl(String input) {
    final match = _tweetPattern.firstMatch(input);
    if (match == null) return null;
    return 'https://x.com/i/status/${match.group(1)}';
  }

  Future<int?> probeContentLength(String url) async {
    final request = await _client
        .getUrl(Uri.parse(url))
        .timeout(const Duration(seconds: 10));
    request
      ..persistentConnection = false
      ..headers.set(HttpHeaders.rangeHeader, 'bytes=0-0')
      ..headers.set(HttpHeaders.acceptHeader, '*/*')
      ..headers.set(
        HttpHeaders.userAgentHeader,
        'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 Chrome/126 Mobile Safari/537.36',
      );
    final response = await request.close().timeout(const Duration(seconds: 15));
    final contentRange = response.headers.value(HttpHeaders.contentRangeHeader);
    final rangeLength = contentLengthFromRange(contentRange);
    final contentLength = response.contentLength;
    final statusCode = response.statusCode;
    final subscription = response.listen((_) {});
    await subscription.cancel();
    if (statusCode == HttpStatus.partialContent) return rangeLength;
    if (statusCode == HttpStatus.ok && contentLength > 0) return contentLength;
    return null;
  }

  static int? contentLengthFromRange(String? contentRange) {
    if (contentRange == null) return null;
    final total = RegExp(r'/(\d+)$').firstMatch(contentRange)?.group(1);
    final length = int.tryParse(total ?? '');
    return length != null && length > 0 ? length : null;
  }

  Future<TwitterVideoInfo> parse(String input) async {
    final tweetId = extractTweetId(input);
    if (tweetId == null) {
      throw const TwitterParseException('请输入有效的 Twitter/X 推文链接');
    }
    final sourceUrl = extractTweetUrl(input)!;

    Object? firstError;
    try {
      final json = await _getJson(
        Uri.parse('https://api.fxtwitter.com/status/$tweetId'),
      );
      return parseFxResponse(json, sourceUrl: sourceUrl);
    } catch (error) {
      firstError = error;
    }

    try {
      final json = await _getJson(
        Uri.parse('https://api.vxtwitter.com/status/$tweetId'),
      );
      return parseVxResponse(json, sourceUrl: sourceUrl);
    } catch (_) {
      throw TwitterParseException(
        firstError is TwitterParseException
            ? firstError.message
            : '暂时无法解析该推文，请确认推文公开且包含视频',
      );
    }
  }

  Future<String> resolveSnapCdnDownloadUrl({
    required String tweetUrl,
    required String directUrl,
  }) async {
    Object? firstError;
    for (final provider in const [
      (
        endpoint: 'https://savetwitter.net/api/ajaxSearch',
        referer: 'https://savetwitter.net/zh-cn3',
      ),
      (
        endpoint: 'https://snapvid.net/api/ajaxSearch',
        referer: 'https://snapvid.net/zh-cn1/twitter-downloader',
      ),
    ]) {
      try {
        final result = await _requestSnapCdnProvider(
          endpoint: provider.endpoint,
          referer: provider.referer,
          tweetUrl: tweetUrl,
        );
        return parseSnapCdnResponse(result, directUrl: directUrl);
      } catch (error) {
        firstError ??= error;
      }
    }
    throw TwitterParseException(
      firstError is TwitterParseException
          ? firstError.message
          : '暂时无法获取 SnapCDN 中转链接，请稍后重试',
    );
  }

  Future<Map<String, dynamic>> _requestSnapCdnProvider({
    required String endpoint,
    required String referer,
    required String tweetUrl,
  }) async {
    final request = await _client
        .postUrl(Uri.parse(endpoint))
        .timeout(const Duration(seconds: 12));
    request.headers
      ..set(
        HttpHeaders.contentTypeHeader,
        'application/x-www-form-urlencoded; charset=UTF-8',
      )
      ..set(HttpHeaders.acceptHeader, 'application/json')
      ..set('X-Requested-With', 'XMLHttpRequest')
      ..set(HttpHeaders.refererHeader, referer)
      ..set(
        HttpHeaders.userAgentHeader,
        'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 Chrome/126 Mobile Safari/537.36',
      );
    request.write(
      'q=${Uri.encodeQueryComponent(tweetUrl)}&lang=zh-cn&cftoken=',
    );
    final response = await request.close().timeout(const Duration(seconds: 25));
    final body = await utf8.decoder.bind(response).join();
    if (response.statusCode != HttpStatus.ok) {
      throw TwitterParseException('中转服务响应异常 (${response.statusCode})，请稍后重试');
    }
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      throw const TwitterParseException('中转服务返回了无法识别的数据');
    }
    return decoded;
  }

  static String parseSnapCdnResponse(
    Map<String, dynamic> root, {
    required String directUrl,
  }) {
    final html = root['data'];
    if (root['status'] != 'ok' || html is! String) {
      throw const TwitterParseException('SaveTwitter 暂时无法生成中转链接');
    }
    final links = RegExp(
      r'href="(https://dl\.snapcdn\.app/get\?token=[^"]+)"',
      caseSensitive: false,
    ).allMatches(html);
    final directUri = Uri.tryParse(directUrl);
    for (final link in links) {
      final relayUrl = link.group(1)!.replaceAll('&amp;', '&');
      final token = Uri.tryParse(relayUrl)?.queryParameters['token'];
      final source = _snapCdnSourceUrl(token);
      if (source == null) continue;
      if (source == directUrl) return relayUrl;
      final sourceUri = Uri.tryParse(source);
      if (sourceUri != null &&
          directUri != null &&
          sourceUri.replace(query: '').toString() ==
              directUri.replace(query: '').toString()) {
        return relayUrl;
      }
    }
    throw const TwitterParseException('中转服务没有返回该画质的下载链接');
  }

  static String? _snapCdnSourceUrl(String? token) {
    if (token == null) return null;
    final parts = token.split('.');
    if (parts.length < 2) return null;
    try {
      final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      );
      return payload is Map<String, dynamic> ? payload['url'] as String? : null;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>> _getJson(Uri uri) async {
    final request = await _client
        .getUrl(uri)
        .timeout(const Duration(seconds: 12));
    request.headers
      ..set(HttpHeaders.acceptHeader, 'application/json')
      ..set(
        HttpHeaders.userAgentHeader,
        'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 Chrome/126 Mobile Safari/537.36',
      );
    final response = await request.close().timeout(const Duration(seconds: 20));
    final body = await utf8.decoder.bind(response).join();
    if (response.statusCode != HttpStatus.ok) {
      throw TwitterParseException(
        response.statusCode == HttpStatus.notFound
            ? '没有找到该推文，可能已删除或不是公开推文'
            : '解析服务响应异常 (${response.statusCode})',
      );
    }
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      throw const TwitterParseException('解析服务返回了无法识别的数据');
    }
    return decoded;
  }

  static TwitterVideoInfo parseFxResponse(
    Map<String, dynamic> root, {
    required String sourceUrl,
  }) {
    final tweet = _asMap(root['tweet']);
    if (tweet == null) throw const TwitterParseException('没有找到该推文');
    final mediaRoot = _asMap(tweet['media']);
    final mediaItems = _asList(mediaRoot?['all']);
    final parsedMedia = <TwitterVideoMedia>[];

    for (final raw in mediaItems) {
      final media = _asMap(raw);
      if (media == null) continue;
      final type = '${media['type']}'.toLowerCase();
      if (type != 'video' && type != 'gif' && type != 'animated_gif') continue;
      final variants = _parseFxVariants(media);
      if (variants.isEmpty) continue;
      parsedMedia.add(
        TwitterVideoMedia(
          id: '${media['id'] ?? parsedMedia.length + 1}',
          thumbnailUrl: '${media['thumbnail_url'] ?? ''}',
          durationSeconds: _asDouble(media['duration']),
          variants: variants,
        ),
      );
    }

    if (parsedMedia.isEmpty) {
      throw const TwitterParseException('该推文中没有可下载的视频');
    }
    final author = _asMap(tweet['author']);
    return TwitterVideoInfo(
      tweetId: '${tweet['id'] ?? extractTweetId(sourceUrl) ?? ''}',
      tweetUrl: '${tweet['url'] ?? sourceUrl}',
      authorName: '${author?['name'] ?? 'X 用户'}',
      authorUsername: '${author?['screen_name'] ?? ''}',
      avatarUrl: '${author?['avatar_url'] ?? ''}',
      text: '${tweet['text'] ?? ''}',
      media: parsedMedia,
    );
  }

  static List<TwitterVideoVariant> _parseFxVariants(
    Map<String, dynamic> media,
  ) {
    final result = <TwitterVideoVariant>[];
    final seen = <String>{};
    final formats = _asList(media['formats']).isNotEmpty
        ? _asList(media['formats'])
        : _asList(media['variants']);
    for (final raw in formats) {
      final format = _asMap(raw);
      if (format == null) continue;
      final url = '${format['url'] ?? ''}';
      final container =
          '${format['container'] ?? format['content_type'] ?? ''}';
      if (url.isEmpty ||
          (!url.contains('.mp4') && !container.contains('mp4'))) {
        continue;
      }
      if (!seen.add(url)) continue;
      final resolution = RegExp(r'/(\d+)x(\d+)/').firstMatch(url);
      result.add(
        TwitterVideoVariant(
          url: url,
          bitrate: _asInt(format['bitrate']),
          width: int.tryParse(resolution?.group(1) ?? '') ?? 0,
          height: int.tryParse(resolution?.group(2) ?? '') ?? 0,
        ),
      );
    }
    if (result.isEmpty) {
      final url = '${media['url'] ?? ''}';
      if (url.contains('.mp4')) {
        final size = _asMap(media['size']);
        result.add(
          TwitterVideoVariant(
            url: url,
            bitrate: 0,
            width: _asInt(size?['width'] ?? media['width']),
            height: _asInt(size?['height'] ?? media['height']),
          ),
        );
      }
    }
    result.sort((a, b) {
      final height = b.height.compareTo(a.height);
      return height != 0 ? height : b.bitrate.compareTo(a.bitrate);
    });
    return result;
  }

  static TwitterVideoInfo parseVxResponse(
    Map<String, dynamic> root, {
    required String sourceUrl,
  }) {
    final mediaItems = _asList(root['media_extended']);
    final parsedMedia = <TwitterVideoMedia>[];
    for (final raw in mediaItems) {
      final media = _asMap(raw);
      if (media == null) continue;
      final type = '${media['type']}'.toLowerCase();
      final url = '${media['url'] ?? ''}';
      if ((type != 'video' && type != 'gif') || !url.contains('.mp4')) continue;
      final size = _asMap(media['size']);
      parsedMedia.add(
        TwitterVideoMedia(
          id: '${media['id_str'] ?? parsedMedia.length + 1}',
          thumbnailUrl: '${media['thumbnail_url'] ?? ''}',
          durationSeconds: _asDouble(media['duration_millis']) / 1000,
          variants: [
            TwitterVideoVariant(
              url: url,
              bitrate: 0,
              width: _asInt(size?['width']),
              height: _asInt(size?['height']),
            ),
          ],
        ),
      );
    }
    if (parsedMedia.isEmpty) {
      throw const TwitterParseException('该推文中没有可下载的视频');
    }
    return TwitterVideoInfo(
      tweetId: '${root['tweetID'] ?? extractTweetId(sourceUrl) ?? ''}',
      tweetUrl: '${root['tweetURL'] ?? sourceUrl}',
      authorName: '${root['user_name'] ?? 'X 用户'}',
      authorUsername: '${root['user_screen_name'] ?? ''}',
      avatarUrl: '${root['user_profile_image_url'] ?? ''}',
      text: '${root['text'] ?? ''}',
      media: parsedMedia,
    );
  }

  void close() => _client.close(force: true);

  static Map<String, dynamic>? _asMap(Object? value) =>
      value is Map<String, dynamic> ? value : null;

  static List<dynamic> _asList(Object? value) =>
      value is List ? value : const [];

  static int _asInt(Object? value) => switch (value) {
    int number => number,
    num number => number.toInt(),
    String text => int.tryParse(text) ?? 0,
    _ => 0,
  };

  static double _asDouble(Object? value) => switch (value) {
    num number => number.toDouble(),
    String text => double.tryParse(text) ?? 0,
    _ => 0,
  };
}
