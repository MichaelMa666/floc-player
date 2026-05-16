import '../models/site_models.dart';
import 'site_adapters/jable_adapter.dart';
import 'site_adapters/maccms_adapter.dart';
import 'site_adapters/missav_adapter.dart';
import 'site_adapters/movieplayer_cms_adapter.dart';
import 'site_adapters/site_adapter.dart';

/// 静态注册三个适配器；新加站点改这里。
class SiteRegistry {
  SiteRegistry._(this._adapters);

  factory SiteRegistry.defaults() {
    final adapters = <SiteAdapter>[
      MacCmsAdapter(
        info: const SiteInfo(
          id: 'maccms_zsledzm',
          name: '影视大全',
          baseUrl: 'https://www.zsledzm.com',
        ),
        // 实测只有"免费观看"线路能播；其他（高清不卡 / 腾讯云播 等）CDN 地域屏蔽。
        sourceKeywords: const ['免费观看'],
      ),
      MoviePlayerCmsAdapter(
        info: const SiteInfo(
          id: 'fofo22',
          name: 'FoFo 影院',
          baseUrl: 'https://fofo22.com',
        ),
        obfuscated: true,
        categoryUrlTemplate: '/{cat}',
        categories: const [
          SiteCategory(id: 'dianying', name: '电影'),
          SiteCategory(id: 'dianshiju', name: '电视剧'),
          SiteCategory(id: 'dongman', name: '动漫'),
          SiteCategory(id: 'zongyi', name: '综艺'),
        ],
      ),
      MoviePlayerCmsAdapter(
        info: const SiteInfo(
          id: 'agoys',
          name: 'ago 影院',
          baseUrl: 'https://www.agoys.com',
        ),
        obfuscated: false,
        categoryUrlTemplate: '/type/{cat}',
        cardStyle: MoviePlayerCmsCardStyle.altVideoSpan,
        categories: const [
          SiteCategory(id: 'film', name: '电影'),
          SiteCategory(id: 'tvseries', name: '电视剧'),
          SiteCategory(id: 'anime', name: '动漫'),
          SiteCategory(id: 'varietyshow', name: '综艺'),
        ],
      ),
      JableAdapter(
        info: const SiteInfo(
          id: 'jable',
          name: 'Jable.TV',
          baseUrl: 'https://jp.jable.tv',
        ),
      ),
      MissAvAdapter(
        info: const SiteInfo(
          id: 'missav',
          name: 'MissAV',
          baseUrl: 'https://missav.ai',
        ),
      ),
    ];
    return SiteRegistry._({for (final a in adapters) a.info.id: a});
  }

  final Map<String, SiteAdapter> _adapters;

  List<SiteAdapter> get all => _adapters.values.toList();
  List<SiteInfo> get sites => [for (final a in all) a.info];

  SiteAdapter? byId(String id) => _adapters[id];

  SiteAdapter requireById(String id) {
    final a = _adapters[id];
    if (a == null) throw StateError('未注册的站点: $id');
    return a;
  }
}
