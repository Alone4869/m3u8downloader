import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/services.dart';

enum DownloadStatus { queued, downloading, completed, failed, cancelled }

class DownloadTask {
  const DownloadTask({
    required this.id,
    required this.url,
    required this.fileName,
    required this.status,
    required this.progress,
    this.message = '',
    this.savedPath = '',
    this.contentUri = '',
    this.createdAt = 0,
    this.completedAt = 0,
    this.fileSize = 0,
    this.uploaded = false,
  });

  factory DownloadTask.fromMap(Map<Object?, Object?> map) {
    final statusName = map['status'] as String? ?? 'queued';
    return DownloadTask(
      id: map['id'] as String? ?? '',
      url: map['url'] as String? ?? '',
      fileName: map['fileName'] as String? ?? 'video.ts',
      status: DownloadStatus.values.firstWhere(
        (status) => status.name == statusName,
        orElse: () => DownloadStatus.queued,
      ),
      progress: (map['progress'] as num?)?.toDouble() ?? 0,
      message: map['message'] as String? ?? '',
      savedPath: map['savedPath'] as String? ?? '',
      contentUri: map['contentUri'] as String? ?? '',
      createdAt: (map['createdAt'] as num?)?.toInt() ?? 0,
      completedAt: (map['completedAt'] as num?)?.toInt() ?? 0,
      fileSize: (map['fileSize'] as num?)?.toInt() ?? 0,
      uploaded: map['uploaded'] as bool? ?? false,
    );
  }

  final String id;
  final String url;
  final String fileName;
  final DownloadStatus status;
  final double progress;
  final String message;
  final String savedPath;
  final String contentUri;
  final int createdAt;
  final int completedAt;
  final int fileSize;
  final bool uploaded;
}

class SmbFolderEntry {
  const SmbFolderEntry({required this.name, required this.url});

  factory SmbFolderEntry.fromMap(Map<Object?, Object?> map) => SmbFolderEntry(
    name: map['name'] as String? ?? '',
    url: map['url'] as String? ?? '',
  );

  final String name;
  final String url;
}

class SmbUploadProgress {
  const SmbUploadProgress({
    required this.fileIndex,
    required this.fileCount,
    required this.fileName,
    required this.uploadedBytes,
    required this.totalBytes,
    required this.bytesPerSecond,
  });

  factory SmbUploadProgress.fromMap(Map<Object?, Object?> map) =>
      SmbUploadProgress(
        fileIndex: (map['fileIndex'] as num?)?.toInt() ?? 0,
        fileCount: (map['fileCount'] as num?)?.toInt() ?? 1,
        fileName: map['fileName'] as String? ?? '',
        uploadedBytes: (map['uploadedBytes'] as num?)?.toInt() ?? 0,
        totalBytes: (map['totalBytes'] as num?)?.toInt() ?? 0,
        bytesPerSecond: (map['bytesPerSecond'] as num?)?.toDouble() ?? 0,
      );

  final int fileIndex;
  final int fileCount;
  final String fileName;
  final int uploadedBytes;
  final int totalBytes;
  final double bytesPerSecond;

  double? get progress =>
      totalBytes > 0 ? (uploadedBytes / totalBytes).clamp(0.0, 1.0) : null;
}

class DownloadBridge {
  DownloadBridge._();

  static final DownloadBridge instance = DownloadBridge._();
  static const _methods = MethodChannel('m3u8_downloader/methods');
  static const _events = EventChannel('m3u8_downloader/events');
  static const _uploadEvents = EventChannel('m3u8_downloader/upload_events');

  Stream<DownloadTask>? _taskEvents;
  Stream<SmbUploadProgress>? _smbUploadProgress;

  Stream<DownloadTask> get taskEvents =>
      _taskEvents ??= _events.receiveBroadcastStream().map(
        (event) =>
            DownloadTask.fromMap(Map<Object?, Object?>.from(event as Map)),
      );

  Stream<SmbUploadProgress> get smbUploadProgress =>
      _smbUploadProgress ??= _uploadEvents.receiveBroadcastStream().map(
        (event) =>
            SmbUploadProgress.fromMap(Map<Object?, Object?>.from(event as Map)),
      );

  Future<List<DownloadTask>> getTasks() async {
    final raw =
        await _methods.invokeListMethod<Object?>('getTasks') ?? const [];
    return raw
        .map(
          (item) =>
              DownloadTask.fromMap(Map<Object?, Object?>.from(item! as Map)),
        )
        .toList();
  }

  Future<void> startDownload({
    required String url,
    required String fileName,
    String cookie = '',
  }) {
    return _methods.invokeMethod('startDownload', {
      'url': url,
      'fileName': fileName,
      'cookie': cookie,
    });
  }

  Future<void> cancelDownload(String id) {
    return _methods.invokeMethod('cancelDownload', {'id': id});
  }

  Future<bool> ensureLocalMediaAccess(List<DownloadTask> tasks) async {
    return await _methods.invokeMethod<bool>('ensureLocalMediaAccess', {
          'fileNames': tasks.map((task) => task.fileName).toList(),
          'contentUris': tasks.map((task) => task.contentUri).toList(),
          'fileSizes': tasks.map((task) => task.fileSize).toList(),
        }) ??
        false;
  }

  Future<void> openVideo(DownloadTask task) {
    return _methods.invokeMethod('openVideo', {
      'fileName': task.fileName,
      'contentUri': task.contentUri,
      'fileSize': task.fileSize,
    });
  }

  Future<Uint8List?> getVideoThumbnail(DownloadTask task) {
    return _methods.invokeMethod<Uint8List>('getVideoThumbnail', {
      'fileName': task.fileName,
      'contentUri': task.contentUri,
      'fileSize': task.fileSize,
    });
  }

  Future<void> deleteTasks(
    List<DownloadTask> tasks, {
    required bool deleteFiles,
  }) {
    return _methods.invokeMethod('deleteTasks', {
      'ids': tasks.map((task) => task.id).toList(),
      'fileNames': tasks.map((task) => task.fileName).toList(),
      'contentUris': tasks.map((task) => task.contentUri).toList(),
      'fileSizes': tasks.map((task) => task.fileSize).toList(),
      'deleteFiles': deleteFiles,
    });
  }

  Future<void> testSmb(Map<String, Object> config) {
    return _methods.invokeMethod('testSmb', {'config': config});
  }

  Future<List<SmbFolderEntry>> listSmbFolders(
    Map<String, Object> config,
    String path,
  ) async {
    final raw = await _methods.invokeListMethod<Object?>('listSmbFolders', {
      'config': config,
      'path': path,
    });
    return raw
            ?.map(
              (item) => SmbFolderEntry.fromMap(
                Map<Object?, Object?>.from(item! as Map),
              ),
            )
            .toList() ??
        const [];
  }

  Future<void> uploadToSmb(
    Map<String, Object> config,
    String path,
    List<DownloadTask> tasks,
  ) {
    return _methods.invokeMethod('uploadToSmb', {
      'config': config,
      'path': path,
      'ids': tasks.map((task) => task.id).toList(),
      'fileNames': tasks.map((task) => task.fileName).toList(),
      'contentUris': tasks.map((task) => task.contentUri).toList(),
      'fileSizes': tasks.map((task) => task.fileSize).toList(),
    });
  }
}
