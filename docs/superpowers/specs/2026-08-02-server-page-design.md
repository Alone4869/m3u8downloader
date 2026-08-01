# 服务器（Servers）功能设计文档

日期：2026-08-02
状态：已获用户确认

## 背景与目标

在现有 M3U8 下载器（Flutter Material 3 + 液态玻璃导航）中新增「服务器」功能：
- 底部导航新增第 4 个 Tab「服务器」
- 展示可添加的连接卡片：Jellyfin、Emby、SMB，卡片带协议专属图标
- 本阶段只实现 Jellyfin：点击卡片进入 Jellyfin 原生 UI 首页，包含巨幕轮播、继续观看、媒体库卡片、最新添加影片
- 点击影片进入详情页（海报、简介、评分等），提供「播放」操作——调系统播放器在线播放（**不做下载**）

## 现有架构参照

- 导航：`lib/src/app.dart` 中 `HomeScreen` 的液态玻璃底部导航（`_SmoothLiquidNavigationBar`），Tab 切换用 `FullScreenPageStack`（IndexedStack）。新增 Tab 只需加一个 `LiquidGlassTabBarItem` 和对应 View 组件。
- 凭据存储：沿用 `smb_settings.dart` 模式——`shared_preferences`（非敏感字段）+ `flutter_secure_storage`（密码/Token）。
- 页面风格：`AppSurface`（圆角卡片）、`AppBackdrop`（渐变背景）、中文字体、暗色 `#0E1015`。
- 系统返回：`HomeScreen._handleSystemBack` 中 `_selectedIndex != 0` 时回到首页，新 Tab 无需改动（0 以外的 index 已覆盖）。

## 技术选型

- 新增依赖：`http`（Jellyfin API 客户端）、`url_launcher`（唤起系统播放器）。
- 不引入播放器库、不引入 WebView 方案，全部 Flutter 原生 UI。
- 图片加载：Jellyfin 图片接口支持 `?api_key=` 查询参数鉴权，可直接用 `Image.network`。
- Jellyfin API 基准路径：`{serverUrl}/Users/{userId}/...`，所有请求带 `X-Emby-Token` 头或 `api_key` 参数。

## 架构与模块

新增文件（均位于 `lib/src/`，遵循现有单文件模块风格）：

1. **`server_settings.dart`** — 服务器配置存储
   - `ServerType` 枚举：`jellyfin` / `emby` / `smb`（本阶段仅 jellyfin 可完整使用）
   - `ServerConfig`：id、type、name、url、username、userId、accessToken、创建时间
   - `ServerSettingsStore`（单例）：`loadAll()` / `save(ServerConfig)` / `remove(id)`；密码与 token 存 secure storage，其余存 preferences（沿用 `smb_settings.dart` 的 `Future.wait` 模式）

2. **`jellyfin_client.dart`** — 轻量 Jellyfin API 客户端
   - `JellyfinClient`：持有 baseUrl + accessToken + userId
   - `login(baseUrl, username, password)`：`POST /Users/AuthenticateByName`，返回 `UserId` 与 `AccessToken`；失败抛异常并带可读中文错误（401 → 「账号或密码错误」）
   - `fetchViews()`：`GET /Users/{id}/Views` → 媒体库列表
   - `fetchResume()`：`GET /Users/{id}/Items/Resume` → 继续观看（含 `UserData.PlaybackPositionTicks` 进度）
   - `fetchLatest(parentId, limit)`：`GET /Users/{id}/Items/Latest?ParentId=&Limit=` → 最新添加
   - `fetchItem(id)`：`GET /Users/{id}/Items/{id}` → 详情
   - `fetchPeople(id)`：`GET /Items/{id}/People` → 演职员
   - `fetchPlaybackUrl(itemId, mediaSourceId)`：`POST /Items/{id}/PlaybackInfo` 取 `MediaSourceId`，拼出 `{server}/videos/{id}/master.m3u8?api_key=...&MediaSourceId=...&UserId=...`（流地址不预下载，仅在播放时构建）
   - 模型类：`JellyfinItem`（id、type、name、overview、year、runtime、communityRating、genres、imageTags、backdropImageTags、progressTicks 等）、`JellyfinView`（id、name、type、imageTag）
   - 超时与错误处理：网络异常 → 「无法连接服务器」；解析失败 → 「服务器返回了无法识别的数据」

3. **`server_home_view.dart`** — 「服务器」Tab 根视图
   - 标题「服务器」+ 右侧「添加」按钮
   - 已保存服务器卡片列表：卡片含协议图标（Jellyfin 紫色方块 Logo、Emby 绿色 Logo、SMB 蓝色文件夹图标——用 Material Icons + 品牌色圆形底实现，不引入图片资源）、服务器名、地址、连接状态（未配置/已连接），点击进入 `JellyfinHomeView`
   - 空状态：居中引导卡片「添加你的第一个服务器」
   - 添加流程：底部弹层（`showModalBottomSheet`）三步走
     - 第一步：选协议（Jellyfin/Emby/SMB 三张可选卡，后两者显示「即将支持」并禁用）
     - 第二步：表单（服务器地址、用户名、密码）
     - 第三步：「测试并连接」→ 调 `JellyfinClient.login` → 成功保存并进入 Jellyfin；失败弹 SnackBar 提示原因
   - 卡片长按或卡片上「更多」菜单：编辑 / 删除（删除需确认对话框）

4. **`jellyfin_home_view.dart`** — Jellyfin 原生首页
   - 深色影院风（页面独立使用深色系，与 App 主题无关，接近 Jellyfin 的 `#0B0B0F`）
   - **巨幕轮播**：顶部全宽 `PageView`（高度约屏宽 9/16 或 380-420dp）
     - 数据：`fetchResume()` 取不到的影片 + `fetchLatest` 各库合成取前 5-8 部有 `BackdropImageTags` 的影片
     - 背景：backdrop 大图 + 底部深色渐变遮罩 + 左侧片名大标题（与 Jellyfin 官网海报墙风格一致）+ 年份/评分/类型胶囊标签 + 「▶ 播放」按钮（唤起系统播放器）
     - 自动轮播：`Timer` 每 5 秒切页（手势交互后重置计时），带动效过渡 + 底部圆点指示器
   - **继续观看**（若有数据）：横向 `ListView` 卡片（16:9 缩略图 + 片名 + 底部渐变进度条，显示播放进度百分比），点卡片直接调播放（进度数据已含，无需进详情）
   - **媒体库**：横向滚动圆角卡片（库图标：电影/剧集/音乐/图片/混合，来自 `Views` 的 CollectionType 映射），下方小字「X 部」
   - **最新添加**：每个媒体库一个分区，标题为库名 + 「最新」，横向海报墙（2:3 海报圆角卡片 + 片名 + 年份），点海报进详情页
   - 页面结构：`CustomScrollView` + `SliverList`，整页毛玻璃氛围，加载时显示骨架屏或 `CircularProgressIndicator`
   - 失败态：整页错误卡片 + 「重试」按钮；下拉刷新（`RefreshIndicator`）

5. **`jellyfin_detail_view.dart`** — 影片详情页
   - 顶部背景：backdrop 大图 + 渐变遮罩，左上返回按钮（普通 AppBar）
   - 内容区：海报（2:3，圆角）+ 片名（大字）+ 年份/片长/评分/类型标签行 + 简介（可展开）+ 演职员横向头像列表
   - 底部悬浮「▶ 播放」大按钮：调 `fetchPlaybackUrl` → `url_launcher` 打开 m3u8 流地址（系统播放器如 MX Player/VLC 可播）；未安装可播应用时提示错误
   - 不含任何下载功能

6. **`app.dart` 改动**：底部导航 items 中「设置」前插入 `LiquidGlassTabBarItem(icon: Icons.dns_outlined, selectedIcon: Icons.dns_rounded, label: '服务器')`，children 插入 `ServerHomeView()`。`_bottomNavigationClearance` 等逻辑自动适配 4 Tab。

## 数据流

```
ServerHomeView ──选卡片──▶ JellyfinHomeView
       │                       │ initState
       │                       ▼
       │              JellyfinClient(fetchViews / fetchResume / fetchLatest)
       │                       │ 并行请求
       │                       ▼
       │              AnimatedBuilder 刷新各 Sliver 区块
       ▼
  点海报 ──▶ JellyfinDetailView ──▶ fetchItem + fetchPeople
                     │
                     ▼
              「播放」──▶ fetchPlaybackUrl ──▶ url_launcher
```

## 错误处理

| 场景 | 处理 |
|---|---|
| 登录失败（401） | SnackBar「账号或密码错误」 |
| 网络不通/超时 | SnackBar「无法连接服务器」，添加表单保留输入 |
| Token 失效（进入首页后 401） | 弹「登录已过期，请重新连接」→ 回到服务器列表，清除该服务器 token |
| 首页接口失败 | 整页错误卡片 + 重试 |
| 单图片加载失败 | `errorBuilder` 显示类型图标占位（沿用 `twitter_home_view.dart` 的 `_MediaCard` 模式） |
| 播放无可用应用 | SnackBar「未找到可播放 m3u8 的应用」 |

## 测试

沿用现有 `test/*_test.dart` 模式（widget test + 纯 Dart 单测）：
- `server_settings_test.dart`：store 增删查、secure storage 分离存储
- `jellyfin_client_test.dart`：用 `MockClient`（http 包自带）验证各接口 URL/参数/解析与错误分支
- `server_home_view_test.dart`：空状态、添加流程弹层、卡片渲染
- `jellyfin_home_view_test.dart`：加载态、错误态重试、轮播与分区渲染（注入 fake client）
- `jellyfin_detail_view_test.dart`：详情渲染与播放按钮回调

## 不做的事（YAGNI）

- 不做 Emby / SMB 的实际功能（仅展示「即将支持」卡片）
- 不做下载、不做播放进度上报回 Jellyfin（`POST /Sessions/Playing`）
- 不做服务器自动发现（Quick Connect / mDNS）
- 不做离线缓存
- 不引入视频播放器库、不做剧集季/集列表（详情页仅展示整体信息；剧集/电影统一走 HLS 播放，若服务器不支持则提示「无法获取播放地址」）

## 视觉基调

- 服务器列表页沿用 App 主题（浅/深色自适应、`AppSurface` 卡片）
- Jellyfin 首页与详情页使用固定深色影院主题（背景 `#0B0B0F` 系、文字白/灰、品牌紫 `#AAB4F5` 点缀），与 Jellyfin 官方 App 质感一致
