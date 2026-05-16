import 'package:flutter/widgets.dart';

import '../../models/site_models.dart';
import '../cloudflare_browser.dart';
import 'site_adapter.dart';

/// missav.ai 适配器。
///
/// **不走 Dio**：missav.ai 用 Cloudflare 拦截，纯 Dart 的 HttpClient 跟 iOS Safari
/// TLS 指纹对不上，即使 cookie + UA + header 全对齐还是 403。所以这边所有 HTML
/// 拉取走 [CloudflareBrowser]——一个常驻 HeadlessInAppWebView 当 fetcher。
///
/// 站点细节：
/// - 列表/搜索/分类都被 CF 拦；只有 `/cn` 首页和 `/cn/{slug}` 详情页能稳定渲出 HTML。
/// - 详情页内嵌 Dean Edwards p.a.c.k.e.r：`eval(function(p,a,c,k,e,d){...}('payload',base,count,'kw|...'.split('|'),0,{})`，
///   解包后会出现 `https://surrit.com/{uuid}/playlist.m3u8`（master HLS）。
/// - 缩略图托管在 `fourhoi.com`，**不** 走 CF，正常 Image.network 即可加载。
class MissAvAdapter implements SiteAdapter {
  MissAvAdapter({required this.info});

  @override
  final SiteInfo info;

  String get _localePath => '${info.baseUrl}/cn';

  @override
  Future<List<SiteCategory>> fetchCategories() async => const [
        SiteCategory(id: 'release', name: '最新发布'),
        SiteCategory(id: 'new', name: '新作'),
        SiteCategory(id: 'today-hot', name: '今日热门'),
        SiteCategory(id: 'weekly-hot', name: '本周热门'),
        SiteCategory(id: 'chinese-subtitle', name: '中文字幕'),
        SiteCategory(id: 'uncensored-leak', name: '无码流出'),
      ];

  @override
  double get cardAspectRatio => 3 / 2;

  @override
  BoxFit get cardImageFit => BoxFit.contain;

  @override
  Future<List<VideoSummary>> fetchListing(
      {String? categoryId, int page = 1}) async {
    // /cn 首页是精选 ~40 条，不分页。所以默认走 /cn/release（最新发布）这种
    // 标准 Laravel 列表页，支持 ?page=N。
    final segment = categoryId ?? 'release';
    final base = '$_localePath/$segment';
    final url = page <= 1 ? base : '$base?page=$page';
    final body = await _safeFetch(url);
    return _parseCards(body);
  }

  @override
  Future<List<VideoSummary>> search(String query, {int page = 1}) async {
    if (page > 1) return const [];
    final q = query.trim();
    if (q.isEmpty) return const [];

    // 走站方真正的搜索：`/cn/search/{q}`。结果页和首页一样的 Alpine 卡片模板，
    // _parseCards 直接复用。
    final encoded = Uri.encodeComponent(q);
    final url = '$_localePath/search/$encoded';
    try {
      final html = await _safeFetch(url);
      final cards = _parseCards(html);
      if (cards.isNotEmpty) return cards;
    } catch (_) {
      // 走兜底
    }

    // 兜底：搜索路由失败 / 没命中时，把输入当番号 slug 直接命中 `/cn/{slug}` 详情页。
    final slug = _slugify(q);
    if (slug.isEmpty) return const [];
    final fallback = '$_localePath/$slug';
    try {
      final html = await _safeFetch(fallback);
      final title = _ogContent(html, 'og:title') ?? slug.toUpperCase();
      final cover = _ogContent(html, 'og:image');
      return [
        VideoSummary(
          siteId: info.id,
          title: title,
          detailUrl: fallback,
          thumb: cover,
          subtitle: '按番号匹配',
        ),
      ];
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<VideoDetail> fetchDetail(String detailUrl) async {
    final html = await _safeFetch(detailUrl);
    final title = _ogContent(html, 'og:title') ?? detailUrl;
    final cover = _ogContent(html, 'og:image');
    final desc = _ogContent(html, 'og:description');
    return VideoDetail(
      siteId: info.id,
      title: title,
      detailUrl: detailUrl,
      cover: cover,
      description: desc,
      sources: [
        EpisodeSource(
          label: '正片',
          episodes: [Episode(label: '播放', ref: detailUrl)],
        ),
      ],
    );
  }

  @override
  Future<ResolvedSource> resolve(Episode ep) async {
    final html = await _safeFetch(ep.ref);
    final url = _findPlaylistInPacker(html);
    if (url == null) {
      throw Exception('未在详情页找到 m3u8 (${info.id})');
    }
    // surrit.com 不挂 CF，media_kit 直接拉 m3u8 即可；带 Referer 防 CDN 反盗链。
    return ResolvedSource(
      url: url,
      headers: {
        'User-Agent': _kPlayerUA,
        'Referer': '${info.baseUrl}/',
      },
    );
  }

  @override
  Map<String, String> thumbHeaders() => {
        // fourhoi.com 也不挂 CF，但带个 Referer 防意外反盗链。
        'Referer': '${info.baseUrl}/',
        'User-Agent': _kPlayerUA,
      };

  Future<String> _safeFetch(String url) async {
    try {
      return await CloudflareBrowser.instance.fetchHtml(url);
    } catch (e) {
      // 把 WebView 出来的"超时""挑战页"等错误统一翻译给上层。
      final msg = e.toString();
      if (msg.contains('Cloudflare') ||
          msg.contains('超时') ||
          msg.contains('挑战')) {
        throw Exception('${info.name} 被 Cloudflare 拦截，稍后再试');
      }
      rethrow;
    }
  }

  List<VideoSummary> _parseCards(String html) {
    final out = <VideoSummary>[];
    final seen = <String>{};
    for (final m in _titleLinkRe.allMatches(html)) {
      final slug = m.group(1)!;
      final raw = _decodeHtml(m.group(2)!).trim();
      // Alpine 模板里 `<a href="#" ...>&nbsp;</a>` 是占位卡。
      if (raw.isEmpty) continue;
      if (!seen.add(slug)) continue;
      out.add(VideoSummary(
        siteId: info.id,
        title: raw,
        detailUrl: '$_localePath/$slug',
        thumb: 'https://fourhoi.com/$slug/cover-t.jpg',
      ));
    }
    return out;
  }
}

// 播放/缩略图请求用的 UA。Player 由 media_kit 发，不经过 WebView 也不走 CF，
// 所以这里可以用一个稳定的桌面 UA 字符串。
const _kPlayerUA =
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/147.0.0.0 Safari/537.36';

String _slugify(String s) {
  final lower = s.trim().toLowerCase();
  final mapped = lower.replaceAll(RegExp(r'[\s_]+'), '-');
  final cleaned = mapped.replaceAll(RegExp(r'[^a-z0-9-]'), '');
  return cleaned.replaceAll(RegExp(r'-+'), '-').replaceAll(RegExp(r'^-|-$'), '');
}

String? _ogContent(String html, String property) {
  final re = RegExp(
    '<meta\\s+property="${RegExp.escape(property)}"\\s+content="([^"]*)"',
  );
  final m = re.firstMatch(html);
  if (m == null) return null;
  final raw = _decodeHtml(m.group(1)!).trim();
  return raw.isEmpty ? null : raw;
}

/// 解 Dean Edwards p.a.c.k.e.r，找到 `*.m3u8` 即可（master playlist 优先）。
String? _findPlaylistInPacker(String html) {
  for (final m in _packerRe.allMatches(html)) {
    final keywords = _unescapeJsString(m.group(4)!).split('|');
    // 只关心含 m3u8 的那块；另一块是域名重定向，没用。
    if (!keywords.contains('m3u8')) continue;

    final payload = _unescapeJsString(m.group(1)!);
    final radix = int.tryParse(m.group(2)!) ?? 0;
    final count = int.tryParse(m.group(3)!) ?? 0;
    if (radix < 2 || count <= 0) continue;

    final unpacked = _packerDecode(payload, radix, count, keywords);
    final master = _masterM3u8Re.firstMatch(unpacked);
    if (master != null) return master.group(0);
    final any = _anyM3u8Re.firstMatch(unpacked);
    if (any != null) return any.group(0);
  }
  return null;
}

String _packerDecode(
    String payload, int radix, int count, List<String> keywords) {
  var p = payload;
  for (var c = count - 1; c >= 0; c--) {
    if (c >= keywords.length) continue;
    final repl = keywords[c];
    final symbol = c.toRadixString(radix);
    if (repl.isEmpty || repl == symbol) continue;
    p = p.replaceAll(RegExp('\\b${RegExp.escape(symbol)}\\b'), repl);
  }
  return p;
}

String _unescapeJsString(String s) =>
    s.replaceAllMapped(RegExp(r'\\(.)'), (m) {
      switch (m.group(1)!) {
        case 'n':
          return '\n';
        case 't':
          return '\t';
        case 'r':
          return '\r';
        default:
          return m.group(1)!;
      }
    });

final _packerRe = RegExp(
  r"""\}\('((?:\\.|[^'\\])*)',(\d+),(\d+),'((?:\\.|[^'\\])*)'\.split\('\|'\)""",
);

final _titleLinkRe = RegExp(
  r'<a\s+class="text-secondary group-hover:text-primary"\s+href="https://missav\.ai/cn/([a-z0-9][a-z0-9-]*)"[^>]*>([\s\S]*?)</a>',
  dotAll: true,
);

final _masterM3u8Re = RegExp(r'''https?://[^\s'"]+/playlist\.m3u8[^\s'"]*''');
final _anyM3u8Re = RegExp(r'''https?://[^\s'"]+\.m3u8[^\s'"]*''');

const _entityMap = {
  '&amp;': '&',
  '&lt;': '<',
  '&gt;': '>',
  '&quot;': '"',
  '&#39;': "'",
  '&nbsp;': ' ',
};

final _entityNumeric = RegExp(r'&#(x?[0-9a-fA-F]+);');

String _decodeHtml(String s) {
  var out = s;
  _entityMap.forEach((k, v) => out = out.replaceAll(k, v));
  out = out.replaceAllMapped(_entityNumeric, (m) {
    final raw = m.group(1)!;
    final code = raw.startsWith('x')
        ? int.tryParse(raw.substring(1), radix: 16)
        : int.tryParse(raw);
    if (code == null) return m.group(0)!;
    return String.fromCharCode(code);
  });
  return out;
}
