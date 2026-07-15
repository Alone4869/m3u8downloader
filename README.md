# M3U8 视频下载器

仅支持 Android 的 Material 3 Flutter 应用。内置 WebView 打开视频解析站，捕获 M3U8 或视频下载请求后弹出确认窗口；确认后由 Android 前台服务在后台并发下载分片，并保存到系统“下载/M3U8 Downloader”目录。

## 开发环境

- Flutter 3.44+
- Android SDK / Android Studio
- Android API 29+

```bash
flutter pub get
flutter test
flutter build apk --debug
```

M3U8 分片按最高带宽变体下载，支持常见 AES-128 HLS；M3U8 输出为 `.ts`，直链视频保留为 `.mp4`。应用不会绕过付费、登录或 DRM 保护，请仅下载你有权保存的内容。

已完成的视频可上传到 SMB 2/3 共享。上传采用大块顺序流式写入和 1MB SMB 传输窗口，上传弹窗会显示实时速度、文件进度与已传容量，便于在真机上核对局域网吞吐。
