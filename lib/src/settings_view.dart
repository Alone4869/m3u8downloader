import 'package:flutter/material.dart';

import 'app_update.dart';
import 'download_bridge.dart';
import 'glass_surface.dart';
import 'smb_settings.dart';
import 'twitter_download_settings.dart';

class SettingsView extends StatefulWidget {
  const SettingsView({super.key});

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  SmbConfig? _smbConfig;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final config = await SmbSettingsStore.instance.load();
    if (mounted) {
      setState(() => _smbConfig = config);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            const _SettingsHero(),
            const _SettingsHeader('功能设置'),
            _SettingsCard(
              children: [
                ListTile(
                  leading: const _SettingsIcon(Icons.download_outlined),
                  title: const Text('下载与性能'),
                  subtitle: const Text('下载位置、X 视频线路和并发策略'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.push<void>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const DownloadSettingsPage(),
                    ),
                  ),
                ),
                const Divider(indent: 64),
                ListTile(
                  leading: const _SettingsIcon(Icons.dns_outlined),
                  title: const Text('SMB 上传'),
                  subtitle: Text(
                    _smbConfig?.isConfigured == true
                        ? '${_smbConfig!.host}/${_smbConfig!.share}'
                        : '连接 NAS 或局域网文件服务器',
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () async {
                    await Navigator.push<void>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const SmbSettingsPage(),
                      ),
                    );
                    _reload();
                  },
                ),
              ],
            ),
            const _SettingsHeader('应用'),
            _SettingsCard(
              children: [
                ListTile(
                  leading: const _SettingsIcon(Icons.info_outline_rounded),
                  title: const Text('关于应用'),
                  subtitle: const Text('版本更新、内容使用说明和开源许可'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.push<void>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const AboutSettingsPage(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 96),
          ],
        ),
      ),
    );
  }
}

class DownloadSettingsPage extends StatefulWidget {
  const DownloadSettingsPage({super.key});

  @override
  State<DownloadSettingsPage> createState() => _DownloadSettingsPageState();
}

class _DownloadSettingsPageState extends State<DownloadSettingsPage> {
  TwitterDownloadRoute _downloadRoute = TwitterDownloadRoute.direct;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final route = await TwitterDownloadSettingsStore.instance.load();
    if (mounted) {
      setState(() {
        _downloadRoute = route;
        _loading = false;
      });
    }
  }

  Future<void> _selectRoute(TwitterDownloadRoute route) async {
    if (route == _downloadRoute) return;
    await TwitterDownloadSettingsStore.instance.save(route);
    if (!mounted) return;
    setState(() => _downloadRoute = route);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('已切换为${route.title}')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('下载与性能')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
              children: [
                const _SettingsHeader('文件保存'),
                const _SettingsCard(
                  children: [
                    ListTile(
                      leading: _SettingsIcon(Icons.folder_outlined),
                      title: Text('下载位置'),
                      subtitle: Text('系统“下载/M3U8 Downloader”目录'),
                    ),
                  ],
                ),
                const _SettingsHeader('X 视频下载线路'),
                _SettingsCard(
                  children: [
                    for (
                      var index = 0;
                      index < TwitterDownloadRoute.values.length;
                      index++
                    ) ...[
                      if (index > 0) const Divider(indent: 64),
                      _DownloadRouteTile(
                        route: TwitterDownloadRoute.values[index],
                        selected:
                            TwitterDownloadRoute.values[index] ==
                            _downloadRoute,
                        onTap: () =>
                            _selectRoute(TwitterDownloadRoute.values[index]),
                      ),
                    ],
                  ],
                ),
                const _SettingsHeader('性能'),
                const _SettingsCard(
                  children: [
                    ListTile(
                      leading: _SettingsIcon(Icons.bolt_outlined),
                      title: Text('并发下载'),
                      subtitle: Text('单个任务自动使用最多 6 路连接，兼顾速度与稳定性'),
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}

class _DownloadRouteTile extends StatelessWidget {
  const _DownloadRouteTile({
    required this.route,
    required this.selected,
    required this.onTap,
  });

  final TwitterDownloadRoute route;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ListTile(
      leading: _SettingsIcon(
        route == TwitterDownloadRoute.direct
            ? Icons.speed_rounded
            : Icons.cloud_download_outlined,
      ),
      title: Text(route.title),
      subtitle: Text(route.description),
      trailing: Icon(
        selected ? Icons.check_circle_rounded : Icons.circle_outlined,
        color: selected ? colors.primary : colors.outline,
      ),
      selected: selected,
      onTap: onTap,
    );
  }
}

class AboutSettingsPage extends StatefulWidget {
  const AboutSettingsPage({super.key});

  @override
  State<AboutSettingsPage> createState() => _AboutSettingsPageState();
}

class _AboutSettingsPageState extends State<AboutSettingsPage> {
  AppVersion? _appVersion;
  bool _checkingUpdate = false;

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    final version = await AppUpdateService().getCurrentVersion();
    if (mounted) setState(() => _appVersion = version);
  }

  Future<void> _checkForUpdates() async {
    if (_checkingUpdate) return;
    setState(() => _checkingUpdate = true);
    final service = AppUpdateService();
    try {
      final current = _appVersion ?? await service.getCurrentVersion();
      final release = await service.fetchLatestRelease(
        supportedAbis: current.supportedAbis,
      );
      if (!mounted) return;
      if (release.isNewerThan(current)) {
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            icon: const Icon(Icons.system_update_rounded),
            title: Text('发现新版本 ${release.version}'),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320),
              child: SingleChildScrollView(
                child: Text(
                  release.notes.isEmpty ? release.title : release.notes,
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('稍后'),
              ),
              FilledButton.icon(
                onPressed: () async {
                  Navigator.pop(dialogContext);
                  await service.openRelease(release);
                },
                icon: const Icon(Icons.download_rounded),
                label: const Text('下载更新'),
              ),
            ],
          ),
        );
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('已是最新版本 ${current.version}')));
      }
    } catch (error) {
      if (!mounted) return;
      final message = error is UpdateNotConfiguredException
          ? '当前构建未配置公开更新仓库'
          : '检查更新失败：$error';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      service.close();
      if (mounted) setState(() => _checkingUpdate = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('关于应用')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          const _SettingsHeader('版本'),
          _SettingsCard(
            children: [
              ListTile(
                leading: const _SettingsIcon(Icons.system_update_outlined),
                title: const Text('检查更新'),
                subtitle: Text(
                  _appVersion == null
                      ? '正在读取当前版本'
                      : '当前版本 ${_appVersion!.display}',
                ),
                trailing: _checkingUpdate
                    ? const SizedBox.square(
                        dimension: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.chevron_right_rounded),
                onTap: _checkingUpdate ? null : _checkForUpdates,
              ),
              const Divider(indent: 64),
              const ListTile(
                leading: _SettingsIcon(Icons.install_mobile_outlined),
                title: Text('升级与数据'),
                subtitle: Text('安装新版时直接覆盖安装，可保留任务记录和应用设置'),
              ),
            ],
          ),
          const _SettingsHeader('使用与许可'),
          _SettingsCard(
            children: [
              const ListTile(
                leading: _SettingsIcon(Icons.verified_user_outlined),
                title: Text('内容使用说明'),
                subtitle: Text('仅处理你拥有权利或已获授权下载、保存和上传的内容'),
              ),
              const Divider(indent: 64),
              ListTile(
                leading: const _SettingsIcon(Icons.code_rounded),
                title: const Text('开源软件许可'),
                subtitle: const Text('查看本应用及所用第三方软件的许可信息'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => showLicensePage(
                  context: context,
                  applicationName: 'M3U8 视频下载器',
                  applicationVersion: _appVersion?.display,
                  applicationLegalese: 'Copyright 2026 Alone4869 · MIT License',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SettingsHero extends StatelessWidget {
  const _SettingsHero();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AppSurface(
      elevated: true,
      borderRadius: 22,
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: colors.primary,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: colors.primary.withValues(alpha: 0.24),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: const Icon(Icons.movie_filter_rounded, color: Colors.white),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'M3U8 Downloader',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: colors.onSurface,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '快速捕获、下载并归档视频',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colors.onSurfaceVariant,
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

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return AppSurface(borderRadius: 20, child: Column(children: children));
  }
}

class _SettingsIcon extends StatelessWidget {
  const _SettingsIcon(this.icon);

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: colors.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: colors.onPrimaryContainer, size: 21),
    );
  }
}

class _SettingsHeader extends StatelessWidget {
  const _SettingsHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 24, 4, 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class SmbSettingsPage extends StatefulWidget {
  const SmbSettingsPage({super.key});

  @override
  State<SmbSettingsPage> createState() => _SmbSettingsPageState();
}

class _SmbSettingsPageState extends State<SmbSettingsPage> {
  final _formKey = GlobalKey<FormState>();
  final _host = TextEditingController();
  final _port = TextEditingController(text: '445');
  final _share = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _domain = TextEditingController();
  bool _loading = true;
  bool _testing = false;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final config = await SmbSettingsStore.instance.load();
    _host.text = config.host;
    _port.text = '${config.port}';
    _share.text = config.share;
    _username.text = config.username;
    _password.text = config.password;
    _domain.text = config.domain;
    if (mounted) setState(() => _loading = false);
  }

  SmbConfig _config() => SmbConfig(
    host: _host.text,
    port: int.tryParse(_port.text) ?? 445,
    share: _share.text,
    username: _username.text,
    password: _password.text,
    domain: _domain.text,
  );

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    await SmbSettingsStore.instance.save(_config());
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('SMB 配置已保存')));
  }

  Future<void> _test() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _testing = true);
    try {
      await DownloadBridge.instance.testSmb(_config().toMap());
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('SMB 连接成功')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('连接失败：$error')));
      }
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  void dispose() {
    _host.dispose();
    _port.dispose();
    _share.dispose();
    _username.dispose();
    _password.dispose();
    _domain.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('SMB 配置')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                children: [
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.cloud_sync_outlined,
                          color: Theme.of(
                            context,
                          ).colorScheme.onPrimaryContainer,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            '连接 NAS 或局域网文件服务器。支持 SMB 2/3 多连接上传；密码仅保存在设备安全存储中。',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onPrimaryContainer,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const _SettingsHeader('服务器'),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                flex: 3,
                                child: TextFormField(
                                  controller: _host,
                                  decoration: const InputDecoration(
                                    labelText: '服务器地址',
                                    hintText: '192.168.1.10',
                                    prefixIcon: Icon(Icons.dns_outlined),
                                  ),
                                  validator: _required,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                flex: 2,
                                child: TextFormField(
                                  controller: _port,
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                    labelText: '端口',
                                    hintText: '445',
                                  ),
                                  validator: _required,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: _share,
                            decoration: const InputDecoration(
                              labelText: '共享名称',
                              hintText: 'Videos',
                              prefixIcon: Icon(Icons.folder_shared_outlined),
                            ),
                            validator: _required,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const _SettingsHeader('登录凭据'),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          TextFormField(
                            controller: _username,
                            decoration: const InputDecoration(
                              labelText: '用户名',
                              prefixIcon: Icon(Icons.person_outline_rounded),
                            ),
                            validator: _required,
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: _password,
                            obscureText: _obscurePassword,
                            decoration: InputDecoration(
                              labelText: '密码',
                              prefixIcon: const Icon(Icons.key_outlined),
                              suffixIcon: IconButton(
                                tooltip: _obscurePassword ? '显示密码' : '隐藏密码',
                                onPressed: () => setState(
                                  () => _obscurePassword = !_obscurePassword,
                                ),
                                icon: Icon(
                                  _obscurePassword
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: _domain,
                            decoration: const InputDecoration(
                              labelText: '域（可选）',
                              prefixIcon: Icon(Icons.domain_outlined),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _testing ? null : _test,
                          icon: _testing
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.network_check),
                          label: const Text('测试连接'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _save,
                          icon: const Icon(Icons.save_outlined),
                          label: const Text('保存'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
    );
  }

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? '不能为空' : null;
}
