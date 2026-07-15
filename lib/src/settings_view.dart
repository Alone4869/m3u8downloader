import 'package:flutter/material.dart';

import 'download_bridge.dart';
import 'smb_settings.dart';

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
    if (mounted) setState(() => _smbConfig = config);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          const _SettingsHero(),
          const _SettingsHeader('通用设置'),
          const _SettingsCard(
            children: [
              ListTile(
                leading: _SettingsIcon(Icons.folder_outlined),
                title: Text('下载位置'),
                subtitle: Text('下载/M3U8 Downloader'),
              ),
              Divider(indent: 64),
              ListTile(
                leading: _SettingsIcon(Icons.bolt_outlined),
                title: Text('高速下载'),
                subtitle: Text('每个任务最多 6 路连接'),
              ),
              Divider(indent: 64),
              ListTile(
                leading: _SettingsIcon(Icons.shield_outlined),
                title: Text('数据保护'),
                subtitle: Text('升级请直接覆盖安装；任务记录与非敏感设置跟随系统备份'),
              ),
            ],
          ),
          const _SettingsHeader('上传设置'),
          _SettingsCard(
            children: [
              ListTile(
                leading: const _SettingsIcon(Icons.dns_outlined),
                title: const Text('SMB 服务器'),
                subtitle: Text(
                  _smbConfig?.isConfigured == true
                      ? '${_smbConfig!.host}/${_smbConfig!.share}'
                      : '尚未配置远端存储',
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () async {
                  await Navigator.push<void>(
                    context,
                    MaterialPageRoute(builder: (_) => const SmbSettingsPage()),
                  );
                  _reload();
                },
              ),
              const Divider(indent: 64),
              const ListTile(
                leading: _SettingsIcon(Icons.speed_rounded),
                title: Text('上传引擎'),
                subtitle: Text('SMB 2/3 · 1MB 传输窗口 · 实时测速'),
              ),
            ],
          ),
          const _SettingsHeader('关于'),
          const _SettingsCard(
            children: [
              ListTile(
                leading: _SettingsIcon(Icons.info_outline_rounded),
                title: Text('M3U8 视频下载器'),
                subtitle: Text('版本 1.0.0'),
              ),
              Divider(indent: 64),
              ListTile(
                leading: _SettingsIcon(Icons.verified_user_outlined),
                title: Text('内容与隐私'),
                subtitle: Text('请仅处理你有权下载和上传的内容'),
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
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [colors.primaryContainer, colors.tertiaryContainer],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: colors.surface.withAlpha(210),
              borderRadius: BorderRadius.circular(17),
            ),
            child: Icon(Icons.movie_filter_rounded, color: colors.primary),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'M3U8 Downloader',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: colors.onPrimaryContainer,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '快速捕获、下载并归档视频',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colors.onPrimaryContainer.withAlpha(190),
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
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
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
          color: Theme.of(context).colorScheme.primary,
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
                            '连接局域网 NAS 或文件服务器。凭据仅保存在设备安全存储中。',
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
