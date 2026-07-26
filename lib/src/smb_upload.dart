import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'download_bridge.dart';
import 'glass_surface.dart';
import 'settings_view.dart';
import 'smb_settings.dart';

Future<void> uploadTasksToSmb(
  BuildContext context,
  List<DownloadTask> tasks,
) async {
  final completed = tasks
      .where((task) => task.status == DownloadStatus.completed)
      .toList();
  if (completed.isEmpty) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('请选择已完成的任务')));
    return;
  }

  try {
    final hasAccess = await DownloadBridge.instance.ensureLocalMediaAccess(
      completed,
    );
    if (!hasAccess) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('需要允许访问视频，才能读取并上传下载目录中的文件')));
      return;
    }
  } catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('无法读取本地视频：$error')));
    return;
  }

  var config = await SmbSettingsStore.instance.load();
  if (!context.mounted) return;
  if (!config.isConfigured) {
    final configure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('尚未配置 SMB'),
        content: const Text('请先填写 SMB 服务器和共享信息。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('去设置'),
          ),
        ],
      ),
    );
    if (configure != true || !context.mounted) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => const SmbSettingsPage()),
    );
    config = await SmbSettingsStore.instance.load();
    if (!config.isConfigured || !context.mounted) return;
  }

  final folder = await showDialog<String>(
    context: context,
    builder: (context) => _SmbFolderPicker(config: config),
  );
  if (folder == null || !context.mounted) return;

  final uploadProgress = ValueNotifier<SmbUploadProgress?>(null);
  final progressSubscription = DownloadBridge.instance.smbUploadProgress.listen(
    (progress) => uploadProgress.value = progress,
  );
  unawaited(
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _UploadProgressDialog(
        progress: uploadProgress,
        fileCount: completed.length,
      ),
    ),
  );
  try {
    await DownloadBridge.instance.uploadToSmb(
      config.toMap(),
      folder,
      completed,
    );
    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('已上传 ${completed.length} 个文件')));
  } catch (error) {
    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('上传失败：$error')));
  } finally {
    await progressSubscription.cancel();
    uploadProgress.dispose();
  }
}

class _UploadProgressDialog extends StatelessWidget {
  const _UploadProgressDialog({
    required this.progress,
    required this.fileCount,
  });

  final ValueListenable<SmbUploadProgress?> progress;
  final int fileCount;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Dialog(
      elevation: 0,
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
      child: AppSurface(
        borderRadius: 24,
        elevated: true,
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
        child: SizedBox(
          width: 390,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '正在上传到 SMB',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 18),
              ValueListenableBuilder<SmbUploadProgress?>(
                valueListenable: progress,
                builder: (context, value, _) {
                  final speed = value == null
                      ? '正在建立高速连接…'
                      : '${_formatRate(value.bytesPerSecond)} · '
                            '${value.fileIndex + 1}/${value.fileCount}';
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              color: colors.primaryContainer,
                              borderRadius: BorderRadius.circular(17),
                            ),
                            child: Icon(
                              Icons.cloud_upload_outlined,
                              color: colors.onPrimaryContainer,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  value?.fileName ?? '准备上传 $fileCount 个文件',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.titleSmall
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  speed,
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(
                                        color: colors.onSurfaceVariant,
                                      ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  value?.protocol ?? '正在协商 SMB 版本…',
                                  style: Theme.of(context).textTheme.labelMedium
                                      ?.copyWith(
                                        color: value == null
                                            ? colors.onSurfaceVariant
                                            : colors.primary,
                                        fontWeight: FontWeight.w700,
                                      ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      LinearProgressIndicator(
                        value: value?.progress,
                        minHeight: 8,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            value == null
                                ? '协商 SMB 2/3 连接'
                                : '${_formatBytes(value.uploadedBytes)} / ${_formatBytes(value.totalBytes)}',
                            style: Theme.of(context).textTheme.labelMedium
                                ?.copyWith(color: colors.onSurfaceVariant),
                          ),
                          Text(
                            value?.progress == null
                                ? '—'
                                : '${(value!.progress! * 100).round()}%',
                            style: Theme.of(context).textTheme.labelLarge
                                ?.copyWith(
                                  color: colors.primary,
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                        ],
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatRate(double bytesPerSecond) {
    if (bytesPerSecond <= 0) return '测速中…';
    return '${(bytesPerSecond / 1024 / 1024).toStringAsFixed(1)} MB/s';
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '—';
    final megabytes = bytes / 1024 / 1024;
    if (megabytes < 1024) return '${megabytes.toStringAsFixed(1)} MB';
    return '${(megabytes / 1024).toStringAsFixed(2)} GB';
  }
}

class _SmbFolderPicker extends StatefulWidget {
  const _SmbFolderPicker({required this.config});

  final SmbConfig config;

  @override
  State<_SmbFolderPicker> createState() => _SmbFolderPickerState();
}

class _SmbFolderLocation {
  const _SmbFolderLocation({required this.name, required this.url});

  final String name;
  final String url;
}

class _SmbFolderPickerState extends State<_SmbFolderPicker> {
  List<SmbFolderEntry> _folders = const [];
  final List<_SmbFolderLocation> _locations = [];
  bool _loading = true;
  String? _error;
  int _loadGeneration = 0;

  _SmbFolderLocation get _currentLocation => _locations.last;

  @override
  void initState() {
    super.initState();
    _locations.add(_SmbFolderLocation(name: widget.config.share, url: ''));
    _loadCurrentFolder();
  }

  Future<void> _loadCurrentFolder() async {
    final generation = ++_loadGeneration;
    final path = _currentLocation.url;
    setState(() {
      _loading = true;
      _error = null;
      _folders = const [];
    });
    try {
      final folders = await DownloadBridge.instance.listSmbFolders(
        widget.config.toMap(),
        path,
      );
      if (mounted && generation == _loadGeneration) {
        setState(() => _folders = folders);
      }
    } catch (error) {
      if (mounted && generation == _loadGeneration) {
        setState(() => _error = '$error');
      }
    } finally {
      if (mounted && generation == _loadGeneration) {
        setState(() => _loading = false);
      }
    }
  }

  void _openFolder(SmbFolderEntry folder) {
    setState(() {
      _locations.add(_SmbFolderLocation(name: folder.name, url: folder.url));
    });
    _loadCurrentFolder();
  }

  void _goUp() {
    if (_locations.length <= 1 || _loading) return;
    setState(() => _locations.removeLast());
    _loadCurrentFolder();
  }

  String get _displayPath =>
      _locations.map((location) => location.name).join(' / ');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final screenHeight = MediaQuery.sizeOf(context).height;
    final visibleRows = _loading || _error != null
        ? 2
        : _folders.length.clamp(2, 6);
    final preferredHeight = (252.0 + visibleRows * 58)
        .clamp(390.0, 580.0)
        .toDouble();
    final maxDialogHeight = (screenHeight * 0.72)
        .clamp(390.0, 580.0)
        .toDouble();
    final dialogHeight = math.min(preferredHeight, maxDialogHeight);

    return Dialog(
      elevation: 0,
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: AppSurface(
        borderRadius: 24,
        elevated: true,
        child: SizedBox(
          width: 440,
          height: dialogHeight,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 12, 14),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: colors.primaryContainer,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        Icons.drive_folder_upload_outlined,
                        color: colors.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '选择上传文件夹',
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'SMB · ${widget.config.share}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: '关闭',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Material(
                  color: colors.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(16),
                  clipBehavior: Clip.antiAlias,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 6, 8),
                    child: Row(
                      children: [
                        if (_locations.length > 1)
                          IconButton.filledTonal(
                            tooltip: '返回上一级',
                            onPressed: _loading ? null : _goUp,
                            icon: const Icon(Icons.arrow_back),
                          )
                        else
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: colors.surfaceContainerLow,
                              borderRadius: BorderRadius.circular(13),
                            ),
                            child: Icon(
                              Icons.storage_outlined,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _currentLocation.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _locations.length == 1 ? '共享根目录' : _displayPath,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: '刷新',
                          onPressed: _loading ? null : _loadCurrentFolder,
                          icon: const Icon(Icons.refresh),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 8),
                child: Row(
                  children: [
                    Icon(
                      Icons.filter_alt_outlined,
                      size: 16,
                      color: colors.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '仅显示文件夹，不读取文件内容',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Material(
                    color: colors.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(16),
                    clipBehavior: Clip.antiAlias,
                    child: _buildFolderList(context),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Divider(height: 1, color: colors.outlineVariant),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Row(
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('取消'),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _loading || _error != null
                            ? null
                            : () =>
                                  Navigator.pop(context, _currentLocation.url),
                        icon: const Icon(Icons.check),
                        label: const Text('选择此文件夹'),
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

  Widget _buildFolderList(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off_outlined, size: 32, color: colors.error),
              const SizedBox(height: 10),
              Text(
                '无法读取此文件夹',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _error!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _loadCurrentFolder,
                icon: const Icon(Icons.refresh),
                label: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }
    if (_folders.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.folder_off_outlined,
                size: 36,
                color: colors.onSurfaceVariant,
              ),
              const SizedBox(height: 10),
              Text(
                '没有子文件夹',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '仍可选择当前文件夹作为上传位置',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: _folders.length,
      separatorBuilder: (_, _) => Divider(
        height: 1,
        indent: 62,
        color: colors.outlineVariant.withValues(alpha: 0.55),
      ),
      itemBuilder: (context, index) {
        final folder = _folders[index];
        return ListTile(
          minTileHeight: 56,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
          leading: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: colors.secondaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.folder_outlined,
              size: 22,
              color: colors.onSecondaryContainer,
            ),
          ),
          title: Text(
            folder.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          trailing: Icon(Icons.chevron_right, color: colors.onSurfaceVariant),
          onTap: () => _openFolder(folder),
        );
      },
    );
  }
}
