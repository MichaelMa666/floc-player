import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

class VideoThumbnailCache {
  VideoThumbnailCache._();
  static final VideoThumbnailCache instance = VideoThumbnailCache._();

  final Map<String, Uint8List> _memory = {};
  final Map<String, Future<Uint8List?>> _pending = {};
  Directory? _diskDir;

  Future<Directory> _diskCacheDir() async {
    final cached = _diskDir;
    if (cached != null) return cached;
    final base = await getTemporaryDirectory();
    final dir = Directory('${base.path}/video-thumbs');
    if (!await dir.exists()) await dir.create(recursive: true);
    _diskDir = dir;
    return dir;
  }

  String _diskKey(String videoPath) {
    final h = videoPath.hashCode.toUnsigned(32).toRadixString(16);
    final len = videoPath.length;
    return 'thumb_${h}_$len.jpg';
  }

  Future<Uint8List?> get(String videoPath) {
    final memHit = _memory[videoPath];
    if (memHit != null) return Future.value(memHit);
    final pending = _pending[videoPath];
    if (pending != null) return pending;
    final future = _load(videoPath);
    _pending[videoPath] = future;
    future.whenComplete(() => _pending.remove(videoPath));
    return future;
  }

  Future<Uint8List?> _load(String videoPath) async {
    final dir = await _diskCacheDir();
    final diskFile = File('${dir.path}/${_diskKey(videoPath)}');
    if (await diskFile.exists()) {
      final bytes = await diskFile.readAsBytes();
      _memory[videoPath] = bytes;
      return bytes;
    }
    try {
      final bytes = await VideoThumbnail.thumbnailData(
        video: videoPath,
        imageFormat: ImageFormat.JPEG,
        maxWidth: 320,
        quality: 70,
      );
      if (bytes == null || bytes.isEmpty) return null;
      _memory[videoPath] = bytes;
      unawaited(diskFile.writeAsBytes(bytes, flush: false));
      return bytes;
    } catch (_) {
      return null;
    }
  }

  void evict(String videoPath) {
    _memory.remove(videoPath);
    _pending.remove(videoPath);
    _diskCacheDir().then((dir) {
      final f = File('${dir.path}/${_diskKey(videoPath)}');
      f.exists().then((exists) {
        if (exists) f.delete();
      });
    });
  }
}
