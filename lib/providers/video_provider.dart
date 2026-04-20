import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/video_source.dart';
import '../models/video.dart';
import '../services/video_thumbnail_cache.dart';

enum VideoPermissionState { unknown, granted, denied }

class VideoProvider extends ChangeNotifier {
  VideoProvider(this._source, this._prefs);

  static const _posPrefix = 'video.pos.';
  static const _durPrefix = 'video.dur.';

  final VideoSource _source;
  final SharedPreferences _prefs;

  List<VideoItem> _items = const [];
  bool _loading = false;
  Object? _error;
  String? _baseDirPath;
  VideoPermissionState _permission = VideoPermissionState.unknown;

  List<VideoItem> get items => _items;
  bool get loading => _loading;
  Object? get error => _error;
  String? get baseDirPath => _baseDirPath;
  VideoPermissionState get permission => _permission;

  Duration? _readPosition(String path) {
    final ms = _prefs.getInt('$_posPrefix$path');
    return ms == null ? null : Duration(milliseconds: ms);
  }

  Duration? _readDuration(String path) {
    final ms = _prefs.getInt('$_durPrefix$path');
    return ms == null ? null : Duration(milliseconds: ms);
  }

  Future<bool> _ensurePermission() async {
    if (!Platform.isAndroid) {
      _permission = VideoPermissionState.granted;
      return true;
    }
    final status = await Permission.manageExternalStorage.status;
    if (status.isGranted) {
      _permission = VideoPermissionState.granted;
      return true;
    }
    final result = await Permission.manageExternalStorage.request();
    _permission = result.isGranted
        ? VideoPermissionState.granted
        : VideoPermissionState.denied;
    return result.isGranted;
  }

  Future<void> openSystemSettings() {
    return openAppSettings();
  }

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final granted = await _ensurePermission();
      if (!granted) {
        _items = const [];
        _baseDirPath = null;
        return;
      }
      final dir = await _source.baseDir();
      _baseDirPath = dir.path;
      final paths = await _source.scan();
      _items = [
        for (final path in paths)
          VideoItem(
            path: path,
            name: VideoItem.basename(path),
            lastPosition: _readPosition(path),
            duration: _readDuration(path),
          ),
      ];
    } catch (e) {
      _error = e;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> saveProgress(
    String path,
    Duration position, {
    Duration? duration,
  }) async {
    if (position < Duration.zero) return;
    await _prefs.setInt('$_posPrefix$path', position.inMilliseconds);
    if (duration != null && duration > Duration.zero) {
      await _prefs.setInt('$_durPrefix$path', duration.inMilliseconds);
    }
    _items = [
      for (final i in _items)
        if (i.path == path)
          i.copyWith(lastPosition: position, duration: duration)
        else
          i,
    ];
    notifyListeners();
  }

  Future<void> remove(String path) async {
    await _source.delete(path);
    await _prefs.remove('$_posPrefix$path');
    await _prefs.remove('$_durPrefix$path');
    VideoThumbnailCache.instance.evict(path);
    _items = _items.where((i) => i.path != path).toList();
    notifyListeners();
  }
}
