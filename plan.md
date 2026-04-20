# floc-player 开发计划

## 项目信息
- 项目名：floc_player
- Flutter 版本：3.32.4
- 平台：Android（真机调试） + iOS Simulator（UI 调试）
- 开发工具：VSCode

## 技术栈
- 播放器：media_kit
- 状态管理：provider
- 本地存储：shared_preferences
- 路由：go_router
- HTTP：dio（支持拦截器自动注入 token）

---

## Phase 1：项目初始化 + 依赖配置

### 步骤 1.1 清理默认代码
- 清空 `lib/main.dart`，只保留最基础的 MaterialApp 结构
- 主题使用暗色主题 `ThemeData.dark()`
- `debugShowCheckedModeBanner: false`

### 步骤 1.2 配置 pubspec.yaml 依赖
添加以下依赖：
```yaml
dependencies:
  media_kit: ^1.1.10
  media_kit_video: ^1.2.4
  media_kit_libs_video: ^1.0.4
  provider: ^6.1.2
  shared_preferences: ^2.3.2
  go_router: ^14.2.7
  dio: ^5.7.0
```

### 步骤 1.3 建立项目目录结构
```
lib/
├── main.dart
├── app.dart                  # MaterialApp 配置
├── router.dart               # 路由配置
├── config/
│   └── app_config.dart       # 统一配置：域名、默认账号、登录验证码等
├── models/
│   ├── channel.dart          # 直播频道模型
│   └── video.dart            # 本地视频模型
├── services/
│   ├── api_client.dart       # dio 封装：baseUrl、token 拦截器
│   └── auth_service.dart     # 登录、token 持久化与读取
├── data/
│   ├── channel_source.dart   # 频道数据源抽象接口
│   └── mock_channel_source.dart # Mock 实现（硬编码热门列表，后续替换为远端推送）
├── providers/
│   ├── auth_provider.dart    # 登录态 / token 状态管理
│   ├── live_provider.dart    # 直播状态管理
│   └── video_provider.dart   # 视频状态管理
├── screens/
│   ├── home_screen.dart      # 底部导航主页
│   ├── live/
│   │   ├── live_screen.dart       # 直播列表页
│   │   └── live_player_screen.dart # 直播播放页
│   └── video/
│       ├── video_screen.dart       # 视频列表页
│       └── video_player_screen.dart # 视频播放页
└── widgets/
    ├── player/
    │   ├── player_controls.dart    # 播放器控制栏
    │   └── player_gestures.dart    # 手势层
    ├── live_channel_card.dart      # 频道列表卡片
    └── video_card.dart             # 视频列表卡片
```

### 步骤 1.4 Android 权限配置
在 `android/app/src/main/AndroidManifest.xml` 添加：
```xml
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE"/>
```

### 步骤 1.5 media_kit 初始化
在 `main.dart` 的 `main()` 函数中添加：
```dart
WidgetsFlutterBinding.ensureInitialized();
MediaKit.ensureInitialized();
```

---

## Phase 2：底部导航 + 基础路由

### 步骤 2.1 创建 HomeScreen
- 底部导航栏，2个 tab：直播、视频
- 使用 NavigationBar 组件
- 图标：直播用播放图标，视频用视频图标

### 步骤 2.2 配置路由
使用 go_router 配置以下路由：
```
/               → HomeScreen
/live           → LiveScreen
/live/player    → LivePlayerScreen
/video          → VideoScreen
/video/player   → VideoPlayerScreen
```

---

## Phase 3：直播模块

### 步骤 3.1 统一配置 AppConfig
集中维护所有可变配置，位于 `lib/config/app_config.dart`。
初期直接用 `const` 硬编码（开发值），后续可替换为 `--dart-define` 或环境文件。

```dart
class AppConfig {
  // 主 + 备用域名，按顺序做网络层故障切换。
  static const String apiBaseUrl = 'https://api.fb168168.com';
  static const List<String> apiBaseUrls = [
    apiBaseUrl,
    'https://api.iqiu888.com',
  ];

  // 开发阶段默认登录凭证
  static const String defaultAccount = '13866668888';
  static const String loginChannel  = 'phone';
  static const String defaultCode   = '7202';
}
```

备用源通过 `HostFailoverInterceptor` 接入：仅在连接/超时类错误上切换到下一个域名，业务错误（code != 0）不会触发切换；切换后 baseUrl 粘住新域名。

### 步骤 3.2 ApiClient（dio 封装）
位于 `lib/services/api_client.dart`，暴露单例 `Dio`：
- `baseUrl = AppConfig.apiBaseUrl`
- 请求拦截器：若本地已有 token，自动添加 `Authorization: <token>`（无 Bearer 前缀）
- 响应拦截器：后端统一结构 `{code, data, message}` — `code != 0` 时抛 `ApiException(code, message)`
- 401 → 自动调 `AuthService.refresh()`（串行去重）刷新 token 后重放原请求
- refresh 内部按 `apiBaseUrls` 顺序尝试所有域名，任一成功即返回；成功后的 host 粘住为后续默认 host

### 步骤 3.3 AuthService & AuthProvider
位于 `lib/services/auth_service.dart` + `lib/providers/auth_provider.dart`。

接口：
- `POST /api/v1/auth/login`
  - 请求体：`{ "account": "...", "channel": "phone", "code": "..." }`
  - 返回：`{ code, data: { token, refresh_token, expired, id, new_user }, message }`

职责：
- `AuthService.login()` → 在当前 host 调一次登录接口，成功则把 `token` / `expired` 写入 `shared_preferences`
- `AuthService.refresh()` → 串行去重；依次尝试 `apiBaseUrls` 中每个 host 调 `login()`，任一成功即返回，全败抛错
- `AuthService.currentHost` → 暴露当前 Dio 的 baseUrl，供 ApiClient 在 401 重放时同步
- `AuthProvider`：
  - 启动时 `ensureAuthenticated()` → 若本地 token 无效则 `service.refresh()`
  - 暴露 `isAuthenticated` / `token` / `loading` / `error` 给上层
  - 登录失败向上抛错，首页显示失败占位 + 重试

### 步骤 3.4 Channel 数据模型
列表接口只返回直播条目的元数据，**不包含播放地址**。播放地址在进入播放页时通过单独接口拉取。

```dart
class Channel {
  final int    id;              // hot_live item id
  final int    matchId;
  final int    videoType;       // 1=足球 2=篮球
  final String title;           // video_title，例如 "15:00 日职联 名古屋鲸鱼 vs 福冈黄蜂"
  final String coverUrl;        // 封面图
  final DateTime startTime;     // live_start_time
  final String competitionName; // match.competition_name
  final String homeTeamName;    // match.home_team_name
  final String homeTeamLogo;    // match.home_team_logo
  final String awayTeamName;
  final String awayTeamLogo;
  final String commentatorName; // commentators[0].nickname
  final String commentatorAvatar;
}
```

### 步骤 3.5 频道数据源
频道列表由远端接口返回「热门直播」，不在本地做分类。

列表接口：
- `GET /api/v1/index/index?x=<timestamp_ms>`
  - 无业务参数；`x` 为防缓存用的毫秒时间戳
  - 需携带 Bearer token（由 ApiClient 拦截器注入）
  - 响应结构：`{code, data: {sort, result: {hot_live: [...], hot_match, preference_scheme}}, message}`
  - 只取 `data.result.hot_live`，其它字段（比赛/方案等）忽略

实现：
- 定义 `ChannelSource` 抽象（`Future<List<Channel>> fetch()`）
- `ApiChannelSource` 实现：调 `/api/v1/index/index`，遍历 `data.result.hot_live` 构造 `Channel` 列表
- 解析失败 / 网络失败向上抛错，由列表页统一展示失败占位

> **TODO**：播放地址接口待补充。已知列表项有 `id` 与 `match_id`，播放时需要用其中之一调 `GET ???` 获取 m3u8/rtmp 地址。在得到接口前，播放页先做占位（展示标题和封面），或走开发用假地址。

### 步骤 3.6 直播列表页 LiveScreen
- 单一列表，不做分类 Tab
- 顶部仅保留页面标题 / 刷新入口
- 频道列表，每个卡片显示：
  - 频道名称
  - 清晰度标签（HD/4K）
  - LIVE 红色标识
- 下拉刷新触发数据源重新拉取
- 加载中 / 空列表 / 失败状态统一处理
- 未登录或 token 失效时显示登录失败占位 + 重试
- 点击跳转播放页,传入 Channel 对象

### 步骤 3.7 直播播放页 LivePlayerScreen
布局：
- 顶部视频播放区域（16:9）
- 底部频道列表（可滚动，高亮当前播放频道）

功能：
- 进入页面自动播放
- 点击底部频道列表直接切台（不退出页面）
- 加载中显示 loading 指示器
- 播放失败展示失败占位（错误文案 + 重试按钮），不做自动降级

---

## Phase 4：视频模块

### 步骤 4.1 Video 数据模型
```dart
class Video {
  final String name;
  final String path;          // 本地文件路径
  final Duration? lastPosition; // 上次播放进度
  final Duration? duration;   // 总时长
}
```

### 步骤 4.2 VideoProvider
- 扫描本地固定目录的 mp4 文件
- Android 目录：`/storage/emulated/0/floc-player/videos/`
- 读取并保存每个视频的播放进度（用 shared_preferences）

### 步骤 4.3 视频列表页 VideoScreen
- 显示本地视频列表
- 每个卡片显示：
  - 文件名
  - 上次播放进度（如有）
  - 总时长（如有）
- 长按显示删除选项
- 目录不存在或为空时显示提示

### 步骤 4.4 视频播放页 VideoPlayerScreen
- 全屏播放
- 自动跳转到上次播放位置
- 退出时保存当前进度

---

## Phase 5：播放器手势与控制栏

### 步骤 5.1 手势层 PlayerGestures
在视频区域叠加 GestureDetector：
```
单击          →  显示/隐藏控制栏
左右滑动      →  快进快退（显示进度提示）
左侧上下滑动  →  调节亮度
右侧上下滑动  →  调节音量
长按 3倍速快进
```

### 步骤 5.2 控制栏 PlayerControls
包含：
- 顶部：返回按钮 + 标题
- 底部：
  - 播放/暂停按钮
  - 进度条（直播模式隐藏）
  - 当前时间 / 总时长
  - 全屏按钮
- 2秒无操作自动隐藏

### 步骤 5.3 屏幕旋转
- 进入播放页锁定横屏
- 退出播放页恢复竖屏

---

## Phase 6：收尾与优化

### 步骤 6.1 播放失败处理
- 统一失败占位：错误文案 + 手动「重试」按钮
- 不做自动重试 / 自动重连

### 步骤 6.2 缓存清理（视频模块）
- 设置页或长按菜单支持删除本地视频文件

### 步骤 6.3 整体 UI 细节
- 统一暗色主题颜色
- loading 状态统一处理
- 错误状态统一处理

---

## 开发顺序总结

```
Phase 1  →  Phase 2  →  Phase 3  →  Phase 4  →  Phase 5  →  Phase 6
初始化      导航路由    直播模块    视频模块    播放手势    收尾优化
```

每个 Phase 完成后在真机测试核心功能，再进入下一阶段。