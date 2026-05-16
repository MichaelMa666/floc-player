import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../models/online_video.dart';
import '../models/play_history.dart';
import '../models/site_models.dart';
import '../providers/play_history_provider.dart';
import 'site_registry.dart';

/// 把一条播放历史还原成可播放的 OnlineVideo 并跳转到播放器。
/// 站点条目会重新调用 adapter.resolve 拿新 m3u8（应对签名 URL）；
/// 粘贴条目直接复用记录的 url + headers。
Future<void> replayHistory(BuildContext context, PlayHistoryEntry e) async {
  final history = context.read<PlayHistoryProvider>();
  final messenger = ScaffoldMessenger.of(context);

  if (e.isPaste) {
    final url = e.url;
    if (url == null || url.isEmpty) {
      messenger.showSnackBar(const SnackBar(content: Text('链接已失效')));
      return;
    }
    final updated = await history.recordPaste(
      url: url,
      title: e.title,
      thumb: e.thumb,
      referer: e.referer,
      userAgent: e.userAgent,
    );
    if (!context.mounted) return;
    context.push(
      '/online/player',
      extra: OnlineVideo(
        url: url,
        title: e.title,
        referer: e.referer,
        userAgent: e.userAgent,
        addedAt: e.lastPlayedAt,
        historyId: updated.id,
        lastPosition: updated.lastPosition,
        duration: updated.duration,
        thumb: e.thumb,
      ),
    );
    return;
  }

  // site
  final adapter = context.read<SiteRegistry>().byId(e.siteId ?? '');
  if (adapter == null || e.detailUrl == null || e.episodeRef == null) {
    messenger.showSnackBar(const SnackBar(content: Text('站点已不可用')));
    return;
  }
  try {
    final src = await adapter.resolve(
      Episode(label: e.episodeLabel ?? '', ref: e.episodeRef!),
    );
    if (!context.mounted) return;
    final updated = await history.recordSite(
      siteId: e.siteId!,
      siteName: e.siteName ?? adapter.info.name,
      detailUrl: e.detailUrl!,
      episodeRef: e.episodeRef!,
      episodeLabel: e.episodeLabel ?? '',
      title: e.title,
      thumb: e.thumb,
    );
    if (!context.mounted) return;
    context.push(
      '/online/player',
      extra: OnlineVideo(
        url: src.url,
        title: e.title,
        referer: src.headers['Referer'],
        userAgent: src.headers['User-Agent'],
        addedAt: e.lastPlayedAt,
        historyId: updated.id,
        lastPosition: updated.lastPosition,
        duration: updated.duration,
        thumb: e.thumb,
      ),
    );
  } catch (err) {
    messenger.showSnackBar(SnackBar(content: Text('解析失败：$err')));
  }
}
