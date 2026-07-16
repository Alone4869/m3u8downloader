import 'dart:async';

import 'package:flutter/material.dart';

import 'download_bridge.dart';
import 'glass_surface.dart';
import 'twitter_download_settings.dart';
import 'twitter_parser.dart';

class TwitterHomeView extends StatefulWidget {
  const TwitterHomeView({super.key});

  @override
  State<TwitterHomeView> createState() => _TwitterHomeViewState();
}

class _TwitterHomeViewState extends State<TwitterHomeView> {
  final _urlController = TextEditingController();
  final _urlFocus = FocusNode();
  final _parser = TwitterParser();
  Timer? _autoParseTimer;
  TwitterVideoInfo? _videoInfo;
  String? _error;
  String? _lastParsedUrl;
  bool _loading = false;
  int _requestGeneration = 0;
  TwitterDownloadRoute _downloadRoute =
      TwitterDownloadSettingsStore.instance.route.value;

  @override
  void initState() {
    super.initState();
    TwitterDownloadSettingsStore.instance.route.addListener(
      _onDownloadRouteChanged,
    );
    unawaited(TwitterDownloadSettingsStore.instance.load());
  }

  void _onDownloadRouteChanged() {
    if (!mounted) return;
    setState(() {
      _downloadRoute = TwitterDownloadSettingsStore.instance.route.value;
    });
  }

  @override
  void dispose() {
    _autoParseTimer?.cancel();
    TwitterDownloadSettingsStore.instance.route.removeListener(
      _onDownloadRouteChanged,
    );
    _parser.close();
    _urlController.dispose();
    _urlFocus.dispose();
    super.dispose();
  }

  void _onUrlChanged(String value) {
    _autoParseTimer?.cancel();
    if (value.trim().isEmpty) {
      setState(() {
        _videoInfo = null;
        _error = null;
        _lastParsedUrl = null;
      });
      return;
    }
    if (TwitterParser.extractTweetId(value) == null) return;
    _autoParseTimer = Timer(
      const Duration(milliseconds: 500),
      () => _parse(value),
    );
  }

  void _clearInput() {
    _autoParseTimer?.cancel();
    _requestGeneration++;
    _urlController.clear();
    _urlFocus.requestFocus();
    setState(() {
      _videoInfo = null;
      _error = null;
      _lastParsedUrl = null;
      _loading = false;
    });
  }

  Future<void> _parse([String? rawUrl, bool force = false]) async {
    final input = (rawUrl ?? _urlController.text).trim();
    final normalized = TwitterParser.extractTweetUrl(input);
    if (normalized == null) {
      setState(() {
        _error = '请输入有效的 Twitter/X 推文链接';
        _videoInfo = null;
      });
      return;
    }
    if (!force && (_loading || normalized == _lastParsedUrl)) return;
    final generation = ++_requestGeneration;
    _lastParsedUrl = normalized;
    _urlFocus.unfocus();
    setState(() {
      _loading = true;
      _error = null;
      _videoInfo = null;
    });
    try {
      final info = await _parser.parse(normalized);
      if (!mounted || generation != _requestGeneration) return;
      setState(() => _videoInfo = info);
    } catch (error) {
      if (!mounted || generation != _requestGeneration) return;
      setState(() {
        _lastParsedUrl = null;
        _error = error is TwitterParseException ? error.message : '解析失败，请稍后重试';
      });
    } finally {
      if (mounted && generation == _requestGeneration) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _confirmDownload(
    TwitterVideoInfo info,
    TwitterVideoMedia media,
    TwitterVideoVariant variant,
    int mediaIndex,
  ) async {
    final quality = variant.qualityLabel;
    final username = info.authorUsername.isEmpty
        ? 'twitter'
        : info.authorUsername;
    final suffix = info.media.length > 1 ? '_${mediaIndex + 1}' : '';
    final initialFileName = _safeFileName(
      '${username}_${info.tweetId}$suffix-$quality.mp4',
    );
    final controller = TextEditingController(text: initialFileName)
      ..selection = TextSelection(
        baseOffset: 0,
        extentOffset: initialFileName.toLowerCase().endsWith('.mp4')
            ? initialFileName.length - 4
            : initialFileName.length,
      );
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          icon: const Icon(Icons.download_for_offline_outlined),
          title: Text('下载 $quality 画质'),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _DownloadSummary(
                  media: media,
                  variant: variant,
                  route: _downloadRoute,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: controller,
                  autofocus: true,
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(
                    labelText: '文件名',
                    prefixIcon: Icon(Icons.video_file_outlined),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('取消'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(dialogContext, true),
              icon: const Icon(Icons.download_rounded),
              label: const Text('开始下载'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      var fileName = _safeFileName(controller.text.trim());
      if (fileName.isEmpty) fileName = 'twitter_${info.tweetId}-$quality.mp4';
      if (!fileName.toLowerCase().endsWith('.mp4')) fileName = '$fileName.mp4';
      final downloadUrl = await _resolveDownloadUrl(info, variant);
      if (downloadUrl == null) return;
      await DownloadBridge.instance.startDownload(
        url: downloadUrl,
        fileName: fileName,
        cookie: '',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$quality 画质已加入后台下载')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('无法启动下载：$error')));
    } finally {
      controller.dispose();
    }
  }

  Future<String?> _resolveDownloadUrl(
    TwitterVideoInfo info,
    TwitterVideoVariant variant,
  ) async {
    if (_downloadRoute == TwitterDownloadRoute.direct) return variant.url;

    final dialogContext = Completer<BuildContext>();
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          if (!dialogContext.isCompleted) dialogContext.complete(context);
          return const AlertDialog(
            content: Row(
              children: [
                CircularProgressIndicator(),
                SizedBox(width: 18),
                Expanded(child: Text('正在获取 SnapCDN 中转链接…')),
              ],
            ),
          );
        },
      ),
    );
    final progressContext = await dialogContext.future;
    try {
      return await _parser.resolveSnapCdnDownloadUrl(
        tweetUrl: info.tweetUrl,
        directUrl: variant.url,
      );
    } catch (error) {
      if (!mounted) return null;
      final message = error is TwitterParseException
          ? error.message
          : '无法获取 SnapCDN 中转链接';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$message；可在设置中切回 X 官方直连')));
      return null;
    } finally {
      if (progressContext.mounted) Navigator.pop(progressContext);
    }
  }

  String _safeFileName(String input) => input
      .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 118),
          children: [
            const _HomeHeader(),
            const SizedBox(height: 18),
            _UrlInputCard(
              controller: _urlController,
              focusNode: _urlFocus,
              loading: _loading,
              onChanged: _onUrlChanged,
              onClear: _clearInput,
              onParse: () => _parse(null, true),
            ),
            const SizedBox(height: 18),
            if (_loading) const _ParsingCard(),
            if (!_loading && _error != null)
              _ParseErrorCard(
                message: _error!,
                onRetry: () => _parse(null, true),
              ),
            if (!_loading && _videoInfo != null)
              _VideoResult(info: _videoInfo!, onDownload: _confirmDownload),
            if (!_loading && _error == null && _videoInfo == null)
              const _HomeGuide(),
          ],
        ),
      ),
    );
  }
}

class _HomeHeader extends StatelessWidget {
  const _HomeHeader();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: colors.primary,
            borderRadius: BorderRadius.circular(17),
          ),
          alignment: Alignment.center,
          child: const Text(
            '𝕏',
            style: TextStyle(
              color: Colors.white,
              fontSize: 29,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'X 视频下载',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                '粘贴推文链接，选择需要的画质',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _UrlInputCard extends StatelessWidget {
  const _UrlInputCard({
    required this.controller,
    required this.focusNode,
    required this.loading,
    required this.onChanged,
    required this.onClear,
    required this.onParse,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool loading;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final VoidCallback onParse;

  @override
  Widget build(BuildContext context) {
    return AppSurface(
      borderRadius: 22,
      elevated: true,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: controller,
            focusNode: focusNode,
            onChanged: onChanged,
            onSubmitted: (_) => onParse(),
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.go,
            autocorrect: false,
            maxLines: 2,
            minLines: 1,
            decoration: InputDecoration(
              labelText: 'Twitter/X 推文 URL',
              hintText: 'https://x.com/user/status/…',
              prefixIcon: const Icon(Icons.link_rounded),
              suffixIcon: IconButton(
                tooltip: '清空',
                onPressed: onClear,
                icon: const Icon(Icons.clear_rounded),
              ),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: loading ? null : onParse,
            icon: loading
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.auto_awesome_rounded),
            label: Text(loading ? '正在解析…' : '解析视频'),
          ),
          const SizedBox(height: 8),
          Text(
            '检测到有效链接后会自动解析',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _ParsingCard extends StatelessWidget {
  const _ParsingCard();

  @override
  Widget build(BuildContext context) {
    return const AppSurface(
      padding: EdgeInsets.all(22),
      child: Row(
        children: [
          CircularProgressIndicator(),
          SizedBox(width: 18),
          Expanded(child: Text('正在获取推文信息和可用画质…')),
        ],
      ),
    );
  }
}

class _ParseErrorCard extends StatelessWidget {
  const _ParseErrorCard({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AppSurface(
      padding: const EdgeInsets.all(18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline_rounded, color: colors.error),
          const SizedBox(width: 12),
          Expanded(child: Text(message)),
          TextButton(onPressed: onRetry, child: const Text('重试')),
        ],
      ),
    );
  }
}

class _HomeGuide extends StatelessWidget {
  const _HomeGuide();

  @override
  Widget build(BuildContext context) {
    return AppSurface(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '使用方法',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          const _GuideStep(
            number: '1',
            title: '复制推文链接',
            subtitle: '在 X 的分享菜单中选择“复制链接”',
          ),
          const _GuideStep(
            number: '2',
            title: '粘贴并自动解析',
            subtitle: '应用会读取视频缩略图和全部可用画质',
          ),
          const _GuideStep(
            number: '3',
            title: '选择画质下载',
            subtitle: '确认文件名后加入后台高速下载',
          ),
        ],
      ),
    );
  }
}

class _GuideStep extends StatelessWidget {
  const _GuideStep({
    required this.number,
    required this.title,
    required this.subtitle,
  });

  final String number;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: colors.primaryContainer,
        foregroundColor: colors.onPrimaryContainer,
        child: Text(
          number,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(subtitle),
    );
  }
}

typedef _DownloadCallback =
    Future<void> Function(
      TwitterVideoInfo info,
      TwitterVideoMedia media,
      TwitterVideoVariant variant,
      int mediaIndex,
    );

class _VideoResult extends StatelessWidget {
  const _VideoResult({required this.info, required this.onDownload});

  final TwitterVideoInfo info;
  final _DownloadCallback onDownload;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppSurface(
          borderRadius: 22,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _NetworkAvatar(url: info.avatarUrl),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          info.authorName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        if (info.authorUsername.isNotEmpty)
                          Text(
                            '@${info.authorUsername}',
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text('${info.media.length} 个视频'),
                  ),
                ],
              ),
              if (info.text.isNotEmpty) ...[
                const SizedBox(height: 14),
                SelectableText(
                  info.text,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        for (int index = 0; index < info.media.length; index++) ...[
          _MediaCard(
            media: info.media[index],
            index: index,
            count: info.media.length,
            onDownload: (variant) =>
                onDownload(info, info.media[index], variant, index),
          ),
          if (index != info.media.length - 1) const SizedBox(height: 14),
        ],
      ],
    );
  }
}

class _MediaCard extends StatelessWidget {
  const _MediaCard({
    required this.media,
    required this.index,
    required this.count,
    required this.onDownload,
  });

  final TwitterVideoMedia media;
  final int index;
  final int count;
  final ValueChanged<TwitterVideoVariant> onDownload;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AppSurface(
      borderRadius: 22,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (media.thumbnailUrl.isNotEmpty)
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(21),
              ),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Image.network(
                  media.thumbnailUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => ColoredBox(
                    color: colors.surfaceContainerHighest,
                    child: const Icon(Icons.movie_outlined, size: 54),
                  ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 15, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    count > 1 ? '视频 ${index + 1} · 选择画质' : '选择下载画质',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text(
                  '${media.variants.length} 档',
                  style: TextStyle(color: colors.onSurfaceVariant),
                ),
              ],
            ),
          ),
          for (final variant in media.variants)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 4, 10, 8),
              child: Material(
                color: colors.surfaceContainerLow,
                borderRadius: BorderRadius.circular(16),
                child: ListTile(
                  horizontalTitleGap: 12,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  leading: Container(
                    width: 68,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: colors.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      variant.qualityLabel,
                      style: TextStyle(
                        color: colors.onPrimaryContainer,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  title: Text(
                    variant.detailsLabel.isEmpty
                        ? 'MP4 视频'
                        : variant.detailsLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    variant.estimatedSize(media.durationSeconds).isEmpty
                        ? '点击确认并下载'
                        : '${variant.estimatedSize(media.durationSeconds)} · MP4',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: const Icon(Icons.download_rounded),
                  onTap: () => onDownload(variant),
                ),
              ),
            ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

class _NetworkAvatar extends StatelessWidget {
  const _NetworkAvatar({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    final fallback = Icon(
      Icons.person_rounded,
      color: Theme.of(context).colorScheme.onPrimaryContainer,
    );
    return CircleAvatar(
      radius: 23,
      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      foregroundImage: url.isEmpty ? null : NetworkImage(url),
      child: fallback,
    );
  }
}

class _DownloadSummary extends StatelessWidget {
  const _DownloadSummary({
    required this.media,
    required this.variant,
    required this.route,
  });

  final TwitterVideoMedia media;
  final TwitterVideoVariant variant;
  final TwitterDownloadRoute route;

  @override
  Widget build(BuildContext context) {
    final estimated = variant.estimatedSize(media.durationSeconds);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(
            Icons.high_quality_rounded,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  variant.detailsLabel.isEmpty
                      ? variant.qualityLabel
                      : '${variant.qualityLabel} · ${variant.detailsLabel}',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                Text(
                  estimated.isEmpty
                      ? route.title
                      : '${route.title} · $estimated · 实际大小以服务器为准',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
