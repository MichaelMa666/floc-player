import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/video.dart';
import '../services/video_thumbnail_cache.dart';

class VideoCard extends StatelessWidget {
  const VideoCard({
    super.key,
    required this.video,
    required this.onTap,
    required this.onDelete,
  });

  final VideoItem video;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  static String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final pos = video.lastPosition;
    final dur = video.duration;
    double? progress;
    String? posLabel;
    if (pos != null && pos > Duration.zero) {
      posLabel = '上次 ${_fmt(pos)}';
      if (dur != null && dur.inMilliseconds > 0) {
        progress = pos.inMilliseconds / dur.inMilliseconds;
        if (progress >= 0.99) posLabel = '已看完';
      }
    }
    return InkWell(
      onTap: onTap,
      onLongPress: () => _showMenu(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                width: 160,
                height: 90,
                child: _Thumbnail(
                  videoPath: video.path,
                  progress: progress,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    video.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, color: Colors.white),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      if (dur != null)
                        Text(
                          _fmt(dur),
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.white70,
                          ),
                        ),
                      if (dur != null && posLabel != null)
                        const SizedBox(width: 8),
                      if (posLabel != null)
                        Text(
                          posLabel,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.white54,
                          ),
                        ),
                    ],
                  ),
                  if (progress != null) ...[
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(1),
                      child: LinearProgressIndicator(
                        value: progress.clamp(0.0, 1.0),
                        minHeight: 2,
                        backgroundColor: Colors.white12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showMenu(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1C1C1C),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(
                Icons.delete_outline,
                color: Colors.redAccent,
              ),
              title: const Text(
                '删除',
                style: TextStyle(color: Colors.redAccent),
              ),
              onTap: () {
                Navigator.of(ctx).pop();
                onDelete();
              },
            ),
            ListTile(
              leading: const Icon(Icons.close, color: Colors.white70),
              title: const Text('取消'),
              onTap: () => Navigator.of(ctx).pop(),
            ),
          ],
        ),
      ),
    );
  }
}

class _Thumbnail extends StatefulWidget {
  const _Thumbnail({required this.videoPath, this.progress});

  final String videoPath;
  final double? progress;

  @override
  State<_Thumbnail> createState() => _ThumbnailState();
}

class _ThumbnailState extends State<_Thumbnail> {
  Uint8List? _bytes;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  @override
  void didUpdateWidget(covariant _Thumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.videoPath != widget.videoPath) {
      _bytes = null;
      _loading = true;
      _fetch();
    }
  }

  Future<void> _fetch() async {
    final bytes = await VideoThumbnailCache.instance.get(widget.videoPath);
    if (!mounted) return;
    setState(() {
      _bytes = bytes;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Container(color: const Color(0xFF222222)),
        if (_bytes != null)
          Image.memory(_bytes!, fit: BoxFit.cover, gaplessPlayback: true)
        else if (!_loading)
          const Center(
            child: Icon(
              Icons.play_circle_outline,
              color: Colors.white54,
              size: 32,
            ),
          ),
        if (widget.progress != null)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: LinearProgressIndicator(
              value: widget.progress!.clamp(0.0, 1.0),
              minHeight: 2,
              backgroundColor: Colors.black38,
            ),
          ),
      ],
    );
  }
}
