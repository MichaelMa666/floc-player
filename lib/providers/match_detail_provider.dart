import 'package:flutter/foundation.dart';

import '../data/match_detail_source.dart';
import '../models/match_detail.dart';

class MatchDetailProvider extends ChangeNotifier {
  MatchDetailProvider(this._source);

  final MatchDetailSource _source;

  MatchDetail? _detail;
  bool _loading = false;
  Object? _error;
  int _selectedIndex = 0;

  MatchDetail? get detail => _detail;
  bool get loading => _loading;
  Object? get error => _error;
  int get selectedIndex => _selectedIndex;

  MatchStream? get selectedStream {
    final streams = _detail?.streams;
    if (streams == null || streams.isEmpty) return null;
    final i = _selectedIndex.clamp(0, streams.length - 1);
    return streams[i];
  }

  Future<void> load(int matchId, int videoType) async {
    debugPrint('[match-detail] load matchId=$matchId videoType=$videoType');
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _detail = await _source.fetch(matchId, videoType);
      if (_selectedIndex >= (_detail?.streams.length ?? 0)) {
        _selectedIndex = 0;
      }
    } catch (e) {
      _error = e;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  void select(int index) {
    if (_detail == null) return;
    if (index < 0 || index >= _detail!.streams.length) return;
    if (index == _selectedIndex) return;
    _selectedIndex = index;
    notifyListeners();
  }
}
