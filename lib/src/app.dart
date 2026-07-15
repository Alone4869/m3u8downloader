import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';

import 'browser_settings.dart';
import 'download_bridge.dart';
import 'glass_surface.dart';
import 'settings_view.dart';
import 'smb_upload.dart';

class M3u8DownloaderApp extends StatelessWidget {
  const M3u8DownloaderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'M3U8 视频下载器',
      theme: _buildAppTheme(Brightness.light),
      darkTheme: _buildAppTheme(Brightness.dark),
      themeMode: ThemeMode.system,
      home: const HomeScreen(),
    );
  }
}

ThemeData _buildAppTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF3F6FD8),
    brightness: brightness,
    dynamicSchemeVariant: DynamicSchemeVariant.tonalSpot,
  );
  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
  );
  return base.copyWith(
    scaffoldBackgroundColor: dark
        ? const Color(0xFF0E1015)
        : const Color(0xFFF6F7FB),
    appBarTheme: AppBarTheme(
      centerTitle: false,
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: base.textTheme.titleLarge?.copyWith(
        color: scheme.onSurface,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.4,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 68,
      elevation: 0,
      backgroundColor: Colors.transparent,
      indicatorColor: scheme.primary.withValues(alpha: dark ? 0.30 : 0.16),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => base.textTheme.labelMedium?.copyWith(
          color: states.contains(WidgetState.selected)
              ? scheme.primary
              : scheme.onSurfaceVariant,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w700
              : FontWeight.w500,
        ),
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: dark ? const Color(0xFF181B22) : Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    dialogTheme: DialogThemeData(
      elevation: 18,
      backgroundColor: dark ? const Color(0xFF191C22) : Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(
          color: Colors.white.withValues(alpha: dark ? 0.14 : 0.65),
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark ? const Color(0xFF21242C) : const Color(0xFFF0F2F7),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: scheme.outlineVariant.withAlpha(120)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: scheme.primary, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 48),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant.withAlpha(130),
      space: 1,
    ),
  );
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _browserKey = GlobalKey<_BrowserViewState>();
  final _downloadsKey = GlobalKey<_DownloadsViewState>();
  int _selectedIndex = 0;
  int _taskCount = 0;
  DateTime? _exitArmedAt;
  bool _handlingBack = false;

  void _selectDestination(int index) {
    _exitArmedAt = null;
    setState(() => _selectedIndex = index);
  }

  Future<void> _handleSystemBack() async {
    if (_handlingBack) return;
    _handlingBack = true;
    try {
      if (_selectedIndex == 0) {
        if (await (_browserKey.currentState?.handleSystemBack() ??
            Future.value(false))) {
          _exitArmedAt = null;
          return;
        }
      } else if (_selectedIndex == 1) {
        if (_downloadsKey.currentState?.handleSystemBack() == true) {
          _exitArmedAt = null;
          return;
        }
        _selectDestination(0);
        return;
      } else {
        _selectDestination(0);
        return;
      }

      final now = DateTime.now();
      final armedAt = _exitArmedAt;
      if (armedAt != null &&
          now.difference(armedAt) <= const Duration(seconds: 2)) {
        await SystemNavigator.pop();
        return;
      }
      _exitArmedAt = now;
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      messenger
        ..clearSnackBars()
        ..showSnackBar(
          const SnackBar(
            content: Text('再返回一次退出应用'),
            duration: Duration(seconds: 2),
          ),
        );
    } finally {
      _handlingBack = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return PopScope<Object?>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_handleSystemBack());
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
          statusBarBrightness: dark ? Brightness.dark : Brightness.light,
          systemStatusBarContrastEnforced: false,
        ),
        child: AppBackdrop(
          child: Scaffold(
            backgroundColor: Colors.transparent,
            body: FullScreenPageStack(
              index: _selectedIndex,
              children: [
                BrowserView(key: _browserKey),
                DownloadsView(
                  key: _downloadsKey,
                  onCountChanged: (count) {
                    if (mounted && count != _taskCount) {
                      setState(() => _taskCount = count);
                    }
                  },
                ),
                const SettingsView(),
              ],
            ),
            bottomNavigationBar: SafeArea(
              top: false,
              minimum: const EdgeInsets.fromLTRB(14, 0, 14, 10),
              child: _LiquidNavigationBar(
                selectedIndex: _selectedIndex,
                taskCount: _taskCount,
                onChanged: _selectDestination,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LiquidNavigationBar extends StatelessWidget {
  const _LiquidNavigationBar({
    required this.selectedIndex,
    required this.taskCount,
    required this.onChanged,
  });

  final int selectedIndex;
  final int taskCount;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final downloadLabel = taskCount > 0 ? '下载 $taskCount' : '下载';

    return LayoutBuilder(
      builder: (context, constraints) => LiquidGlassBottomNavBar(
        width: constraints.maxWidth,
        height: 68,
        margin: EdgeInsets.zero,
        itemPadding: 5,
        selectedIndex: selectedIndex,
        onChanged: onChanged,
        items: [
          const LiquidGlassTabBarItem(
            icon: Icons.public_outlined,
            selectedIcon: Icons.public_rounded,
            label: '浏览器',
          ),
          LiquidGlassTabBarItem(
            icon: Icons.download_outlined,
            selectedIcon: Icons.download_rounded,
            label: downloadLabel,
          ),
          const LiquidGlassTabBarItem(
            icon: Icons.settings_outlined,
            selectedIcon: Icons.settings_rounded,
            label: '设置',
          ),
        ],
        itemStyle: LiquidGlassNavItemStyle(
          selectedColor: colors.primary,
          unselectedColor: colors.onSurfaceVariant,
          iconSize: 23,
          labelFontSize: 11,
          iconLabelGap: 3,
          selectedFontWeight: FontWeight.w700,
        ),
        pillStyle: LiquidGlassNavPillStyle(
          mode: LiquidGlassPillMode.none,
          animated: true,
          animationDuration: const Duration(milliseconds: 280),
          animationCurve: Curves.easeOutCubic,
          color: colors.primary.withValues(alpha: dark ? 0.22 : 0.13),
        ),
        style: LiquidGlassStyle(
          shape: LiquidGlassShape.continuousRoundedRectangle(
            cornerRadius: 28,
            borderWidth: 0.9,
            borderColor: Colors.white.withValues(alpha: dark ? 0.17 : 0.72),
          ),
          appearance: LiquidGlassAppearance(
            color: dark ? const Color(0x7A171A21) : const Color(0x8AFFFFFF),
            saturation: 1.08,
            blur: const LiquidGlassBlur(sigmaX: 10, sigmaY: 10),
          ),
          refraction: const LiquidGlassRefraction(
            distortion: 0.035,
            distortionWidth: 20,
            chromaticAberration: 0.0008,
          ),
        ),
      ),
    );
  }
}

/// Keeps every tab under tight screen constraints.
///
/// An [IndexedStack] uses loose constraints by default. A nested [Scaffold]
/// can therefore shrink to its empty content, which previously placed the
/// downloads action bar halfway up the screen.
class FullScreenPageStack extends StatelessWidget {
  const FullScreenPageStack({
    super.key,
    required this.index,
    required this.children,
  });

  final int index;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: IndexedStack(
        index: index,
        sizing: StackFit.expand,
        children: children,
      ),
    );
  }
}

class BrowserView extends StatefulWidget {
  const BrowserView({super.key});

  @override
  State<BrowserView> createState() => _BrowserViewState();
}

class _BrowserViewState extends State<BrowserView> {
  final _addressController = TextEditingController(text: defaultBrowserHomeUrl);
  final _addressFocus = FocusNode();
  final Set<String> _handledUrls = {};
  InAppWebViewController? _webViewController;
  String _homeUrl = defaultBrowserHomeUrl;
  bool _homeUrlReady = false;
  double _progress = 0;
  String _pageTitle = '视频解析';
  bool _canGoBack = false;
  bool _canGoForward = false;
  bool _dialogOpen = false;

  @override
  void initState() {
    super.initState();
    BrowserSettingsStore.instance.homeUrl.addListener(_onHomeUrlChanged);
    unawaited(_loadHomeUrl());
  }

  Future<void> _loadHomeUrl() async {
    final homeUrl = await BrowserSettingsStore.instance.load();
    if (!mounted) return;
    setState(() {
      _homeUrl = homeUrl;
      _homeUrlReady = true;
      if (_webViewController == null && !_addressFocus.hasFocus) {
        _addressController.text = homeUrl;
      }
    });
  }

  void _onHomeUrlChanged() {
    if (!mounted) return;
    setState(() => _homeUrl = BrowserSettingsStore.instance.homeUrl.value);
  }

  Future<bool> handleSystemBack() async {
    final controller = _webViewController;
    if (controller == null || !await controller.canGoBack()) return false;
    await controller.goBack();
    await _updateNavigation();
    return true;
  }

  static const _mediaScript = r'''
    (() => {
      if (window.__m3u8DownloaderInstalled) return;
      window.__m3u8DownloaderInstalled = true;
      const report = (value) => {
        if (typeof value !== 'string') return;
        const lower = value.toLowerCase();
        if (lower.includes('.m3u8') || lower.match(/\.mp4(?:$|[?#])/)) {
          window.flutter_inappwebview.callHandler('mediaLink', value, document.title);
        }
      };
      document.addEventListener('click', (event) => {
        const anchor = event.target.closest && event.target.closest('a');
        if (anchor) report(anchor.href);
      }, true);
      const scan = () => performance.getEntriesByType('resource').forEach(e => report(e.name));
      new PerformanceObserver(scan).observe({entryTypes: ['resource']});
      scan();
    })();
  ''';

  @override
  void dispose() {
    BrowserSettingsStore.instance.homeUrl.removeListener(_onHomeUrlChanged);
    _addressController.dispose();
    _addressFocus.dispose();
    super.dispose();
  }

  bool _isMediaUrl(String url) {
    final lower = url.toLowerCase();
    return lower.contains('.m3u8') ||
        RegExp(r'\.mp4(?:$|[?#])').hasMatch(lower);
  }

  Future<void> _updateNavigation() async {
    final controller = _webViewController;
    if (controller == null) return;
    final back = await controller.canGoBack();
    final forward = await controller.canGoForward();
    if (mounted) {
      setState(() {
        _canGoBack = back;
        _canGoForward = forward;
      });
    }
  }

  void _loadAddress() {
    var value = _addressController.text.trim();
    if (value.isEmpty) return;
    if (!value.startsWith(RegExp(r'https?://'))) value = 'https://$value';
    final uri = WebUri(value);
    _addressFocus.unfocus();
    _webViewController?.loadUrl(urlRequest: URLRequest(url: uri));
  }

  Future<void> _offerDownload(
    String rawUrl, {
    String? pageTitle,
    bool force = false,
  }) async {
    if ((!force && !_isMediaUrl(rawUrl)) ||
        _dialogOpen ||
        _handledUrls.contains(rawUrl)) {
      return;
    }
    _handledUrls.add(rawUrl);
    _dialogOpen = true;
    final uri = Uri.tryParse(rawUrl);
    final suggestedName = _suggestFileName(uri, pageTitle);
    final fileNameController = TextEditingController(text: suggestedName);

    try {
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          icon: const Icon(Icons.download_for_offline_outlined),
          title: const Text('确认下载'),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: TextEditingController(text: rawUrl),
                  readOnly: true,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: '视频链接',
                    prefixIcon: Icon(Icons.link),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: fileNameController,
                  autofocus: true,
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
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(context, true),
              icon: const Icon(Icons.download),
              label: const Text('确认下载'),
            ),
          ],
        ),
      );
      if (confirmed != true) {
        _handledUrls.remove(rawUrl);
        return;
      }
      final fileName = _normalizeFileName(fileNameController.text, rawUrl);
      final cookies = await CookieManager.instance().getCookies(
        url: WebUri(rawUrl),
      );
      final cookieHeader = cookies
          .map((cookie) => '${cookie.name}=${cookie.value}')
          .join('; ');
      await DownloadBridge.instance.startDownload(
        url: rawUrl,
        fileName: fileName,
        cookie: cookieHeader,
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('已加入后台下载：$fileName')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('无法启动下载：$error')));
      }
    } finally {
      fileNameController.dispose();
      _dialogOpen = false;
    }
  }

  String _suggestFileName(Uri? uri, String? title) {
    final queryName =
        uri?.queryParameters['filename'] ?? uri?.queryParameters['name'];
    var name = queryName ?? '';
    if (name.isEmpty && uri != null && uri.pathSegments.isNotEmpty) {
      name = Uri.decodeComponent(uri.pathSegments.last);
    }
    if (name.isEmpty || !name.contains('.')) name = title?.trim() ?? 'video';
    return _normalizeFileName(name, uri?.toString() ?? '');
  }

  String _normalizeFileName(String input, String url) {
    var name = input.trim().replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    if (name.isEmpty) name = 'video_${DateTime.now().millisecondsSinceEpoch}';
    final isM3u8 = url.toLowerCase().contains('.m3u8');
    final extension = isM3u8 ? '.ts' : '.mp4';
    name = name.replaceFirst(
      RegExp(r'\.(m3u8|mp4|ts)$', caseSensitive: false),
      '',
    );
    return '$name$extension';
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          Material(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 9),
              child: Row(
                children: [
                  IconButton(
                    tooltip: '后退',
                    onPressed: _canGoBack
                        ? () => _webViewController?.goBack()
                        : null,
                    icon: const Icon(Icons.arrow_back),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _addressController,
                      focusNode: _addressFocus,
                      onSubmitted: (_) => _loadAddress(),
                      keyboardType: TextInputType.url,
                      textInputAction: TextInputAction.go,
                      maxLines: 1,
                      decoration: InputDecoration(
                        hintText: '输入网址',
                        prefixIcon: const Icon(Icons.lock_outline, size: 17),
                        suffixIcon: IconButton(
                          tooltip: '打开',
                          onPressed: _loadAddress,
                          icon: const Icon(Icons.arrow_forward, size: 20),
                        ),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 10,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(22),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: Theme.of(context).colorScheme.surface,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '刷新',
                    onPressed: () => _webViewController?.reload(),
                    icon: const Icon(Icons.refresh),
                  ),
                  PopupMenuButton<String>(
                    tooltip: '更多',
                    icon: const Icon(Icons.more_vert),
                    onSelected: (value) {
                      if (value == 'forward' && _canGoForward) {
                        _webViewController?.goForward();
                      } else if (value == 'home') {
                        _webViewController?.loadUrl(
                          urlRequest: URLRequest(url: WebUri(_homeUrl)),
                        );
                      }
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: 'forward',
                        enabled: _canGoForward,
                        child: const ListTile(
                          leading: Icon(Icons.arrow_forward),
                          title: Text('前进'),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'home',
                        child: ListTile(
                          leading: Icon(Icons.home_outlined),
                          title: Text('主页'),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (_progress < 1)
            LinearProgressIndicator(value: _progress == 0 ? null : _progress),
          Expanded(
            child: !_homeUrlReady
                ? const Center(child: CircularProgressIndicator())
                : InAppWebView(
                    initialUrlRequest: URLRequest(url: WebUri(_homeUrl)),
                    initialSettings: InAppWebViewSettings(
                      javaScriptEnabled: true,
                      domStorageEnabled: true,
                      databaseEnabled: true,
                      useShouldOverrideUrlLoading: true,
                      useOnDownloadStart: true,
                      mediaPlaybackRequiresUserGesture: false,
                      mixedContentMode:
                          MixedContentMode.MIXED_CONTENT_COMPATIBILITY_MODE,
                    ),
                    onWebViewCreated: (controller) {
                      _webViewController = controller;
                      controller.addJavaScriptHandler(
                        handlerName: 'mediaLink',
                        callback: (arguments) {
                          if (arguments.isNotEmpty) {
                            unawaited(
                              _offerDownload(
                                arguments.first.toString(),
                                pageTitle: arguments.length > 1
                                    ? arguments[1].toString()
                                    : null,
                              ),
                            );
                          }
                        },
                      );
                    },
                    shouldOverrideUrlLoading: (controller, action) async {
                      final url = action.request.url?.toString();
                      if (url != null && _isMediaUrl(url)) {
                        unawaited(_offerDownload(url, pageTitle: _pageTitle));
                        return NavigationActionPolicy.CANCEL;
                      }
                      return NavigationActionPolicy.ALLOW;
                    },
                    onDownloadStartRequest: (controller, request) {
                      unawaited(
                        _offerDownload(
                          request.url.toString(),
                          pageTitle: request.suggestedFilename ?? _pageTitle,
                          force: true,
                        ),
                      );
                    },
                    onLoadResource: (controller, resource) {
                      final url = resource.url.toString();
                      if (_isMediaUrl(url)) {
                        unawaited(_offerDownload(url, pageTitle: _pageTitle));
                      }
                    },
                    onProgressChanged: (controller, progress) {
                      if (mounted) setState(() => _progress = progress / 100);
                    },
                    onTitleChanged: (controller, title) {
                      if (mounted && title != null) {
                        setState(() => _pageTitle = title);
                      }
                    },
                    onUpdateVisitedHistory: (controller, url, _) {
                      if (url != null && !_addressFocus.hasFocus) {
                        _addressController.text = url.toString();
                      }
                      unawaited(_updateNavigation());
                    },
                    onLoadStop: (controller, url) async {
                      await controller.evaluateJavascript(source: _mediaScript);
                      await _updateNavigation();
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class DownloadsView extends StatefulWidget {
  const DownloadsView({super.key, required this.onCountChanged});

  final ValueChanged<int> onCountChanged;

  @override
  State<DownloadsView> createState() => _DownloadsViewState();
}

class _DownloadsViewState extends State<DownloadsView>
    with SingleTickerProviderStateMixin {
  final Map<String, DownloadTask> _tasks = {};
  StreamSubscription<DownloadTask>? _subscription;
  late final TabController _tabController;
  int _tabIndex = 1;
  bool _editing = false;
  final Set<String> _selectedIds = {};
  bool _loading = true;

  bool handleSystemBack() {
    if (!_editing) return false;
    _exitEditing();
    return true;
  }

  @override
  void initState() {
    super.initState();
    _tabController =
        TabController(length: 2, initialIndex: _tabIndex, vsync: this)
          ..addListener(() {
            if (!_tabController.indexIsChanging && mounted) {
              setState(() {
                _tabIndex = _tabController.index;
                _editing = false;
                _selectedIds.clear();
              });
            }
          });
    _loadTasks();
    _subscription = DownloadBridge.instance.taskEvents.listen(_upsertTask);
  }

  Future<void> _loadTasks() async {
    try {
      final tasks = await DownloadBridge.instance.getTasks();
      if (!mounted) return;
      setState(() {
        for (final task in tasks) {
          _tasks[task.id] = task;
        }
        _loading = false;
      });
      widget.onCountChanged(_activeCount);
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _upsertTask(DownloadTask task) {
    if (!mounted) return;
    setState(() => _tasks[task.id] = task);
    widget.onCountChanged(_activeCount);
  }

  int get _activeCount => _tasks.values
      .where(
        (task) =>
            task.status == DownloadStatus.queued ||
            task.status == DownloadStatus.downloading,
      )
      .length;

  List<DownloadTask> get _visibleTasks => _tasks.values.where((task) {
    if (_tabIndex == 1) return task.status == DownloadStatus.completed;
    return task.status != DownloadStatus.completed;
  }).toList();

  void _toggleTask(DownloadTask task) {
    setState(() {
      if (!_selectedIds.add(task.id)) _selectedIds.remove(task.id);
    });
  }

  void _exitEditing() {
    setState(() {
      _editing = false;
      _selectedIds.clear();
    });
  }

  void _selectAll() {
    final visibleIds = _visibleTasks.map((task) => task.id).toSet();
    setState(() {
      if (_selectedIds.containsAll(visibleIds)) {
        _selectedIds.clear();
      } else {
        _selectedIds
          ..clear()
          ..addAll(visibleIds);
      }
    });
  }

  List<DownloadTask> get _selectedTasks =>
      _selectedIds.map((id) => _tasks[id]).whereType<DownloadTask>().toList();

  Future<void> _deleteSelected() async {
    final selected = _selectedTasks;
    if (selected.isEmpty) return;
    final deleteFiles = await showDialog<bool?>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('删除 ${selected.length} 个任务？'),
        content: const Text('“确认”只删除下载记录，本地视频文件会保留。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('同时删除文件'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('确认'),
          ),
        ],
      ),
    );
    if (deleteFiles == null) return;
    try {
      await DownloadBridge.instance.deleteTasks(
        selected,
        deleteFiles: deleteFiles,
      );
      if (!mounted) return;
      setState(() {
        for (final task in selected) {
          _tasks.remove(task.id);
        }
      });
      _exitEditing();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('删除失败：$error')));
      }
    }
  }

  Future<void> _uploadSelected() async {
    final selected = _selectedTasks;
    if (selected.isEmpty) return;
    await uploadTasksToSmb(context, selected);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tasks = _tasks.values.toList();
    final activeTasks =
        tasks
            .where(
              (task) =>
                  task.status == DownloadStatus.queued ||
                  task.status == DownloadStatus.downloading,
            )
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final unresolvedTasks =
        tasks
            .where(
              (task) =>
                  task.status == DownloadStatus.failed ||
                  task.status == DownloadStatus.cancelled,
            )
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final completedTasks =
        tasks.where((task) => task.status == DownloadStatus.completed).toList()
          ..sort((a, b) {
            final aTime = a.completedAt > 0 ? a.completedAt : a.createdAt;
            final bTime = b.completedAt > 0 ? b.completedAt : b.createdAt;
            return bTime.compareTo(aTime);
          });
    return DownloadsPageFrame(
      header: DownloadsHeader(
        controller: _tabController,
        activeCount: activeTasks.length,
        completedCount: completedTasks.length,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _DownloadSection(
                  tasks: activeTasks,
                  unresolvedTasks: unresolvedTasks,
                  emptyIcon: Icons.downloading,
                  emptyTitle: '没有正在下载的任务',
                  editing: _editing,
                  selectedIds: _selectedIds,
                  onToggle: _toggleTask,
                ),
                _DownloadSection(
                  tasks: completedTasks,
                  emptyIcon: Icons.video_library_outlined,
                  emptyTitle: '还没有已完成的视频',
                  editing: _editing,
                  selectedIds: _selectedIds,
                  onToggle: _toggleTask,
                ),
              ],
            ),
      bottomBar: _DownloadEditBar(
        editing: _editing,
        hasTasks: _visibleTasks.isNotEmpty,
        selectedCount: _selectedIds.length,
        allSelected:
            _visibleTasks.isNotEmpty &&
            _selectedIds.containsAll(_visibleTasks.map((task) => task.id)),
        onEdit: () => setState(() => _editing = true),
        onCancel: _exitEditing,
        onSelectAll: _selectAll,
        onDelete: _deleteSelected,
        onUpload: _uploadSelected,
      ),
    );
  }
}

class DownloadsPageFrame extends StatelessWidget {
  const DownloadsPageFrame({
    super.key,
    required this.header,
    required this.body,
    required this.bottomBar,
  });

  final Widget header;
  final Widget body;
  final Widget bottomBar;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.transparent,
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            header,
            Expanded(child: body),
            bottomBar,
          ],
        ),
      ),
    );
  }
}

class DownloadsHeader extends StatelessWidget {
  const DownloadsHeader({
    super.key,
    required this.controller,
    required this.activeCount,
    required this.completedCount,
  });

  final TabController controller;
  final int activeCount;
  final int completedCount;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      key: const ValueKey('downloads-header'),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 48,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '传输中心',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: colors.onSurface,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.4,
                    ),
                  ),
                ),
                Text(
                  '$activeCount 个进行中',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: colors.surfaceContainerHighest.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(17),
              border: Border.all(
                color: colors.outlineVariant.withValues(alpha: 0.55),
                width: 0.8,
              ),
            ),
            child: TabBar(
              key: const ValueKey('downloads-tabs'),
              controller: controller,
              dividerColor: Colors.transparent,
              indicator: BoxDecoration(
                color: colors.primary,
                borderRadius: BorderRadius.circular(13),
                boxShadow: [
                  BoxShadow(
                    color: colors.primary.withValues(alpha: 0.18),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              indicatorSize: TabBarIndicatorSize.tab,
              labelColor: Colors.white,
              unselectedLabelColor: colors.onSurfaceVariant,
              labelStyle: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
              tabs: [
                Tab(text: '进行中 $activeCount'),
                Tab(text: '已完成 $completedCount'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DownloadEditBar extends StatelessWidget {
  const _DownloadEditBar({
    required this.editing,
    required this.hasTasks,
    required this.selectedCount,
    required this.allSelected,
    required this.onEdit,
    required this.onCancel,
    required this.onSelectAll,
    required this.onDelete,
    required this.onUpload,
  });

  final bool editing;
  final bool hasTasks;
  final int selectedCount;
  final bool allSelected;
  final VoidCallback onEdit;
  final VoidCallback onCancel;
  final VoidCallback onSelectAll;
  final VoidCallback onDelete;
  final VoidCallback onUpload;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 7, 12, 7),
          child: editing
              ? Row(
                  children: [
                    TextButton(onPressed: onCancel, child: const Text('取消')),
                    TextButton(
                      onPressed: hasTasks ? onSelectAll : null,
                      child: Text(allSelected ? '取消全选' : '全选'),
                    ),
                    const Spacer(),
                    IconButton.filledTonal(
                      tooltip: '删除',
                      onPressed: selectedCount > 0 ? onDelete : null,
                      icon: const Icon(Icons.delete_outline),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: selectedCount > 0 ? onUpload : null,
                      icon: const Icon(Icons.cloud_upload_outlined),
                      label: Text('上传 $selectedCount'),
                    ),
                  ],
                )
              : Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.tonalIcon(
                    onPressed: hasTasks ? onEdit : null,
                    icon: const Icon(Icons.checklist_rounded),
                    label: const Text('管理任务'),
                  ),
                ),
        ),
      ),
    );
  }
}

class _DownloadSection extends StatelessWidget {
  const _DownloadSection({
    required this.tasks,
    required this.emptyIcon,
    required this.emptyTitle,
    required this.editing,
    required this.selectedIds,
    required this.onToggle,
    this.unresolvedTasks = const [],
  });

  final List<DownloadTask> tasks;
  final List<DownloadTask> unresolvedTasks;
  final IconData emptyIcon;
  final String emptyTitle;
  final bool editing;
  final Set<String> selectedIds;
  final ValueChanged<DownloadTask> onToggle;

  @override
  Widget build(BuildContext context) {
    if (tasks.isEmpty && unresolvedTasks.isEmpty) {
      return _EmptyDownloads(icon: emptyIcon, title: emptyTitle);
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 28),
      children: [
        ...tasks.map(
          (task) => _DownloadTile(
            task: task,
            editing: editing,
            selected: selectedIds.contains(task.id),
            onToggle: () => onToggle(task),
          ),
        ),
        if (unresolvedTasks.isNotEmpty) ...[
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _SectionHeading(
              title: '未完成记录',
              count: unresolvedTasks.length,
              icon: Icons.info_outline,
            ),
          ),
          const SizedBox(height: 4),
          ...unresolvedTasks.map(
            (task) => _DownloadTile(
              task: task,
              editing: editing,
              selected: selectedIds.contains(task.id),
              onToggle: () => onToggle(task),
            ),
          ),
        ],
      ],
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({
    required this.title,
    required this.count,
    required this.icon,
  });

  final String title;
  final int count;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 8),
        Text(title, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(width: 8),
        Text(
          '$count',
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: Theme.of(context).colorScheme.outline,
          ),
        ),
      ],
    );
  }
}

class _EmptyDownloads extends StatelessWidget {
  const _EmptyDownloads({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(26),
            ),
            child: Icon(
              icon,
              size: 36,
              color: Theme.of(context).colorScheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            '从浏览器捕获视频链接后，任务会显示在这里',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _DownloadTile extends StatelessWidget {
  const _DownloadTile({
    required this.task,
    required this.editing,
    required this.selected,
    required this.onToggle,
  });

  final DownloadTask task;
  final bool editing;
  final bool selected;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final active =
        task.status == DownloadStatus.queued ||
        task.status == DownloadStatus.downloading;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 5),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: editing ? onToggle : () => _showInfo(context),
        onLongPress: editing ? onToggle : () => _showActions(context),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 13, 8, 13),
          child: Row(
            children: [
              if (editing) ...[
                Icon(
                  selected ? Icons.check_circle : Icons.radio_button_unchecked,
                  color: selected
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.outline,
                  size: 30,
                ),
                const SizedBox(width: 10),
              ],
              if (task.status == DownloadStatus.completed)
                _VideoThumbnail(
                  task: task,
                  fallbackColor: _statusColor(context, task.status),
                )
              else
                _VideoFileIcon(color: _statusColor(context, task.status)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            task.fileName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        if (task.uploaded) ...[
                          const SizedBox(width: 5),
                          Tooltip(
                            message: '已上传',
                            child: Icon(
                              Icons.cloud_done,
                              size: 18,
                              color: Colors.green.shade400,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _secondaryText(task),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 13,
                      ),
                    ),
                    if (active) ...[
                      const SizedBox(height: 5),
                      LinearProgressIndicator(
                        minHeight: 4,
                        borderRadius: BorderRadius.circular(4),
                        value: task.progress <= 0 ? null : task.progress,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 6),
              if (!editing && task.status == DownloadStatus.completed)
                SizedBox(
                  width: 72,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        _formatFileSize(task.fileSize),
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      IconButton(
                        tooltip: '查看详情',
                        visualDensity: VisualDensity.compact,
                        constraints: const BoxConstraints.tightFor(
                          width: 36,
                          height: 34,
                        ),
                        onPressed: () => _showInfo(context),
                        icon: const Icon(Icons.info_outline),
                      ),
                    ],
                  ),
                )
              else if (!editing)
                IconButton(
                  tooltip: '查看详情',
                  onPressed: () => _showInfo(context),
                  icon: const Icon(Icons.info_outline),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _secondaryText(DownloadTask task) {
    if (task.status == DownloadStatus.completed) {
      return task.savedPath.isEmpty ? '视频文件 · 已完成' : task.savedPath;
    }
    if (task.status == DownloadStatus.downloading) {
      return '下载中 ${(task.progress * 100).round()}% · ${_shortUrl(task.url)}';
    }
    if (task.status == DownloadStatus.queued) {
      return '等待下载 · ${_shortUrl(task.url)}';
    }
    return '${_statusText(task)} · ${_shortUrl(task.url)}';
  }

  String _shortUrl(String value) {
    if (value.length <= 58) return value;
    return '${value.substring(0, 55)}...';
  }

  String _formatFileSize(int bytes) {
    if (bytes <= 0) return '--';
    const units = ['B', 'KB', 'MB', 'GB'];
    var value = bytes.toDouble();
    var unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }
    final digits = unit == 0 || value >= 100
        ? 0
        : unit == 1
        ? 1
        : 2;
    return '${value.toStringAsFixed(digits)} ${units[unit]}';
  }

  void _showInfo(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(task.fileName),
        content: SelectableText(
          '标题：${task.fileName}\n\n链接：${task.url}\n\n文件大小：${_formatFileSize(task.fileSize)}\n\n保存位置：${task.savedPath.isEmpty ? '尚未完成' : task.savedPath}\n\n上传状态：${task.uploaded ? '已上传' : '未上传'}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Future<void> _showActions(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.play_arrow),
              title: const Text('播放'),
              enabled: task.status == DownloadStatus.completed,
              onTap: task.status == DownloadStatus.completed
                  ? () {
                      Navigator.pop(sheetContext);
                      _play(context);
                    }
                  : null,
            ),
            ListTile(
              leading: const Icon(Icons.upload_outlined),
              title: Text(task.uploaded ? '重新上传' : '上传'),
              enabled: task.status == DownloadStatus.completed,
              onTap: task.status == DownloadStatus.completed
                  ? () {
                      Navigator.pop(sheetContext);
                      uploadTasksToSmb(context, [task]);
                    }
                  : null,
            ),
            if (task.status == DownloadStatus.queued ||
                task.status == DownloadStatus.downloading)
              ListTile(
                leading: const Icon(Icons.close),
                title: const Text('取消下载'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  DownloadBridge.instance.cancelDownload(task.id);
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _play(BuildContext context) async {
    try {
      await DownloadBridge.instance.openVideo(task);
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('无法播放：$error')));
    }
  }

  Color _statusColor(BuildContext context, DownloadStatus status) =>
      switch (status) {
        DownloadStatus.queued => Theme.of(context).colorScheme.secondary,
        DownloadStatus.downloading => Theme.of(context).colorScheme.primary,
        DownloadStatus.completed => Colors.green.shade700,
        DownloadStatus.failed => Theme.of(context).colorScheme.error,
        DownloadStatus.cancelled => Theme.of(context).colorScheme.outline,
      };

  String _statusText(DownloadTask task) => switch (task.status) {
    DownloadStatus.queued => '等待下载',
    DownloadStatus.downloading => '下载中 ${(task.progress * 100).round()}%',
    DownloadStatus.completed =>
      task.savedPath.isEmpty ? '下载完成' : '已保存到 ${task.savedPath}',
    DownloadStatus.failed => '下载失败：${task.message}',
    DownloadStatus.cancelled => '已取消',
  };
}

class _VideoFileIcon extends StatelessWidget {
  const _VideoFileIcon({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 48,
      decoration: BoxDecoration(
        color: color.withAlpha(38),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(Icons.movie_creation_outlined, color: color, size: 24),
    );
  }
}

class _VideoThumbnail extends StatefulWidget {
  const _VideoThumbnail({required this.task, required this.fallbackColor});

  final DownloadTask task;
  final Color fallbackColor;

  @override
  State<_VideoThumbnail> createState() => _VideoThumbnailState();
}

class _VideoThumbnailState extends State<_VideoThumbnail> {
  static final Map<String, Future<Uint8List?>> _cache = {};
  late Future<Uint8List?> _thumbnail;

  String get _cacheKey => widget.task.contentUri.isNotEmpty
      ? widget.task.contentUri
      : '${widget.task.id}:${widget.task.fileSize}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _VideoThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldKey = oldWidget.task.contentUri.isNotEmpty
        ? oldWidget.task.contentUri
        : '${oldWidget.task.id}:${oldWidget.task.fileSize}';
    if (oldKey != _cacheKey) _load();
  }

  void _load() {
    _thumbnail = _cache.putIfAbsent(
      _cacheKey,
      () => DownloadBridge.instance
          .getVideoThumbnail(widget.task)
          .catchError((_) => null),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 72,
      height: 48,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(13),
        child: FutureBuilder<Uint8List?>(
          future: _thumbnail,
          builder: (context, snapshot) {
            final bytes = snapshot.data;
            if (bytes == null || bytes.isEmpty) {
              return _VideoThumbnailFallback(color: widget.fallbackColor);
            }
            return Image.memory(
              bytes,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              filterQuality: FilterQuality.medium,
              errorBuilder: (_, _, _) =>
                  _VideoThumbnailFallback(color: widget.fallbackColor),
            );
          },
        ),
      ),
    );
  }
}

class _VideoThumbnailFallback extends StatelessWidget {
  const _VideoThumbnailFallback({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: color.withAlpha(38),
      child: Icon(Icons.movie_creation_outlined, color: color, size: 24),
    );
  }
}
