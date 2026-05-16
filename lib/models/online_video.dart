import 'dart:convert';

class OnlineVideo {
  const OnlineVideo({
    required this.url,
    this.title,
    this.referer,
    this.userAgent,
    required this.addedAt,
    this.lastPlayedAt,
    this.lastPosition,
    this.duration,
    this.historyId,
    this.thumb,
  });

  final String url;
  final String? title;
  final String? referer;
  final String? userAgent;
  final DateTime addedAt;
  final DateTime? lastPlayedAt;
  final Duration? lastPosition;
  final Duration? duration;

  /// 关联的 [PlayHistoryEntry.id]。播放器据此向 PlayHistoryProvider 写进度。
  /// 不参与 [OnlineProvider] 的持久化（只在内存中传递）。
  final String? historyId;

  /// 历史回放时携带的缩略图，用于播放器（暂未使用，预留）。
  final String? thumb;

  String get displayTitle {
    final t = title?.trim();
    if (t != null && t.isNotEmpty) return t;
    final uri = Uri.tryParse(url);
    if (uri == null) return url;
    final segs = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segs.isNotEmpty) return segs.last;
    return uri.host.isNotEmpty ? uri.host : url;
  }

  OnlineVideo copyWith({
    String? title,
    String? referer,
    String? userAgent,
    DateTime? lastPlayedAt,
    Duration? lastPosition,
    Duration? duration,
    String? historyId,
    String? thumb,
  }) {
    return OnlineVideo(
      url: url,
      title: title ?? this.title,
      referer: referer ?? this.referer,
      userAgent: userAgent ?? this.userAgent,
      addedAt: addedAt,
      lastPlayedAt: lastPlayedAt ?? this.lastPlayedAt,
      lastPosition: lastPosition ?? this.lastPosition,
      duration: duration ?? this.duration,
      historyId: historyId ?? this.historyId,
      thumb: thumb ?? this.thumb,
    );
  }

  Map<String, dynamic> toJson() => {
        'url': url,
        'title': title,
        'referer': referer,
        'userAgent': userAgent,
        'addedAt': addedAt.toIso8601String(),
        'lastPlayedAt': lastPlayedAt?.toIso8601String(),
        'lastPositionMs': lastPosition?.inMilliseconds,
        'durationMs': duration?.inMilliseconds,
      };

  factory OnlineVideo.fromJson(Map<String, dynamic> json) {
    Duration? readDur(String key) {
      final v = json[key];
      return v is int ? Duration(milliseconds: v) : null;
    }

    DateTime? readDate(String key) {
      final v = json[key];
      return v is String ? DateTime.tryParse(v) : null;
    }

    return OnlineVideo(
      url: json['url'] as String,
      title: json['title'] as String?,
      referer: json['referer'] as String?,
      userAgent: json['userAgent'] as String?,
      addedAt: readDate('addedAt') ?? DateTime.now(),
      lastPlayedAt: readDate('lastPlayedAt'),
      lastPosition: readDur('lastPositionMs'),
      duration: readDur('durationMs'),
    );
  }

  static List<OnlineVideo> decodeList(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    final data = jsonDecode(raw);
    if (data is! List) return const [];
    return [
      for (final item in data)
        if (item is Map<String, dynamic>) OnlineVideo.fromJson(item),
    ];
  }

  static String encodeList(List<OnlineVideo> items) {
    return jsonEncode([for (final i in items) i.toJson()]);
  }
}
