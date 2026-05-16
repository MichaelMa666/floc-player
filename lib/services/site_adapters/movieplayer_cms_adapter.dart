import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';

import '../../models/site_models.dart';
import 'site_adapter.dart';

const _kBrowserUA =
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/147.0.0.0 Safari/537.36';

/// 列表卡的两种已知样式。
enum MoviePlayerCmsCardStyle {
  /// fofo22-style:
  ///   `<a class="thumbnail" href="/cat/id"><img src="thumb">` +
  ///   `<h2><a href="/cat/id">title</a></h2>`
  thumbnailH2,

  /// agoys-style（Tailwind grid）:
  ///   `<a href="/cat/id"><img alt="video" src="thumb">...<span class="...text-[#FAC33D]...">title</span></a>`
  altVideoSpan,
}

/// 通用 "MoviePlayer CMS" 模板适配器（fofo22 / agoys 等同款）。
///
/// 模板特征：
/// - 详情页内嵌 `var urlList = {...}` 或 `var urlList = decryptDict({...})`
/// - 字典结构: `{ source: [name, ...], url_list: [[ {sid, title, episode, ...}, ... ], ...] }`
/// - 单集解析：`POST /source/` body `id=<sid>` 返回纯文本 m3u8 URL
///
/// 已知差异通过参数适配：
/// - `obfuscated`: fofo22 字典经 Caesar -1 + JSON 包装；agoys 明文
/// - `categoryUrlTemplate`: fofo22 `/{cat}`；agoys `/type/{cat}`
/// - `cardStyle`: 列表卡 HTML 结构差异
class MoviePlayerCmsAdapter implements SiteAdapter {
  MoviePlayerCmsAdapter({
    required this.info,
    required this.categories,
    this.obfuscated = false,
    this.categoryUrlTemplate = '/{cat}',
    this.searchPath = '/search',
    this.searchParam = 'q',
    this.cardStyle = MoviePlayerCmsCardStyle.thumbnailH2,
    Dio? dio,
  }) : _dio = dio ?? _defaultDio() {
    final paths = categories.map((c) => RegExp.escape(c.id)).join('|');
    switch (cardStyle) {
      case MoviePlayerCmsCardStyle.thumbnailH2:
        _cardRe = RegExp(
          '<a[^>]+href="(/(?:$paths)/\\d+)"[^>]*\\bclass="thumbnail"[^>]*>'
          r'\s*<img[^>]+src="([^"]+)"',
        );
        _titleLinkRe = RegExp(
          '<h2[^>]*>\\s*<a[^>]+href="(/(?:$paths)/\\d+)"[^>]*>([^<]+)</a>\\s*</h2>',
        );
        _searchCardRe = null;
      case MoviePlayerCmsCardStyle.altVideoSpan:
        // 一条正则同时抓 (href, thumb, title)：从 <a href="/cat/id"> 起 → img alt="video" src
        // → 中间任意嵌套 → text-[#FAC33D] span 内的标题。
        _cardRe = RegExp(
          '<a[^>]+href="(/(?:$paths)/\\d+)"[^>]*>'
          r'\s*<img[^>]+alt="video"[^>]+src="([^"]+)"'
          r'[\s\S]{0,4000}?'
          r'text-\[#FAC33D\][^>]*>([^<]+)</span>',
        );
        _titleLinkRe = null;
        // agoys 的搜索页用了完全不同的 DOM（topic-details-card），
        // 卡片是 <a href="/cat/id">\n<div class="topic-details-card">…<img src=…>…<div class="topic-details-title">{title}</div>。
        _searchCardRe = RegExp(
          '<a[^>]+href="(/(?:$paths)/\\d+)"\\s*>\\s*'
          r'<div class="topic-details-card">[\s\S]*?'
          r'<img[^>]+src="([^"]+)"[\s\S]*?'
          r'<div class="topic-details-title">([^<]+)</div>',
          dotAll: true,
        );
    }
  }

  @override
  final SiteInfo info;

  /// 该站支持的分类（id 即详情链接里的路径前缀，比如 `dianying` / `anime`）。
  final List<SiteCategory> categories;

  /// 详情页的 urlList 是否被 Caesar -1 + decryptDict 包装。
  final bool obfuscated;

  /// 分类页 URL 模板，`{cat}` 会被替换为分类 id。
  final String categoryUrlTemplate;

  /// 搜索接口 URL 与参数名。
  final String searchPath;
  final String searchParam;

  /// 列表卡 HTML 风格。
  final MoviePlayerCmsCardStyle cardStyle;

  final Dio _dio;
  late final RegExp _cardRe;
  late final RegExp? _titleLinkRe;
  // 搜索结果页 DOM 与列表/分类页不一样时（agoys 是这样）就要用单独的正则。
  // null 表示沿用 _cardRe 处理列表页那套。
  late final RegExp? _searchCardRe;

  static Dio _defaultDio() => Dio(
        BaseOptions(
          headers: {
            'User-Agent': _kBrowserUA,
            'Accept':
                'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
            'Accept-Language': 'zh-CN,zh;q=0.9',
          },
          followRedirects: true,
          responseType: ResponseType.plain,
          connectTimeout: const Duration(seconds: 6),
          receiveTimeout: const Duration(seconds: 8),
        ),
      );

  @override
  Future<List<SiteCategory>> fetchCategories() async => categories;

  @override
  Future<List<VideoSummary>> fetchListing(
      {String? categoryId, int page = 1}) async {
    final base = categoryId == null
        ? info.baseUrl
        : '${info.baseUrl}${categoryUrlTemplate.replaceFirst('{cat}', categoryId)}';
    // fofo22 / agoys 都识别 `?page=N`（实测 `/dianying?page=2` 与
    // `/type/film?page=2` 都返回不同的结果集）。
    final url = page <= 1 ? base : '$base?page=$page';
    final res = await _dio.getUri<String>(Uri.parse(url));
    return _parseCards(res.data ?? '');
  }

  @override
  Future<List<VideoSummary>> search(String query, {int page = 1}) async {
    final params = <String, String>{searchParam: query};
    if (page > 1) params['page'] = '$page';
    final res = await _dio.getUri<String>(
      Uri.parse('${info.baseUrl}$searchPath')
          .replace(queryParameters: params),
    );
    return _parseSearchCards(res.data ?? '');
  }

  @override
  Future<VideoDetail> fetchDetail(String detailUrl) async {
    final res = await _dio.getUri<String>(Uri.parse(detailUrl));
    final html = res.data ?? '';

    final title = _decodeHtml(_firstGroup(_titleTagRe, html) ?? '')
        .split(RegExp(r'[\|\-]'))
        .first
        .trim();

    final cover = _firstGroup(_picRe, html);

    final dictText = _extractUrlListLiteral(html);
    if (dictText == null) {
      throw Exception('urlList 未找到');
    }

    Map<String, dynamic> decoded;
    if (obfuscated) {
      decoded = _decryptDict(dictText);
    } else {
      decoded =
          jsonDecode(dictText.replaceAll("'", '"')) as Map<String, dynamic>;
    }

    final sourceNames = (decoded['source'] as List?)
            ?.map((e) => e.toString())
            .toList() ??
        const <String>[];
    final urlList = (decoded['url_list'] as List?) ?? const [];

    final sources = <EpisodeSource>[];
    for (var i = 0; i < urlList.length; i++) {
      final eps = (urlList[i] as List).cast<Map>();
      final episodes = [
        for (final ep in eps)
          Episode(
            label: _episodeLabel(ep),
            ref: ep['sid'].toString(),
          ),
      ];
      sources.add(EpisodeSource(
        label: i < sourceNames.length ? sourceNames[i] : '线路 ${i + 1}',
        episodes: episodes,
      ));
    }

    return VideoDetail(
      siteId: info.id,
      title: title.isEmpty ? detailUrl : title,
      detailUrl: detailUrl,
      sources: sources,
      cover: cover,
    );
  }

  @override
  Future<ResolvedSource> resolve(Episode ep) async {
    final res = await _dio.post<String>(
      '${info.baseUrl}/source/',
      data: {'id': ep.ref},
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        headers: {
          'X-Requested-With': 'XMLHttpRequest',
          'Origin': info.baseUrl,
          'Referer': '${info.baseUrl}/',
        },
        responseType: ResponseType.plain,
      ),
    );
    final url = (res.data ?? '').trim();
    if (url.isEmpty || !url.startsWith('http')) {
      throw Exception('解析失败：返回非法 URL ($url)');
    }
    return ResolvedSource(
      url: url,
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

  @override
  double get cardAspectRatio => 0.72;

  @override
  BoxFit get cardImageFit => BoxFit.cover;

  List<VideoSummary> _parseCards(String html) {
    switch (cardStyle) {
      case MoviePlayerCmsCardStyle.thumbnailH2:
        return _parseThumbnailH2Cards(html);
      case MoviePlayerCmsCardStyle.altVideoSpan:
        return _parseAltVideoSpanCards(html);
    }
  }

  /// 搜索页和分类页 DOM 不同时（agoys 是这样）走这个；否则退回到列表卡解析。
  List<VideoSummary> _parseSearchCards(String html) {
    final re = _searchCardRe;
    if (re == null) return _parseCards(html);
    final out = <VideoSummary>[];
    final seen = <String>{};
    for (final m in re.allMatches(html)) {
      final href = m.group(1)!;
      if (!seen.add(href)) continue;
      final thumb = _decodeHtml(m.group(2)!);
      final title = _decodeHtml(m.group(3)!).trim();
      out.add(VideoSummary(
        siteId: info.id,
        title: title,
        detailUrl: href.startsWith('http') ? href : '${info.baseUrl}$href',
        thumb: thumb.isEmpty ? null : thumb,
      ));
    }
    return out;
  }

  /// fofo22 风格：href + thumb 来自 thumbnail anchor，title 来自 h2 anchor，按 href 配对。
  List<VideoSummary> _parseThumbnailH2Cards(String html) {
    final thumbByHref = <String, String>{};
    for (final m in _cardRe.allMatches(html)) {
      thumbByHref.putIfAbsent(m.group(1)!, () => _decodeHtml(m.group(2)!));
    }
    final out = <VideoSummary>[];
    final seen = <String>{};
    for (final m in _titleLinkRe!.allMatches(html)) {
      final href = m.group(1)!;
      if (!seen.add(href)) continue;
      final title = _decodeHtml(m.group(2)!);
      out.add(VideoSummary(
        siteId: info.id,
        title: title,
        detailUrl: href.startsWith('http') ? href : '${info.baseUrl}$href',
        thumb: thumbByHref[href],
      ));
    }
    return out;
  }

  /// agoys 风格：一条正则同时拿 href / thumb / title。
  List<VideoSummary> _parseAltVideoSpanCards(String html) {
    final out = <VideoSummary>[];
    final seen = <String>{};
    for (final m in _cardRe.allMatches(html)) {
      final href = m.group(1)!;
      if (!seen.add(href)) continue;
      final thumb = _decodeHtml(m.group(2)!);
      final title = _decodeHtml(m.group(3)!);
      out.add(VideoSummary(
        siteId: info.id,
        title: title,
        detailUrl: href.startsWith('http') ? href : '${info.baseUrl}$href',
        thumb: thumb.isEmpty ? null : thumb,
      ));
    }
    return out;
  }

  String _episodeLabel(Map ep) {
    final t = ep['title'];
    if (t is String && t.trim().isNotEmpty) return t;
    if (t != null) return t.toString();
    final n = ep['episode'];
    final idx = n is int ? n : (n is String ? int.tryParse(n) : null);
    return idx != null ? '第${idx + 1}集' : '?';
  }
}

/// 提取 `var urlList = [decryptDict(]{...})`。
/// 如果有 `decryptDict(` 跳过它；总是返回 `{...}` 这一段。
String? _extractUrlListLiteral(String html) {
  final m = _urlListAssignRe.firstMatch(html);
  if (m == null) return null;
  // matchEnd 指向 `{` 的下一个字符；braceStart 指向 `{`
  final braceStart = m.end - 1;
  return _readBalanced(html, braceStart);
}

final _urlListAssignRe = RegExp(
  r'\burlList\s*=\s*(?:decryptDict\(\s*)?\{',
  dotAll: true,
);

String? _readBalanced(String html, int p0) {
  var depth = 0;
  String? quote;
  var escape = false;
  for (var i = p0; i < html.length; i++) {
    final c = html[i];
    if (quote != null) {
      if (escape) {
        escape = false;
      } else if (c == r'\') {
        escape = true;
      } else if (c == quote) {
        quote = null;
      }
      continue;
    }
    if (c == "'" || c == '"') {
      quote = c;
    } else if (c == '{' || c == '[') {
      depth++;
    } else if (c == '}' || c == ']') {
      depth--;
      if (depth == 0) return html.substring(p0, i + 1);
    }
  }
  return null;
}

/// 把 `{'tpvsdf': ['#xxx#', ...], 'vsm`mjtu': [...]}` 这种 Caesar 加密文本解开。
Map<String, dynamic> _decryptDict(String dictText) {
  final asJson = dictText.replaceAll("'", '"');
  final raw = jsonDecode(asJson);
  return _walk(raw) as Map<String, dynamic>;
}

dynamic _walk(dynamic v) {
  if (v is String) {
    final shifted = _caesarShift(v, -1);
    if (shifted.startsWith('"') && shifted.endsWith('"')) {
      try {
        return jsonDecode(shifted);
      } catch (_) {
        // fall through
      }
    }
    return shifted;
  }
  if (v is List) return v.map(_walk).toList();
  if (v is Map) {
    return <String, dynamic>{
      for (final entry in v.entries)
        _caesarShift(entry.key as String, -1): _walk(entry.value),
    };
  }
  return v;
}

String _caesarShift(String s, int delta) =>
    String.fromCharCodes(s.codeUnits.map((c) => c + delta));

String? _firstGroup(RegExp re, String s) => re.firstMatch(s)?.group(1);

final _titleTagRe = RegExp(r'<title>([^<]*)</title>', caseSensitive: false);
final _picRe = RegExp(r'pic:\s*"([^"]+)"');

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
