import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'download_bridge.dart';
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
    return AlertDialog(
      title: const Text('正在上传到 SMB'),
      content: SizedBox(
        width: 390,
        child: ValueListenableBuilder<SmbUploadProgress?>(
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
                                ?.copyWith(color: colors.onSurfaceVariant),
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
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      value?.progress == null
                          ? '—'
                          : '${(value!.progress! * 100).round()}%',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
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

class _SmbFolderPickerState extends State<_SmbFolderPicker> {
  List<SmbFolderEntry> _folders = const [];
  String? _selectedUrl;
  String? _selectedName;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final folders = await DownloadBridge.instance.listSmbFolders(
        widget.config.toMap(),
        '',
      );
      if (mounted) setState(() => _folders = folders);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('选择上传文件夹'),
      content: SizedBox(
        width: 480,
        height: 420,
        child: Column(
          children: [
            Row(
              children: [
                const Icon(Icons.storage_outlined),
                const SizedBox(width: 12),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: '${widget.config.share}\n'),
                        TextSpan(
                          text: '点击文件夹即可选择，不会读取其内容',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
                IconButton(
                  tooltip: '刷新',
                  onPressed: _load,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            const Divider(height: 1),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                  ? Center(child: Text('读取失败：$_error'))
                  : ListView.builder(
                      itemCount: _folders.length + 1,
                      itemBuilder: (context, index) {
                        final isRoot = index == 0;
                        final folder = isRoot ? null : _folders[index - 1];
                        final url = folder?.url ?? '';
                        final selected = _selectedUrl == url;
                        return ListTile(
                          selected: selected,
                          leading: Icon(
                            isRoot ? Icons.storage_outlined : Icons.folder,
                          ),
                          title: Text(folder?.name ?? '共享根目录'),
                          subtitle: isRoot ? Text(widget.config.share) : null,
                          trailing: Icon(
                            selected
                                ? Icons.check_circle
                                : Icons.radio_button_unchecked,
                            color: selected
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context).colorScheme.outline,
                          ),
                          onTap: () => setState(() {
                            _selectedUrl = url;
                            _selectedName = folder?.name ?? '共享根目录';
                          }),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton.icon(
          onPressed: _loading || _error != null || _selectedUrl == null
              ? null
              : () => Navigator.pop(context, _selectedUrl),
          icon: const Icon(Icons.drive_folder_upload_outlined),
          label: Text(
            _selectedName == null ? '请选择文件夹' : '上传到 $_selectedName',
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
