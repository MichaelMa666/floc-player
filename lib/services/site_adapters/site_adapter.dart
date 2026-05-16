import 'package:flutter/widgets.dart';

import '../../models/site_models.dart';

/// 视频站点适配器接口。
///
/// 实现者负责：列表/搜索抓取、详情解析、单集解析为可播放 URL（含 headers）。
/// 所有方法都可能抛网络/解析异常，调用方应有兜底。
abstract class SiteAdapter {
  SiteInfo get info;

  /// 分类列表（无传入 → 首页/默认）。
  Future<List<SiteCategory>> fetchCategories() async => const [];

  /// 列表。[categoryId] 为 null 时取首页；[page] 从 1 开始。
  /// 不支持分页的站点应当在 page > 1 时返回空，让 UI 知道"到底了"。
  Future<List<VideoSummary>> fetchListing({String? categoryId, int page = 1});

  /// 搜索。[page] 从 1 开始；不支持分页时同上。
  Future<List<VideoSummary>> search(String query, {int page = 1});

  /// 详情，含可播放的集列表。
  Future<VideoDetail> fetchDetail(String detailUrl);

  /// 把单集解析为可播放 URL（含 Referer/UA 等）。
  Future<ResolvedSource> resolve(Episode ep);

  /// 缩略图请求需要的 headers（一般包含 Referer），用于 Image.network。
  Map<String, String> thumbHeaders() => const {};

  /// 列表卡缩略图的宽高比（width / height）。
  /// 竖版海报站（MaCMS / MoviePlayer 模板）默认 0.72（接近 5:7）；
  /// AV 站（jable / missav）覆盖为 3:2（实测 jable / missav 缩略图都是 800×538 / 330×222 这种比例）。
  double get cardAspectRatio => 0.72;

  /// 缩略图在卡片里的填充方式。
  /// - 竖版海报通常和卡片同比例，用 cover 没视觉损失；
  /// - 横版预览图源比例可能略有出入（3:2 / 16:9 / 4:3 都见过），
  ///   用 contain 保证"等比例缩放、不截断"，多出来的边框用卡片底色填充。
  BoxFit get cardImageFit => BoxFit.cover;
}
