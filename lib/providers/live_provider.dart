import 'package:flutter/foundation.dart';

import '../data/channel_source.dart';
import '../models/channel.dart';

class LiveProvider extends ChangeNotifier {
  LiveProvider(this._source);

  final ChannelSource _source;

  List<Channel> _channels = const [];
  bool _loading = false;
  Object? _error;

  List<Channel> get channels => _channels;
  bool get loading => _loading;
  Object? get error => _error;

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _channels = await _source.fetch();
    } catch (e) {
      _error = e;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }
}
