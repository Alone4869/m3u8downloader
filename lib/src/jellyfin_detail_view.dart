import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'jellyfin_client.dart';
import 'jellyfin_items_view.dart';
import 'jellyfin_theme.dart';
import 'video_player_launcher.dart';

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
  List<(IconData, String)> _mediaInfo = [];
  bool _loading = true;
  String? _error;
  bool _expanded = false;
  bool _playing = false;
  bool _transitionDone = false;

  Animation<double>? _routeAnimation;

  JellyfinClient get _client => widget.client;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_routeAnimation == null) {
      final animation = ModalRoute.of(context)?.animation;
      if (animation != null) {
        _routeAnimation = animation;
        if (animation.status == AnimationStatus.completed) {
          _transitionDone = true;
        } else {
          animation.addStatusListener(_onRouteStatus);
        }
      } else {
        _transitionDone = true;
      }
    }
  }

  @override
  void dispose() {
    _routeAnimation?.removeStatusListener(_onRouteStatus);
    super.dispose();
  }

  void _onRouteStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && !_transitionDone) {
      setState(() => _transitionDone = true);
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final item = await _client.fetchItem(widget.itemId);
      if (!mounted) return;
      setState(() {
        _item = item;
        _people = item.people;
        _mediaInfo = _buildMediaInfo(item);
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

  List<(IconData, String)> _buildMediaInfo(JellyfinItem item) {
    final info = <(IconData, String)>[];
    if (item.resolution != null) {
      info.add((Icons.high_quality_outlined, item.resolution!));
    }
    if (item.videoCodec != null) {
      info.add((Icons.videocam_outlined, item.videoCodec!));
    }
    if (item.audioCodec != null) {
      info.add((Icons.audiotrack_outlined, item.audioCodec!));
    }
    if (item.frameRate != null) {
      info.add((
        Icons.speed_outlined,
        '${item.frameRate!.toStringAsFixed(3)} fps',
      ));
    }
    return info;
  }

  Future<void> _play() async {
    final item = _item;
    if (item == null || _playing) return;
    setState(() => _playing = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final url = await _client.fetchPlaybackUrl(item.id);
      final launched = await const VideoPlayerLauncher().launch(url);
      if (!launched && mounted) {
        messenger.showSnackBar(const SnackBar(content: Text('未找到可播放的应用')));
      }
    } catch (error) {
      if (!mounted) return;
      if (error is JellyfinException && error.statusCode == 401) {
        Navigator.pop(context, 'expired');
        return;
      }
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

  void _openWorks({
    required String title,
    required Future<List<JellyfinItem>> Function(int limit, int startIndex)
    loader,
  }) {
    Navigator.push(
      context,
      jellyfinRoute(
        builder: (_) =>
            JellyfinItemsView(title: title, client: _client, loadPage: loader),
      ),
    ).then((result) {
      if (result == 'expired' && mounted) {
        Navigator.pop(context, 'expired');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final item = _item;
    return Theme(
      data: jellyfinCinemaTheme(),
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
        ),
        child: Scaffold(
          backgroundColor: jellyfinBackground,
          body: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
              ? _DetailErrorView(message: _error!, onRetry: _load)
              : item == null
              ? const SizedBox.shrink()
              : !_transitionDone
              ? const Center(child: CircularProgressIndicator())
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
      ),
    );
  }

  Widget _buildAppBar(JellyfinItem item) {
    final backdrop = item.backdropImageTag != null
        ? _client.backdropUrl(
            item.id,
            tag: item.backdropImageTag,
            maxWidth: 1000,
          )
        : item.primaryImageTag != null
        ? _client.imageUrl(item.id, tag: item.primaryImageTag, maxWidth: 1000)
        : null;
    return SliverAppBar(
      expandedHeight: jellyfinHeaderHeight,
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
            if (backdrop != null && _transitionDone)
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
                for (final genre in item.genres)
                  _GenreChip(
                    label: genre,
                    onTap: () => _openWorks(
                      title: genre,
                      loader: (limit, startIndex) => _client.fetchGenreWorks(
                        genre,
                        limit: limit,
                        startIndex: startIndex,
                      ),
                    ),
                  ),
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
          if (_mediaInfo.isNotEmpty) ...[
            const SizedBox(height: 18),
            const Text(
              '媒体信息',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final info in _mediaInfo)
                  _InfoChip(icon: info.$1, label: info.$2),
              ],
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
                itemBuilder: (context, index) {
                  final person = _people[index];
                  return _PersonCard(
                    person: person,
                    client: _client,
                    onTap: () => _openWorks(
                      title: person.name,
                      loader: (limit, startIndex) => _client.fetchPersonWorks(
                        person.id,
                        limit: limit,
                        startIndex: startIndex,
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PersonCard extends StatelessWidget {
  const _PersonCard({
    required this.person,
    required this.client,
    required this.onTap,
  });

  final JellyfinPerson person;
  final JellyfinClient client;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final image = person.imageTag != null
        ? client.imageUrl(person.id, tag: person.imageTag, maxWidth: 200)
        : null;
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
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
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.label, this.iconColor});

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
  const _GenreChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
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
