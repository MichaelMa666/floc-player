import '../models/match_detail.dart';
import '../services/api_client.dart';

abstract class MatchDetailSource {
  Future<MatchDetail> fetch(int matchId, int videoType);
}

class ApiMatchDetailSource implements MatchDetailSource {
  ApiMatchDetailSource(this._client);

  final ApiClient _client;

  @override
  Future<MatchDetail> fetch(int matchId, int videoType) async {
    final path = videoType == 2
        ? '/api/v1/basketball/match/detail'
        : '/api/v1/football/match/detail';
    final resp = await _client.dio.get(
      path,
      queryParameters: {
        'x': DateTime.now().millisecondsSinceEpoch,
        'match_id': matchId,
      },
    );
    final body = (resp.data as Map).cast<String, dynamic>();
    final data = (body['data'] as Map).cast<String, dynamic>();
    return MatchDetail.fromJson(data);
  }
}
