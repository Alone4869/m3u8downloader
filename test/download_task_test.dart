import 'package:flutter_test/flutter_test.dart';
import 'package:m3u8downloader/src/download_bridge.dart';

void main() {
  test('parses a native download task update', () {
    final task = DownloadTask.fromMap({
      'id': 'task-1',
      'url': 'https://example.com/master.m3u8',
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
  });

  test('parses SMB upload progress and clamps its fraction', () {
    final progress = SmbUploadProgress.fromMap({
      'fileIndex': 1,
      'fileCount': 3,
      'fileName': 'sample.ts',
      'uploadedBytes': 120,
      'totalBytes': 100,
      'bytesPerSecond': 73400320.0,
    });

    expect(progress.fileIndex, 1);
    expect(progress.fileCount, 3);
    expect(progress.fileName, 'sample.ts');
    expect(progress.progress, 1.0);
    expect(progress.bytesPerSecond, 73400320.0);
  });
}
