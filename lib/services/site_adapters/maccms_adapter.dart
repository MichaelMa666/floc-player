import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';

import '../../models/site_models.dart';
import 'site_adapter.dart';

const _kBrowserUA =
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/147.0.0.0 Safari/537.36';

/// 苹果 CMS（MaCMS）模板的通用适配器。
/// 列表/详情卡走 `<a class="...lazyload..." href="/detail/{id}.html" title=".." data-original="..">`；
/// 详情页含 `/play/{id}-{src}-{ep}.html` 的剧集；
/// 播放页内嵌 `player_aaaa = {"url":"...m3u8",...}` JSON。
class MacCmsAdapter implements SiteAdapter {
  MacCmsAdapter({
    required this.info,
    Dio? dio,
    this.sourceKeywords,
  }) : _dio = dio ?? _defaultDio();

  @override
  final SiteInfo info;

  /// 线路白名单（按子串匹配）。为 null 时不过滤。
  /// 比如 zsledzm 实测只有"免费观看"能放，其他线路 CDN 地域屏蔽，全部过掉省得用户点中失败。
  final List<String>? sourceKeywords;

  final Dio _dio;

  static Dio _defaultDio() => Dio(
        BaseOptions(
          headers: {
            'User-Agent': _kBrowserUA,
            'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
            'Accept-Language': 'zh-CN,zh;q=0.9',
            'Cache-Control': 'no-cache',
            'Pragma': 'no-cache',
            'Sec-Fetch-Dest': 'document',
            'Sec-Fetch-Mode': 'navigate',
            'Sec-Fetch-Site': 'none',
            'Upgrade-Insecure-Requests': '1',
          },
          followRedirects: true,
          responseType: ResponseType.plain,
          connectTimeout: const Duration(seconds: 6),
          receiveTimeout: const Duration(seconds: 8),
        ),
      );

  List<SiteCategory>? _cachedCategories;

  @override
  Future<List<SiteCategory>> fetchCategories() async {
    if (_cachedCategories != null) return _cachedCategories!;
    final res = await _dio.getUri<String>(Uri.parse(info.baseUrl));
    final html = res.data ?? '';
    final seen = <String>{};
    final out = <SiteCategory>[];
    for (final m in _typeRe.allMatches(html)) {
      final id = m.group(1)!;
      if (!seen.add(id)) continue;
      out.add(SiteCategory(id: id, name: _decodeHtml(m.group(2)!)));
    }
    return _cachedCategories = out;
  }

  @override
  Future<List<VideoSummary>> fetchListing(
      {String? categoryId, int page = 1}) async {
    // 实测站点的分类页一次性返回 500+ 条结果，没有真正的分页 URL；
    // page > 1 直接当"到底了"返回空，避免 UI 误触发后续加载。
    if (page > 1) return const [];
    final url = categoryId == null
        ? info.baseUrl
        : '${info.baseUrl}/type/$categoryId.html';
    final res = await _dio.getUri<String>(Uri.parse(url));
    final body = res.data ?? '';
    if (body.length < 500) {
      throw Exception('${info.name} 暂时不可用（服务器返回空响应）');
    }
    return _parseCards(body);
  }

  @override
  Future<List<VideoSummary>> search(String query, {int page = 1}) async {
    if (page > 1) return const [];
    // MaCMS 标准搜索接口：13 个连字符是站方搜索表单的真实 action（form#search）。
    // 站方关闭网页搜索后会返回一个 "请使用APP搜索" 的提示页（含 mac_msg_jump），
    // 走这条 URL 我们能稳定识别该提示并抛错；如果走 `?wd=` 则只会拿到首页，
    // 解析出一堆假命中。
    final res = await _dio.getUri<String>(
      Uri.parse('${info.baseUrl}/search/-------------.html').replace(
        queryParameters: {'wd': query},
      ),
    );
    final body = res.data ?? '';
    if (body.contains('mac_msg_jump') ||
        body.contains('请使用APP') ||
        body.contains('搜索功能关闭')) {
      throw Exception('${info.name} 网页搜索已被站方关闭，请用分类浏览');
    }
    if (body.length < 500) {
      throw Exception('${info.name} 暂时不可用（服务器返回空响应）');
    }
    return _parseCards(body);
  }

  @override
  Future<VideoDetail> fetchDetail(String detailUrl) async {
    final res = await _dio.getUri<String>(Uri.parse(detailUrl));
    final html = res.data ?? '';

    final rawTitle = _firstGroup(_titleRe, html) ?? '';
    final cleanTitle = _decodeHtml(rawTitle.split(RegExp(r'[\|\-]')).first.trim());

    String? cover;
    final coverM = _coverRe.firstMatch(html);
    if (coverM != null) {
      cover = _decodeHtml(coverM.group(1)!);
    }

    final srcNames = _extractSourceNames(html);

    final bySrc = <String, List<Episode>>{};
    final seenHref = <String>{};
    for (final m in _episodeRe.allMatches(html)) {
      final href = m.group(1)!;
      if (!seenHref.add(href)) continue;
      final src = m.group(3)!;
      final label = _decodeHtml(m.group(5)!).trim();
      if (label.isEmpty || label.contains('立即')) continue;
      bySrc.putIfAbsent(src, () => []).add(
            Episode(label: label, ref: _abs(href)),
          );
    }

    var sources = [
      for (final id in bySrc.keys)
        EpisodeSource(
          label: srcNames[id] ?? '线路 $id',
          episodes: bySrc[id]!,
        ),
    ]..sort((a, b) => _sourceRank(a.label).compareTo(_sourceRank(b.label)));

    if (sourceKeywords != null && sourceKeywords!.isNotEmpty) {
      sources = sources
          .where((s) => sourceKeywords!.any((kw) => s.label.contains(kw)))
          .toList();
    }

    return VideoDetail(
      siteId: info.id,
      title: cleanTitle.isEmpty ? detailUrl : cleanTitle,
      detailUrl: detailUrl,
      sources: sources,
      cover: cover,
    );
  }

  @override
  Future<ResolvedSource> resolve(Episode ep) async {
    final res = await _dio.getUri<String>(Uri.parse(ep.ref));
    final html = res.data ?? '';
    final m = _playerCfgRe.firstMatch(html);
    if (m == null) {
      throw Exception('player_aaaa 未找到 (${info.id})');
    }
    final cfg = jsonDecode(m.group(1)!) as Map<String, dynamic>;
    final url = cfg['url'] as String?;
    if (url == null || url.isEmpty) {
      throw Exception('player_aaaa.url 为空');
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
    final out = <VideoSummary>[];
    final seen = <String>{};
    for (final m in _cardRe.allMatches(html)) {
      final href = m.group(1)!;
      if (!seen.add(href)) continue;
      final title = _decodeHtml(m.group(2)!);
      final thumb = _decodeHtml(m.group(3)!);
      out.add(VideoSummary(
        siteId: info.id,
        title: title,
        detailUrl: _abs(href),
        thumb: thumb.isEmpty ? null : thumb,
      ));
    }
    return out;
  }

  String _abs(String href) {
    if (href.startsWith('http')) return href;
    if (href.startsWith('/')) return '${info.baseUrl}$href';
    return '${info.baseUrl}/$href';
  }

  /// 详情页的线路是按段排布的：
  /// `<h3 class="title"...>名字</h3>` 之后紧跟一组 `/play/{id}-{src}-{ep}.html` 链接。
  /// 把"名字"映射到该段第一个 src ID。
  Map<String, String> _extractSourceNames(String html) {
    final out = <String, String>{};
    String? pendingName;
    for (final m in _titleOrPlayRe.allMatches(html)) {
      final name = m.group(1);
      final src = m.group(2);
      if (name != null) {
        pendingName = _decodeHtml(name).trim();
      } else if (src != null && pendingName != null) {
        out.putIfAbsent(src, () => pendingName!);
      }
    }
    return out;
  }
}

/// 越小越靠前。HD / 免费 / 高清 优先；腾讯/优酷/爱奇艺/搜狐 这种第三方云播沉底。
int _sourceRank(String label) {
  final l = label.toLowerCase();
  if (l.contains('hd') || label.contains('免费') || label.contains('高清') ||
      label.contains('蓝光')) {
    return 0;
  }
  if (label.contains('腾讯') || label.contains('优酷') ||
      label.contains('爱奇艺') || label.contains('芒果') ||
      label.contains('搜狐') || label.contains('云播')) {
    return 100;
  }
  return 50;
}

final _cardRe = RegExp(
  r'''<a[^>]*\blazyload\b[^>]*\bhref="(/detail/\d+\.html)"[^>]*\btitle="([^"]*)"[^>]*\bdata-original="([^"]*)"''',
);
final _episodeRe = RegExp(
  r'<a[^>]+href="(/play/(\d+)-(\d+)-(\d+)\.html)"[^>]*>([^<]*)</a>',
);
final _playerCfgRe = RegExp(
  r'player_aaaa\s*=\s*(\{[^<]+?\})\s*</script>',
  dotAll: true,
);
final _titleRe = RegExp(r'<title>([^<]*)</title>', caseSensitive: false);
final _coverRe = RegExp(
  r'<a[^>]*\blazyload\b[^>]*\bdata-original="([^"]+)"',
);
final _typeRe = RegExp(
  r'<a[^>]+href="/type/(\d+)(?:-\d+)?\.html"[^>]*>([^<]+)</a>',
);
// 顺序扫：要么是源标题 <h3 class="title">...>名字</h3>，要么是 /play/{id}-{src}-{ep}.html
final _titleOrPlayRe = RegExp(
  r'<h3 class="title"[^>]*>(?:<[^>]+>)*([^<]+)</h3>'
  r'|<a[^>]+href="/play/\d+-(\d+)-\d+\.html"',
);

String? _firstGroup(RegExp re, String s) {
  final m = re.firstMatch(s);
  return m?.group(1);
}

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
