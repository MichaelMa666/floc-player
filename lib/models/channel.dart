class Channel {
  const Channel({
    required this.id,
    required this.matchId,
    required this.videoType,
    required this.title,
    required this.coverUrl,
    required this.startTime,
    required this.competitionName,
    required this.homeTeamName,
    required this.homeTeamLogo,
    required this.awayTeamName,
    required this.awayTeamLogo,
    required this.commentatorName,
    required this.commentatorAvatar,
  });

  final int id;
  final int matchId;
  final int videoType;
  final String title;
  final String coverUrl;
  final DateTime startTime;
  final String competitionName;
  final String homeTeamName;
  final String homeTeamLogo;
  final String awayTeamName;
  final String awayTeamLogo;
  final String commentatorName;
  final String commentatorAvatar;

  factory Channel.fromJson(Map<String, dynamic> json) {
    final match = (json['match'] as Map?)?.cast<String, dynamic>() ?? const {};
    final commentators = (json['commentators'] as List?) ?? const [];
    final commentator = commentators.isNotEmpty
        ? (commentators.first as Map).cast<String, dynamic>()
        : const <String, dynamic>{};
    final startSec = (json['live_start_time'] as num?)?.toInt() ?? 0;
    return Channel(
      id: (json['id'] as num).toInt(),
      matchId:
          (json['match_id'] as num?)?.toInt() ??
          (match['match_id'] as num?)?.toInt() ??
          (match['id'] as num?)?.toInt() ??
          0,
      videoType: (json['video_type'] as num?)?.toInt() ?? 1,
      title: (json['video_title'] as String?) ?? '',
      coverUrl: (json['cover_url'] as String?) ?? '',
      startTime: DateTime.fromMillisecondsSinceEpoch(startSec * 1000),
      competitionName: (match['competition_name'] as String?) ?? '',
      homeTeamName: (match['home_team_name'] as String?) ?? '',
      homeTeamLogo: (match['home_team_logo'] as String?) ?? '',
      awayTeamName: (match['away_team_name'] as String?) ?? '',
      awayTeamLogo: (match['away_team_logo'] as String?) ?? '',
      commentatorName: (commentator['nickname'] as String?) ?? '',
      commentatorAvatar: (commentator['avatar'] as String?) ?? '',
    );
  }
}
