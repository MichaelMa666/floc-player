class MatchStream {
  const MatchStream({
    required this.id,
    required this.title,
    required this.commentatorName,
    required this.commentatorAvatar,
    required this.url,
  });

  final int id;
  final String title;
  final String commentatorName;
  final String commentatorAvatar;
  final String url;

  static MatchStream? fromLiveJson(Map<String, dynamic> live) {
    final addresses = (live['addresses'] as List?) ?? const [];
    String url = '';
    for (final raw in addresses) {
      final addr = (raw as Map).cast<String, dynamic>();
      if ((addr['addr_type'] as num?)?.toInt() != 2) continue;
      final direct = (addr['addr_url'] as String?) ?? '';
      final multi = (addr['addr_multi'] as Map?)?.cast<String, dynamic>();
      final m3u8 = (multi?['m3u8'] as String?) ?? '';
      url = m3u8.isNotEmpty ? m3u8 : direct;
      break;
    }
    if (url.isEmpty) return null;

    final commentators = (live['commentators'] as List?) ?? const [];
    final commentator = commentators.isNotEmpty
        ? (commentators.first as Map).cast<String, dynamic>()
        : const <String, dynamic>{};

    return MatchStream(
      id: (live['id'] as num?)?.toInt() ?? 0,
      title: (live['video_title'] as String?) ?? '',
      commentatorName: (commentator['nickname'] as String?) ?? '',
      commentatorAvatar: (commentator['avatar'] as String?) ?? '',
      url: url,
    );
  }
}

class MatchDetail {
  const MatchDetail({
    required this.matchId,
    required this.competitionName,
    required this.homeTeamName,
    required this.homeTeamLogo,
    required this.awayTeamName,
    required this.awayTeamLogo,
    required this.statusName,
    required this.homeScore,
    required this.awayScore,
    required this.minutes,
    required this.streams,
  });

  final int matchId;
  final String competitionName;
  final String homeTeamName;
  final String homeTeamLogo;
  final String awayTeamName;
  final String awayTeamLogo;
  final String statusName;
  final int homeScore;
  final int awayScore;
  final String minutes;
  final List<MatchStream> streams;

  factory MatchDetail.fromJson(Map<String, dynamic> json) {
    final lives = (json['lives'] as List?) ?? const [];
    final streams = <MatchStream>[];
    for (final raw in lives) {
      final stream = MatchStream.fromLiveJson(
        (raw as Map).cast<String, dynamic>(),
      );
      if (stream != null) streams.add(stream);
    }
    return MatchDetail(
      matchId: (json['match_id'] as num?)?.toInt() ?? 0,
      competitionName: (json['competition_name'] as String?) ?? '',
      homeTeamName: (json['home_team_name'] as String?) ?? '',
      homeTeamLogo: (json['home_team_logo'] as String?) ?? '',
      awayTeamName: (json['away_team_name'] as String?) ?? '',
      awayTeamLogo: (json['away_team_logo'] as String?) ?? '',
      statusName: (json['status_name'] as String?) ?? '',
      homeScore: (json['home_normal_score'] as num?)?.toInt() ?? 0,
      awayScore: (json['away_normal_score'] as num?)?.toInt() ?? 0,
      minutes: (json['minutes'] as String?) ?? '',
      streams: streams,
    );
  }
}
