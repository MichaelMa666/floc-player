import 'dart:convert';

/// 一条播放历史。涵盖两种来源：
/// - `site`: 来自某个站点适配器的剧集，重播需要 adapter 重新 resolve（jable 这种签名 URL 必走）。
/// - `paste`: 用户粘贴的 m3u8/mp4 直链，重播直接用存的 url。
class PlayHistoryEntry {
  const PlayHistoryEntry({
    required this.id,
    required this.kind,
    required this.title,
    required this.lastPlayedAt,
    this.thumb,
    this.lastPosition,
    this.duration,
    this.siteId,
    this.siteName,
    this.detailUrl,
    this.episodeRef,
    this.episodeLabel,
    this.url,
    this.referer,
    this.userAgent,
  });

  final String id;
  final String kind; // 'site' | 'paste'
  final String title;
  final String? thumb;
  final DateTime lastPlayedAt;
  final Duration? lastPosition;
  final Duration? duration;

  // kind == 'site'
  final String? siteId;
  final String? siteName;
  final String? detailUrl;
  final String? episodeRef;
  final String? episodeLabel;

  // kind == 'paste'
  final String? url;
  final String? referer;
  final String? userAgent;

  bool get isSite => kind == 'site';
  bool get isPaste => kind == 'paste';

  static String siteIdOf(String siteId, String detailUrl, String episodeRef) =>
      'site:$siteId|$detailUrl|$episodeRef';

  static String pasteIdOf(String url) => 'paste:$url';

  PlayHistoryEntry copyWith({
    DateTime? lastPlayedAt,
    Duration? lastPosition,
    Duration? duration,
    String? thumb,
    String? title,
  }) {
    return PlayHistoryEntry(
      id: id,
      kind: kind,
      title: title ?? this.title,
      thumb: thumb ?? this.thumb,
      lastPlayedAt: lastPlayedAt ?? this.lastPlayedAt,
      lastPosition: lastPosition ?? this.lastPosition,
      duration: duration ?? this.duration,
      siteId: siteId,
      siteName: siteName,
      detailUrl: detailUrl,
      episodeRef: episodeRef,
      episodeLabel: episodeLabel,
      url: url,
      referer: referer,
      userAgent: userAgent,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind,
        'title': title,
        'thumb': thumb,
        'lastPlayedAt': lastPlayedAt.toIso8601String(),
        'lastPositionMs': lastPosition?.inMilliseconds,
        'durationMs': duration?.inMilliseconds,
        'siteId': siteId,
        'siteName': siteName,
        'detailUrl': detailUrl,
        'episodeRef': episodeRef,
        'episodeLabel': episodeLabel,
        'url': url,
        'referer': referer,
        'userAgent': userAgent,
      };

  factory PlayHistoryEntry.fromJson(Map<String, dynamic> j) {
    Duration? dur(String key) {
      final v = j[key];
      return v is int ? Duration(milliseconds: v) : null;
    }

    return PlayHistoryEntry(
      id: j['id'] as String,
      kind: j['kind'] as String,
      title: (j['title'] as String?) ?? '',
      thumb: j['thumb'] as String?,
      lastPlayedAt:
          DateTime.tryParse((j['lastPlayedAt'] as String?) ?? '') ?? DateTime.now(),
      lastPosition: dur('lastPositionMs'),
      duration: dur('durationMs'),
      siteId: j['siteId'] as String?,
      siteName: j['siteName'] as String?,
      detailUrl: j['detailUrl'] as String?,
      episodeRef: j['episodeRef'] as String?,
      episodeLabel: j['episodeLabel'] as String?,
      url: j['url'] as String?,
      referer: j['referer'] as String?,
      userAgent: j['userAgent'] as String?,
    );
  }

  static List<PlayHistoryEntry> decodeList(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    final data = jsonDecode(raw);
    if (data is! List) return const [];
    return [
      for (final i in data)
        if (i is Map<String, dynamic>) PlayHistoryEntry.fromJson(i),
    ];
  }

  static String encodeList(List<PlayHistoryEntry> items) =>
      jsonEncode([for (final i in items) i.toJson()]);
}
