/// 一个视频站点的入口信息（注册时静态填）。
class SiteInfo {
  const SiteInfo({
    required this.id,
    required this.name,
    required this.baseUrl,
  });

  final String id;        // 'maccms_zsledzm' / 'jable' / 'fofo22'
  final String name;      // 显示名
  final String baseUrl;   // 'https://www.zsledzm.com'
}

/// 分类（电影/电视剧/...）。
class SiteCategory {
  const SiteCategory({required this.id, required this.name});

  final String id;
  final String name;
}

/// 列表项（首页/分类/搜索结果）。
class VideoSummary {
  const VideoSummary({
    required this.siteId,
    required this.title,
    required this.detailUrl,
    this.thumb,
    this.subtitle,
  });

  final String siteId;
  final String title;
  final String detailUrl;
  final String? thumb;
  final String? subtitle; // 类型/年份/集数等附加信息
}

/// 详情（含一组源 / 一组集）。
class VideoDetail {
  const VideoDetail({
    required this.siteId,
    required this.title,
    required this.detailUrl,
    required this.sources,
    this.cover,
    this.description,
  });

  final String siteId;
  final String title;
  final String detailUrl;
  final String? cover;
  final String? description;
  final List<EpisodeSource> sources; // 一个站可能给多个"线路"
}

/// 一条线路下的所有集。
class EpisodeSource {
  const EpisodeSource({
    required this.label,
    required this.episodes,
  });

  final String label;             // '线路1' / 'wjm3u8' / '高清'
  final List<Episode> episodes;
}

/// 一集，[ref] 由适配器自定义，resolve 时回传。
class Episode {
  const Episode({
    required this.label,
    required this.ref,
  });

  final String label;             // '第1集' / '正片'
  final String ref;               // 适配器内部用：play 页 URL / sid / m3u8 等
}

/// 解析后的可播放源。
class ResolvedSource {
  const ResolvedSource({
    required this.url,
    this.headers = const {},
    this.expiresAt,
  });

  final String url;
  final Map<String, String> headers;
  final DateTime? expiresAt;      // null 表示不过期
}
