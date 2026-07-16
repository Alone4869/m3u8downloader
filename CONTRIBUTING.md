# 贡献指南

## 开始之前

1. 使用 Flutter stable、JDK 17 和可用的 Android SDK。
2. 执行 `flutter pub get`。
3. 不要提交真实 Cookie、下载链接、SMB 地址/账号/密码、签名文件或 GitHub Token。

## 提交改动

在提交前运行：

```bash
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
```

行为变化应包含相应测试。涉及内嵌第三方代码时，必须保留原许可证和版权声明，并在 `ACKNOWLEDGEMENTS.md` 记录来源、版本及本地修改。

下载器改动不得加入规避 DRM、付费墙、身份验证或访问控制的功能。
