import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'glass_surface.dart';
import 'jellyfin_client.dart';
import 'jellyfin_home_view.dart';
import 'jellyfin_theme.dart';
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

  Future<void> _openSheet({
    ServerConfig? initial,
    bool openAfterSave = true,
  }) async {
    final result = await showModalBottomSheet<ServerConfig>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          _AddServerSheet(clientFactory: _clientFactory, initial: initial),
    );
    if (result == null || !mounted) return;
    await _store.save(result);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('已连接 ${result.name}')));
    await _reload();
    if (!openAfterSave || !mounted) return;
    final client = _clientFactory()
      ..configure(
        baseUrl: result.url,
        accessToken: result.accessToken,
        userId: result.userId,
      );
    final tokenExpired = await Navigator.push<bool>(
      context,
      jellyfinRoute<bool>(
        builder: (_) => JellyfinHomeView(config: result, client: client),
      ),
    );
    if (tokenExpired == true && mounted) {
      await _store.save(result.copyWith(accessToken: ''));
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('登录已过期，请重新连接')));
    }
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
      jellyfinRoute<bool>(
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
                  onEdit: () =>
                      _openSheet(initial: server, openAfterSave: false),
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
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
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
    required this.onEdit,
    required this.onDelete,
  });

  final ServerConfig server;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  Future<void> _showMenu(BuildContext context, Offset pressPosition) async {
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(pressPosition.dx, pressPosition.dy, 1, 1),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem(
          value: 'edit',
          child: Row(
            children: [
              Icon(Icons.edit_outlined, size: 20),
              const SizedBox(width: 12),
              const Text('编辑'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(
                Icons.delete_outline,
                size: 20,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(width: 12),
              Text(
                '删除',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ),
        ),
      ],
    );
    switch (action) {
      case 'edit':
        onEdit();
      case 'delete':
        onDelete();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AppSurface(
      borderRadius: 22,
      elevated: true,
      child: GestureDetector(
        onLongPressStart: (details) =>
            _showMenu(context, details.globalPosition),
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
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
              ],
            ),
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
    final color = switch (type) {
      ServerType.jellyfin => const Color(0xFF17171C),
      ServerType.emby => const Color(0xFF17171C),
      ServerType.smb => const Color(0xFFF59E0B),
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
      child: switch (type) {
        ServerType.jellyfin => Padding(
          padding: const EdgeInsets.all(11),
          child: SvgPicture.asset(
            'assets/logos/jellyfin.svg',
            fit: BoxFit.contain,
          ),
        ),
        ServerType.emby => Padding(
          padding: const EdgeInsets.all(11),
          child: SvgPicture.asset('assets/logos/emby.svg', fit: BoxFit.contain),
        ),
        ServerType.smb => const Icon(
          Icons.folder_rounded,
          color: Colors.white,
          size: 27,
        ),
      },
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
            child: Icon(
              Icons.dns_outlined,
              size: 40,
              color: colors.onPrimaryContainer,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            '添加你的第一个服务器',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
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
  String? _error;

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
    setState(() {
      _connecting = true;
      _error = null;
    });
    try {
      final client = widget.clientFactory();
      await client.login(
        baseUrl: _url.text.trim(),
        username: _username.text.trim(),
        password: _password.text,
      );
      if (!mounted) return;
      final id =
          widget.initial?.id ??
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
      setState(() {
        _error = error is JellyfinException ? error.message : '连接失败：$error';
      });
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
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
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
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 16),
          for (final type in ServerType.values) ...[
            _ProtocolOption(
              type: type,
              enabled: type == ServerType.jellyfin,
              onTap: () => setState(() {
                _type = type;
                _error = null;
              }),
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
            if (_error != null) ...[
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: colors.error, fontSize: 13),
              ),
              const SizedBox(height: 10),
            ],
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
              '密码仅用于本次登录验证',
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: colors.onSurfaceVariant),
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
      color: enabled
          ? colors.surfaceContainerLow
          : colors.surfaceContainerHighest.withValues(alpha: 0.5),
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
