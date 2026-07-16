# M3U8 视频下载器

一款仅支持 Android 的 Material 3 Flutter 应用，用于捕获、下载和归档用户有权保存的视频内容。

## 功能

- 从 X/Twitter 链接解析可用视频清晰度，也可通过内置浏览器捕获 M3U8 或直链视频。
- Android 前台服务并发下载 HLS 分片，自动选择最高带宽变体并支持常见 AES-128 HLS。
- 将结果保存到系统 `下载/M3U8 Downloader`；M3U8 输出为 `.ts`，直链视频保留为 `.mp4`。
- 将已下载视频流式上传到 SMB 2/3 共享，显示实时速度和文件进度。
- 在设置页通过公开 GitHub Releases 检查新版本，不在 App 中保存 GitHub 凭据。

本项目不会绕过付费、登录或 DRM 保护。请仅下载、保存和上传你拥有权利或已获授权处理的内容，并遵守内容来源网站的服务条款及所在地法律。

## 开发

要求 Flutter 3.44+、JDK 17、Android SDK，最低支持 Android API 29。

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
```

正式构建前请阅读 [发布指南](docs/RELEASING.md)。App 默认从本仓库的公开 GitHub Releases 检查更新；复用代码时也可以在构建阶段覆盖更新源：

```bash
flutter build apk --release \
  --dart-define=UPDATE_REPOSITORY=other-owner/other-repository
```

`UPDATE_REPOSITORY` 指向的仓库及其 Releases 必须公开，否则客户端无法在不泄露访问令牌的情况下检查更新。

## 项目来源与致谢

项目是独立实现，不是其他下载器项目的分支。它建立在 Flutter 生态组件之上，并调用 FxTwitter、VxTwitter 等公开在线接口；仓库还包含为 Android Gradle Plugin 兼容性调整过的 `flutter_inappwebview_android` 1.1.3 源码。

完整的上游项目、用途、修改内容及许可证见 [ACKNOWLEDGEMENTS.md](ACKNOWLEDGEMENTS.md)。应用内也可从“设置 > 开源许可”查看由 Flutter 收集的依赖许可。

## 参与和安全

提交改动前请阅读 [CONTRIBUTING.md](CONTRIBUTING.md)。安全问题请按 [SECURITY.md](SECURITY.md) 私下报告，不要在公开 Issue 中附带账号、Cookie、SMB 密码、下载链接或其他敏感数据。

## 许可证

本项目自有代码采用 [MIT License](LICENSE)。`third_party/` 中的代码和其他依赖仍分别受其原始许可证约束；MIT 许可证不会替代这些第三方条款。
