import 'dart:async';

import 'package:flutter/material.dart';

import 'jellyfin_client.dart';
import 'jellyfin_detail_view.dart';
import 'jellyfin_library_view.dart';
import 'jellyfin_theme.dart';
import 'server_settings.dart';
import 'video_player_launcher.dart';

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
      final launched = await const VideoPlayerLauncher().launch(url);
      if (!launched && mounted) {
        messenger.showSnackBar(
          const SnackBar(content: Text('未找到可播放的应用')),
        );
      }
    } catch (error) {
      if (!mounted) return;
      if (error is JellyfinException && error.statusCode == 401) {
        Navigator.pop(context, true);
        return;
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            error is JellyfinException ? error.message : '无法播放：$error',
          ),
        ),
      );
    }
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

  void _openLibrary(JellyfinView view) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => JellyfinLibraryView(view: view, client: _client),
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
                      if (_views.isEmpty)
                        const SliverFillRemaining(
                          hasScrollBody: false,
                          child: _EmptyView(),
                        ),
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
            client: _client,
            onTap: () => _openLibrary(view),
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
        : item.primaryImageTag != null
        ? client.imageUrl(item.id, tag: item.primaryImageTag, maxWidth: 1600)
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
  const _LibraryCard({
    required this.view,
    required this.count,
    required this.client,
    required this.onTap,
  });

  final JellyfinView view;
  final int? count;
  final JellyfinClient client;
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
    final cover = view.primaryImageTag != null
        ? client.imageUrl(view.id, tag: view.primaryImageTag, maxWidth: 300)
        : null;
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 150,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (cover != null)
                Image.network(
                  cover,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                )
              else
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        accent.withValues(alpha: 0.30),
                        accent.withValues(alpha: 0.10),
                      ],
                    ),
                  ),
                ),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.15),
                      Colors.black.withValues(alpha: 0.75),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(14),
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
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
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

class _EmptyView extends StatelessWidget {
  const _EmptyView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.video_library_outlined,
            size: 44,
            color: Colors.white38,
          ),
          const SizedBox(height: 14),
          const Text(
            '这个服务器上还没有媒体库',
            style: TextStyle(color: Colors.white70),
          ),
        ],
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
