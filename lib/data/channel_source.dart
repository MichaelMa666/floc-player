import '../models/channel.dart';
import '../services/api_client.dart';

abstract class ChannelSource {
  Future<List<Channel>> fetch();
}

class ApiChannelSource implements ChannelSource {
  ApiChannelSource(this._client);

  final ApiClient _client;

  @override
  Future<List<Channel>> fetch() async {
    final resp = await _client.dio.get(
      '/api/v1/index/index',
      queryParameters: {'x': DateTime.now().millisecondsSinceEpoch},
    );
    final body = (resp.data as Map).cast<String, dynamic>();
    final data = (body['data'] as Map).cast<String, dynamic>();
    final result = (data['result'] as Map?)?.cast<String, dynamic>();
    final hotLive = (result?['hot_live'] as List?) ?? const [];
    return hotLive
        .map((e) => Channel.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }
}
