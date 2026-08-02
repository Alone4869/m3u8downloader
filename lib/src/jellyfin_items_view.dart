import 'package:flutter/material.dart';

import 'jellyfin_client.dart';
import 'jellyfin_detail_view.dart';
import 'jellyfin_theme.dart';

class JellyfinItemsView extends StatefulWidget {
  const JellyfinItemsView({
    super.key,
    required this.title,
    required this.client,
    required this.loadPage,
  });

  final String title;
  final JellyfinClient client;
  final Future<List<JellyfinItem>> Function(int limit, int startIndex) loadPage;

  @override
  State<JellyfinItemsView> createState() => _JellyfinItemsViewState();
}

class _JellyfinItemsViewState extends State<JellyfinItemsView> {
  static const _pageSize = 48;

  final _scrollController = ScrollController();
  List<JellyfinItem> _items = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _endReached = false;
  String? _error;

  JellyfinClient get _client => widget.client;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _load();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.extentAfter < 600) {
      _loadMore();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await widget.loadPage(_pageSize, 0);
      if (!mounted) return;
      setState(() {
        _items = items;
        _endReached = items.length < _pageSize;
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

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || _endReached || _error != null) return;
    setState(() => _loadingMore = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final items = await widget.loadPage(_pageSize, _items.length);
      if (!mounted) return;
      setState(() {
        _items = [..._items, ...items];
        _endReached = items.length < _pageSize;
        _loadingMore = false;
      });
    } catch (error) {
      if (!mounted) return;
      if (error is JellyfinException && error.statusCode == 401) {
        Navigator.pop(context, 'expired');
        return;
      }
      setState(() => _loadingMore = false);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            error is JellyfinException ? error.message : '加载更多失败，请重试',
          ),
        ),
      );
    }
  }

  void _openDetail(JellyfinItem item) {
    Navigator.push(
      context,
      jellyfinRoute(
        builder: (_) => JellyfinDetailView(itemId: item.id, client: _client),
      ),
    ).then((result) {
      if (result == 'expired' && mounted) {
        Navigator.pop(context, 'expired');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: jellyfinCinemaTheme(),
      child: Scaffold(
        backgroundColor: jellyfinBackground,
        appBar: AppBar(
          backgroundColor: jellyfinBackground,
          foregroundColor: Colors.white,
          title: Text(
            widget.title,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? _LibraryErrorView(message: _error!, onRetry: _load)
            : _items.isEmpty
            ? const _LibraryEmptyView()
            : RefreshIndicator(
                onRefresh: _load,
                child: CustomScrollView(
                  controller: _scrollController,
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                      sliver: SliverGrid(
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              mainAxisSpacing: 14,
                              crossAxisSpacing: 12,
                              childAspectRatio: 0.56,
                            ),
                        delegate: SliverChildBuilderDelegate((context, index) {
                          final item = _items[index];
                          return _LibraryPosterCard(
                            item: item,
                            client: _client,
                            onTap: () => _openDetail(item),
                          );
                        }, childCount: _items.length),
                      ),
                    ),
                    if (_loadingMore)
                      const SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.all(20),
                          child: Center(
                            child: SizedBox.square(
                              dimension: 22,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        ),
                      ),
                    const SliverToBoxAdapter(child: SizedBox(height: 40)),
                  ],
                ),
              ),
      ),
    );
  }
}

class _LibraryPosterCard extends StatelessWidget {
  const _LibraryPosterCard({
    required this.item,
    required this.client,
    required this.onTap,
  });

  final JellyfinItem item;
  final JellyfinClient client;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox.expand(
                child: item.primaryImageTag != null
                    ? Image.network(
                        client.imageUrl(
                          item.id,
                          tag: item.primaryImageTag,
                          maxWidth: 300,
                        ),
                        fit: BoxFit.cover,
                        frameBuilder: (context, child, frame, wasSync) {
                          if (wasSync) return child;
                          return AnimatedOpacity(
                            opacity: frame == null ? 0 : 1,
                            duration: const Duration(milliseconds: 120),
                            curve: Curves.easeOut,
                            child: child,
                          );
                        },
                        errorBuilder: (_, _, _) => const _PosterPlaceholder(),
                      )
                    : const _PosterPlaceholder(),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            item.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _PosterPlaceholder extends StatelessWidget {
  const _PosterPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white10,
      child: const Center(
        child: Icon(Icons.movie_outlined, color: Colors.white24, size: 30),
      ),
    );
  }
}

class _LibraryEmptyView extends StatelessWidget {
  const _LibraryEmptyView();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.video_library_outlined, color: Colors.white24, size: 44),
          SizedBox(height: 12),
          Text(
            '这里暂时没有内容',
            style: TextStyle(color: Colors.white54, fontSize: 15),
          ),
        ],
      ),
    );
  }
}

class _LibraryErrorView extends StatelessWidget {
  const _LibraryErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off_outlined, color: Colors.white24, size: 44),
          const SizedBox(height: 12),
          Text(
            message,
            style: const TextStyle(color: Colors.white54, fontSize: 15),
          ),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: onRetry,
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: Colors.white38),
            ),
            child: const Text('重试'),
          ),
        ],
      ),
    );
  }
}
