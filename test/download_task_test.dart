import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3u8downloader/src/download_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('parses a native download task update', () {
    final task = DownloadTask.fromMap({
      'id': 'task-1',
      'url': 'https://example.com/master.m3u8',
      'sourceUrl': 'https://x.com/example/status/123',
      'fileName': 'sample.ts',
      'status': 'downloading',
      'progress': 0.42,
      'message': '',
      'savedPath': '',
      'contentUri': 'content://media/external/downloads/42',
      'createdAt': 1000,
      'completedAt': 2000,
      'fileSize': 1048576,
      'uploaded': true,
    });

    expect(task.id, 'task-1');
    expect(task.sourceUrl, 'https://x.com/example/status/123');
    expect(task.status, DownloadStatus.downloading);
    expect(task.progress, 0.42);
    expect(task.createdAt, 1000);
    expect(task.completedAt, 2000);
    expect(task.fileSize, 1048576);
    expect(task.contentUri, 'content://media/external/downloads/42');
    expect(task.uploaded, isTrue);
  });

  test('falls back to queued for an unknown native status', () {
    final task = DownloadTask.fromMap({'status': 'new-status'});

    expect(task.status, DownloadStatus.queued);
    expect(task.fileName, 'video.ts');
    expect(task.sourceUrl, isEmpty);
  });

  test('passes the original source URL when starting a download', () async {
    const channel = MethodChannel('m3u8_downloader/methods');
    MethodCall? capturedCall;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      capturedCall = call;
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    await DownloadBridge.instance.startDownload(
      url: 'https://cdn.example.com/video.mp4',
      fileName: 'video.mp4',
      sourceUrl: 'https://x.com/example/status/123',
    );

    expect(capturedCall?.method, 'startDownload');
    expect(capturedCall?.arguments, {
      'url': 'https://cdn.example.com/video.mp4',
      'fileName': 'video.mp4',
      'cookie': '',
      'sourceUrl': 'https://x.com/example/status/123',
    });
  });

  test('parses SMB upload progress and clamps its fraction', () {
    final progress = SmbUploadProgress.fromMap({
      'fileIndex': 1,
      'fileCount': 3,
      'fileName': 'sample.ts',
      'uploadedBytes': 120,
      'totalBytes': 100,
      'bytesPerSecond': 73400320.0,
      'protocol': 'SMB 3.1.1 · 高速模式',
    });

    expect(progress.fileIndex, 1);
    expect(progress.fileCount, 3);
    expect(progress.fileName, 'sample.ts');
    expect(progress.progress, 1.0);
    expect(progress.bytesPerSecond, 73400320.0);
    expect(progress.protocol, 'SMB 3.1.1 · 高速模式');
  });

  test('requests a video thumbnail from the native media entry', () async {
    const channel = MethodChannel('m3u8_downloader/methods');
    MethodCall? capturedCall;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      capturedCall = call;
      return Uint8List.fromList([1, 2, 3]);
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    const task = DownloadTask(
      id: 'task-2',
      url: 'https://example.com/video.mp4',
      fileName: 'video.mp4',
      status: DownloadStatus.completed,
      progress: 1,
      contentUri: 'content://media/external/downloads/99',
      fileSize: 2048,
    );

    final bytes = await DownloadBridge.instance.getVideoThumbnail(task);

    expect(bytes, Uint8List.fromList([1, 2, 3]));
    expect(capturedCall?.method, 'getVideoThumbnail');
    expect(capturedCall?.arguments, {
      'fileName': 'video.mp4',
      'contentUri': 'content://media/external/downloads/99',
      'fileSize': 2048,
    });
  });
}
