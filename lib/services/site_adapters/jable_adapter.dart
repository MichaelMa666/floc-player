import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';

import '../../models/site_models.dart';
import 'site_adapter.dart';

const _kBrowserUA =
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/147.0.0.0 Safari/537.36';

/// jable.tv 适配器。
/// 列表卡片：`<a href="https://jp.jable.tv/videos/{slug}/"><img data-src="{thumb}"></a>`
/// + `<h6 class="title"><a href="...{slug}/">{title}</a></h6>`。
/// 详情页内嵌 `var hlsUrl = '...m3u8';`，每次访问 CDN 重新签名，所以**每次播放都重抓**。
class JableAdapter implements SiteAdapter {
  JableAdapter({required this.info, Dio? dio})
      : _dio = dio ?? _defaultDio();

  @override
  final SiteInfo info;
  final Dio _dio;

  static Dio _defaultDio() => Dio(
        BaseOptions(
          headers: {
            'User-Agent': _kBrowserUA,
            'Accept':
                'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
            'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8,ja;q=0.7',
          },
          followRedirects: true,
          responseType: ResponseType.plain,
          connectTimeout: const Duration(seconds: 12),
          receiveTimeout: const Duration(seconds: 15),
        ),
      );

  @override
  Future<List<SiteCategory>> fetchCategories() async => const [];

  @override
  double get cardAspectRatio => 3 / 2;

  @override
  BoxFit get cardImageFit => BoxFit.contain;

  @override
  Future<List<VideoSummary>> fetchListing(
      {String? categoryId, int page = 1}) async {
    // jable 用 `?from_videos=N` 翻页（实测 page 2 也返回 80+ 卡片）。
    final base = info.baseUrl;
    final url = page <= 1 ? base : '$base/?from_videos=$page';
    final res = await _dio.getUri<String>(Uri.parse(url));
    return _parseCards(res.data ?? '');
  }

  @override
  Future<List<VideoSummary>> search(String query, {int page = 1}) async {
    // 搜索路径 `/search/{query}/?from_videos=N`；page 1 不带参数也能拉到全部。
    final base = '${info.baseUrl}/search/$query/';
    final url = page <= 1 ? base : '$base?from_videos=$page';
    final res = await _dio.getUri<String>(Uri.parse(url));
    return _parseCards(res.data ?? '');
  }

  @override
  Future<VideoDetail> fetchDetail(String detailUrl) async {
    final res = await _dio.getUri<String>(Uri.parse(detailUrl));
    final html = res.data ?? '';

    final titleRaw = _firstGroup(_titleTagRe, html) ?? '';
    final title = titleRaw.split('-').first.trim();

    final cover = _firstGroup(_videoPosterRe, html);

    return VideoDetail(
      siteId: info.id,
      title: title.isEmpty ? detailUrl : title,
      detailUrl: detailUrl,
      sources: [
        EpisodeSource(
          label: '正片',
          episodes: [Episode(label: '播放', ref: detailUrl)],
        ),
      ],
      cover: cover,
    );
  }

  @override
  Future<ResolvedSource> resolve(Episode ep) async {
    final res = await _dio.getUri<String>(Uri.parse(ep.ref));
    final html = res.data ?? '';
    final m = _hlsUrlRe.firstMatch(html);
    if (m == null) {
      throw Exception('hlsUrl 未找到');
    }
    return ResolvedSource(
      url: m.group(1)!,
      headers: {
        'User-Agent': _kBrowserUA,
        'Referer': '${info.baseUrl}/',
      },
    );
  }

  @override
  Map<String, String> thumbHeaders() => {
        'Referer': '${info.baseUrl}/',
        'User-Agent': _kBrowserUA,
      };

  List<VideoSummary> _parseCards(String html) {
    final thumbBySlug = <String, String>{};
    for (final m in _imgPairRe.allMatches(html)) {
      thumbBySlug.putIfAbsent(m.group(1)!, () => _decodeHtml(m.group(2)!));
    }
    final out = <VideoSummary>[];
    final seen = <String>{};
    for (final m in _titleLinkRe.allMatches(html)) {
      final slug = m.group(1)!;
      if (!seen.add(slug)) continue;
      final title = _decodeHtml(m.group(2)!);
      out.add(VideoSummary(
        siteId: info.id,
        title: title,
        detailUrl: '${info.baseUrl}/videos/$slug/',
        thumb: thumbBySlug[slug],
      ));
    }
    return out;
  }
}

String? _firstGroup(RegExp re, String s) => re.firstMatch(s)?.group(1);

final _imgPairRe = RegExp(
  r'href="https://jp\.jable\.tv/videos/([^/]+)/"[\s\S]{0,400}?data-src="([^"]+)"',
);
final _titleLinkRe = RegExp(
  r'<h6[^>]*\bclass="title"[^>]*>\s*<a[^>]+href="https://jp\.jable\.tv/videos/([^/]+)/"[^>]*>([^<]+)</a>',
);
final _hlsUrlRe = RegExp(
  r'''var\s+hlsUrl\s*=\s*['"]([^'"]+\.m3u8[^'"]*)['"]''',
);
final _titleTagRe = RegExp(r'<title>([^<]*)</title>', caseSensitive: false);
final _videoPosterRe = RegExp(
  r'<video[^>]*\bposter="([^"]+)"',
);

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
  return out.trim();
}
