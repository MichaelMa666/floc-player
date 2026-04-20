import 'dart:io';

import 'package:path_provider/path_provider.dart';

abstract class VideoSource {
  Future<Directory> baseDir();
  Future<List<String>> scan();
  Future<void> delete(String path);
}

class FileSystemVideoSource implements VideoSource {
  FileSystemVideoSource({String subDir = 'floc-player-videos'})
    : _subDir = subDir;

  final String _subDir;
  Directory? _cachedBase;

  @override
  Future<Directory> baseDir() async {
    final cached = _cachedBase;
    if (cached != null) return cached;
    final dir = Directory(await _resolveBasePath());
    if (!await dir.exists()) {
      try {
        await dir.create(recursive: true);
      } catch (_) {
        // 权限未授予时 create 会失败，这里吞掉，UI 侧走未授权分支。
      }
    }
    _cachedBase = dir;
    return dir;
  }

  Future<String> _resolveBasePath() async {
    // Android：公共根目录 /sdcard/<subDir>，用户可见、文件管理器可访问。
    // 其它平台：app 文档目录下的子目录。
    if (Platform.isAndroid) {
      return '/sdcard/$_subDir';
    }
    final base = await getApplicationDocumentsDirectory();
    return '${base.path}/$_subDir';
  }

  @override
  Future<List<String>> scan() async {
    final dir = await baseDir();
    if (!await dir.exists()) return const [];
    final entries = dir.listSync(followLinks: false);
    final files = <String>[];
    for (final e in entries) {
      if (e is File && e.path.toLowerCase().endsWith('.mp4')) {
        files.add(e.path);
      }
    }
    files.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return files;
  }

  @override
  Future<void> delete(String path) async {
    final f = File(path);
    if (await f.exists()) {
      await f.delete();
    }
  }
}
