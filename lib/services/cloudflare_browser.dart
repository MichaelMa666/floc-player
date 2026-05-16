import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// 用一个常驻的 [HeadlessInAppWebView] 来当 HTTP 客户端：因为 Dart 的 HttpClient
/// 跟 iOS Safari 的 TLS ClientHello / 各种 fingerprint 对不上号，Cloudflare 拦截站
/// （如 missav.ai）即使我们把 cookie + UA + header 全对齐，TLS 一层还是 403。
///
/// 这个类把 WebView 当 fetcher：第一次给某个 origin 拿内容时启个 WebView 在那个
/// origin 的入口页（让 CF 走完挑战），之后所有 fetch 都复用同一个 WebView，
/// 通过 `loadUrl` 跳到目标页，等渲染完读 `document.documentElement.outerHTML`。
///
/// 因为请求是从 WebView 发出去的，TLS 指纹 / cookie / UA 一切都和 Safari 一致，
/// CF 看到的是正常的浏览器流量。
///
/// 局限：
/// - 一个 WebView 一次只能跳一个 URL，所有 fetch 走串行队列。
/// - 页面加载后我们 0.4s tick 轮询 outerHTML，看见正文（>3KB 且不是挑战页）就返回。
///   首次请求平均 ~1s，命中缓存的后续请求通常 < 800ms。
/// - 不返回原始字节，返回的是 outerHTML（即渲染后的 DOM）；对我们这边的纯 HTML
///   解析够用，但对依赖原始字节的场景（比如下载二进制）不适合。
class CloudflareBrowser {
  CloudflareBrowser._();
  static final CloudflareBrowser instance = CloudflareBrowser._();

  final Map<String, _BrowserHandle> _handles = {};

  /// 取目标 URL 的 HTML。同一个 origin 复用同一个 WebView。
  Future<String> fetchHtml(String url) async {
    final origin = _originOf(url);
    final handle =
        _handles.putIfAbsent(origin, () => _BrowserHandle(origin: origin));
    return handle.fetch(url);
  }

  /// 手动重置：丢掉某 origin 的 WebView（cookie 也会清）。
  /// CF 一直拒、需要重新走一遍挑战时用。
  Future<void> reset(String origin) async {
    final h = _handles.remove(origin);
    if (h != null) await h.dispose();
  }

  String _originOf(String url) {
    final u = Uri.parse(url);
    return '${u.scheme}://${u.host}';
  }
}

class _BrowserHandle {
  _BrowserHandle({required this.origin});
  final String origin;

  HeadlessInAppWebView? _webview;
  InAppWebViewController? _controller;
  Future<void>? _initFut;
  // 串行化：每个 fetch 先把上一个 fetch 链上，避免两个并发请求互踩 WebView 导航。
  Future<dynamic> _queue = Future<dynamic>.value();

  Future<void> _init() {
    final existing = _initFut;
    if (existing != null) return existing;
    final fresh = _doInit();
    _initFut = fresh;
    // 失败时清掉 future，下次 fetch 可以再试；成功就一直缓存。
    fresh.catchError((Object _) {
      _initFut = null;
      // 顺手把 WebView 也丢了，重试时干净起步。
      _webview?.dispose().catchError((Object _) {});
      _webview = null;
      _controller = null;
    });
    return fresh;
  }

  Future<void> _doInit() async {
    _log('bootstrapping for $origin');
    final bootUrl = WebUri('$origin/cn');
    final ready = Completer<void>();
    Timer? pollTimer;

    Future<void> checkClearance() async {
      if (ready.isCompleted) return;
      // 关键：controller 是在 onLoadStop 里赋值的。如果 polling timer 比 onLoadStop
      // 先跑（比如 iOS WKWebsiteDataStore 里有上次进程残留的 cf_clearance cookie），
      // 这边就会在 controller 还是 null 时完成 ready → 接着 fetch 报 "controller is null"。
      if (_controller == null) return;
      try {
        final cookies = await CookieManager.instance().getCookies(url: bootUrl);
        final cf = cookies.where((c) => c.name == 'cf_clearance').firstOrNull;
        if (cf != null && cf.value is String && (cf.value as String).isNotEmpty) {
          _log('cf_clearance acquired during bootstrap');
          pollTimer?.cancel();
          if (!ready.isCompleted) ready.complete();
        }
      } catch (_) {}
    }

    _webview = HeadlessInAppWebView(
      initialUrlRequest: URLRequest(url: bootUrl),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        mediaPlaybackRequiresUserGesture: true,
        useShouldOverrideUrlLoading: false,
        cacheEnabled: true,
        transparentBackground: true,
      ),
      onLoadStop: (controller, loadedUrl) async {
        _controller = controller;
        _log('bootstrap onLoadStop: $loadedUrl');
        await checkClearance();
      },
      onReceivedError: (_, request, error) {
        _log('webview error: ${error.type} ${error.description} for ${request.url}');
      },
    );

    try {
      await _webview!.run();
    } catch (e) {
      throw Exception('无法启动 WebView: $e');
    }

    pollTimer = Timer.periodic(
      const Duration(milliseconds: 600),
      (_) => checkClearance(),
    );

    try {
      await ready.future.timeout(const Duration(seconds: 25));
    } on TimeoutException {
      throw Exception('Cloudflare 挑战超时');
    } finally {
      pollTimer.cancel();
    }
  }

  Future<String> fetch(String url) {
    final completer = Completer<String>();
    _queue = _queue.then((_) async {
      try {
        await _init();
        final html = await _fetchInternal(url);
        completer.complete(html);
      } catch (e, s) {
        completer.completeError(e, s);
      }
    });
    return completer.future;
  }

  Future<String> _fetchInternal(String url) async {
    final controller = _controller;
    if (controller == null) throw StateError('controller is null');
    _log('navigate -> $url');
    await controller.loadUrl(urlRequest: URLRequest(url: WebUri(url)));

    // 轮询 outerHTML，直到"看起来是正文"（够长且不是 CF 挑战页）。
    final start = DateTime.now();
    while (DateTime.now().difference(start) < const Duration(seconds: 15)) {
      await Future<void>.delayed(const Duration(milliseconds: 400));
      String html = '';
      try {
        final raw = await controller.evaluateJavascript(
          source: 'document.documentElement.outerHTML',
        );
        html = raw is String ? raw : (raw?.toString() ?? '');
      } catch (e) {
        _log('eval error: $e');
        continue;
      }
      if (html.length > 3000 && !_isCfPage(html)) {
        _log('got content for $url (len=${html.length})');
        return html;
      }
    }
    throw Exception('页面加载超时');
  }

  // CF 挑战页特征：
  // - `<title>Just a moment...</title>` 是 CF 挑战页固定标题。
  // - `window._cf_chl_opt`（带下划线前缀）是挑战脚本的全局对象，正文页不会有。
  //
  // 注意：不能用 `challenge-platform` 作为判定——CF 在所有受保护页面里都会
  // 注入 `/cdn-cgi/challenge-platform/scripts/jsd/main.js`（JSD 探测脚本），
  // 正文页同样包含这个字符串，会误判。
  bool _isCfPage(String html) =>
      html.contains('<title>Just a moment') ||
      html.contains('_cf_chl_opt');

  Future<void> dispose() async {
    try {
      await _webview?.dispose();
    } catch (_) {}
    _webview = null;
    _controller = null;
  }

  void _log(String msg) {
    if (kDebugMode) debugPrint('[cf-browser/$origin] $msg');
  }
}
