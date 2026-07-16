# 第三方项目与在线服务

本文件说明本项目直接依赖、内嵌或交互的主要上游。完整的 Flutter 间接依赖及精确版本以 `pubspec.lock` 为准，Android 间接依赖以 Gradle 解析结果为准。

## 代码和运行时依赖

| 项目 | 用途 | 许可证 |
| --- | --- | --- |
| [Flutter](https://github.com/flutter/flutter) | 应用框架和 Android 嵌入层 | BSD-3-Clause |
| [flutter_inappwebview](https://github.com/pichillilorenzo/flutter_inappwebview) | 内置浏览器、请求捕获 | Apache-2.0 |
| [liquid_glass_easy](https://pub.dev/packages/liquid_glass_easy) | 液态玻璃界面效果 | MIT |
| [shared_preferences](https://pub.dev/packages/shared_preferences) | 非敏感设置持久化 | BSD-3-Clause |
| [flutter_secure_storage](https://pub.dev/packages/flutter_secure_storage) | SMB 凭据的系统安全存储 | BSD-3-Clause |
| [jcifs-ng](https://github.com/AgNO3/jcifs-ng) | SMB 2/3 客户端 | LGPL |
| [SLF4J](https://www.slf4j.org/) | jcifs-ng 日志接口及空实现 | MIT |

`third_party/flutter_inappwebview_android` 来自上游 `flutter_inappwebview` v6.1.5 中的 Android 包 v1.1.3，保留了上游 Apache-2.0 `LICENSE`。本仓库将调试版和发布版的默认 ProGuard 配置从已被 AGP 9 移除的 `proguard-android.txt` 改为 `proguard-android-optimize.txt`；除此之外不声称对上游代码拥有权利。

## 在线服务

X/Twitter 链接解析会按所选线路访问以下第三方服务。它们不是本项目的一部分，也不受本项目 MIT 许可证覆盖，其可用性、隐私政策和服务条款由各自运营者决定。

- [FxTwitter API](https://github.com/FixTweet/FxTwitter)
- [VxTwitter API](https://github.com/dylanpdx/BetterTwitFix)
- [SaveTwitter](https://savetwitter.net/)
- [SnapVid](https://snapvid.net/)

项目与 X、Twitter、上述服务及其运营者不存在隶属、授权或背书关系。
