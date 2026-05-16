import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/play_history.dart';

class PlayHistoryProvider extends ChangeNotifier {
  PlayHistoryProvider(this._prefs) {
    final list = PlayHistoryEntry.decodeList(_prefs.getString(_key)).toList();
    list.sort((a, b) => b.lastPlayedAt.compareTo(a.lastPlayedAt));
    _items = list;
  }

  static const _key = 'play_history_v1';

  final SharedPreferences _prefs;
  List<PlayHistoryEntry> _items = const [];

  List<PlayHistoryEntry> get items => _items;

  PlayHistoryEntry? byId(String id) {
    for (final e in _items) {
      if (e.id == id) return e;
    }
    return null;
  }

  Future<void> _persist() async {
    await _prefs.setString(_key, PlayHistoryEntry.encodeList(_items));
  }

  void _putFront(PlayHistoryEntry entry) {
    _items = [
      entry,
      for (final i in _items)
        if (i.id != entry.id) i,
    ];
  }

  Future<PlayHistoryEntry> recordSite({
    required String siteId,
    required String siteName,
    required String detailUrl,
    required String episodeRef,
    required String episodeLabel,
    required String title,
    String? thumb,
  }) async {
    final id = PlayHistoryEntry.siteIdOf(siteId, detailUrl, episodeRef);
    final existing = byId(id);
    final now = DateTime.now();
    final entry = existing != null
        ? existing.copyWith(
            lastPlayedAt: now,
            title: title,
            thumb: thumb ?? existing.thumb,
          )
        : PlayHistoryEntry(
            id: id,
            kind: 'site',
            title: title,
            thumb: thumb,
            lastPlayedAt: now,
            siteId: siteId,
            siteName: siteName,
            detailUrl: detailUrl,
            episodeRef: episodeRef,
            episodeLabel: episodeLabel,
          );
    _putFront(entry);
    await _persist();
    notifyListeners();
    return entry;
  }

  Future<PlayHistoryEntry> recordPaste({
    required String url,
    required String title,
    String? thumb,
    String? referer,
    String? userAgent,
  }) async {
    final id = PlayHistoryEntry.pasteIdOf(url);
    final existing = byId(id);
    final now = DateTime.now();
    final entry = existing != null
        ? existing.copyWith(lastPlayedAt: now, title: title, thumb: thumb)
        : PlayHistoryEntry(
            id: id,
            kind: 'paste',
            title: title,
            thumb: thumb,
            lastPlayedAt: now,
            url: url,
            referer: referer,
            userAgent: userAgent,
          );
    _putFront(entry);
    await _persist();
    notifyListeners();
    return entry;
  }

  Future<void> saveProgress(
    String id,
    Duration position, {
    Duration? duration,
  }) async {
    if (position < Duration.zero) return;
    final existing = byId(id);
    if (existing == null) return;
    final updated = existing.copyWith(
      lastPosition: position,
      duration: duration,
    );
    _items = [
      for (final i in _items)
        if (i.id == id) updated else i,
    ];
    await _persist();
    notifyListeners();
  }

  Future<void> remove(String id) async {
    _items = _items.where((e) => e.id != id).toList();
    await _persist();
    notifyListeners();
  }

  Future<void> clear() async {
    _items = const [];
    await _persist();
    notifyListeners();
  }
}
