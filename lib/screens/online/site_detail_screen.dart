import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../models/online_video.dart';
import '../../models/site_models.dart';
import '../../providers/play_history_provider.dart';
import '../../services/site_adapters/site_adapter.dart';
import '../../services/site_registry.dart';

class SiteDetailScreen extends StatefulWidget {
  const SiteDetailScreen({
    super.key,
    required this.siteId,
    required this.summary,
  });

  final String siteId;
  final VideoSummary summary;

  @override
  State<SiteDetailScreen> createState() => _SiteDetailScreenState();
}

class _SiteDetailScreenState extends State<SiteDetailScreen> {
  late final SiteAdapter _adapter;
  Future<VideoDetail>? _future;
  int _selectedSource = 0;
  bool _resolving = false;

  @override
  void initState() {
    super.initState();
    _adapter = context.read<SiteRegistry>().requireById(widget.siteId);
    _load();
  }

  void _load() {
    setState(() {
      _future = _adapter.fetchDetail(widget.summary.detailUrl);
    });
  }

  Future<void> _playEpisode(VideoDetail detail, Episode ep) async {
    if (_resolving) return;
    setState(() => _resolving = true);
    final messenger = ScaffoldMessenger.of(context);
    final historyProvider = context.read<PlayHistoryProvider>();
    try {
      final src = await _adapter.resolve(ep);
      if (!mounted) return;
      final entry = await historyProvider.recordSite(
        siteId: _adapter.info.id,
        siteName: _adapter.info.name,
        detailUrl: detail.detailUrl,
        episodeRef: ep.ref,
        episodeLabel: ep.label,
        title: '${detail.title} · ${ep.label}',
        thumb: detail.cover ?? widget.summary.thumb,
      );
      if (!mounted) return;
      final video = OnlineVideo(
        url: src.url,
        title: '${detail.title} · ${ep.label}',
        referer: src.headers['Referer'],
        userAgent: src.headers['User-Agent'],
        addedAt: DateTime.now(),
        historyId: entry.id,
        lastPosition: entry.lastPosition,
        duration: entry.duration,
        thumb: detail.cover ?? widget.summary.thumb,
      );
      context.push('/online/player', extra: video);
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('解析失败：$e')),
      );
    } finally {
      if (mounted) setState(() => _resolving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Text(
          widget.summary.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 14),
        ),
      ),
      body: FutureBuilder<VideoDetail>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            );
          }
          if (snap.hasError) {
            return _Error(message: '加载失败：${snap.error}', onRetry: _load);
          }
          final detail = snap.data;
          if (detail == null) {
            return _Error(message: '没拉到内容', onRetry: _load);
          }
          if (detail.sources.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('暂无可播放线路', style: TextStyle(color: Colors.white54)),
              ),
            );
          }
          final src = detail.sources[_selectedSource.clamp(0, detail.sources.length - 1)];
          return Stack(
            children: [
              ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  _Header(
                    detail: detail,
                    thumbHeaders: _adapter.thumbHeaders(),
                    coverAspectRatio: _adapter.cardAspectRatio,
                    coverFit: _adapter.cardImageFit,
                  ),
                  if (detail.sources.length > 1) ...[
                    const SizedBox(height: 16),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (var i = 0; i < detail.sources.length; i++)
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                label: Text(detail.sources[i].label),
                                selected: i == _selectedSource,
                                onSelected: (_) =>
                                    setState(() => _selectedSource = i),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final ep in src.episodes)
                        ActionChip(
                          label: Text(ep.label),
                          onPressed: () => _playEpisode(detail, ep),
                        ),
                    ],
                  ),
                ],
              ),
              if (_resolving)
                const ColoredBox(
                  color: Color(0x66000000),
                  child: Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.detail,
    required this.thumbHeaders,
    required this.coverAspectRatio,
    required this.coverFit,
  });

  final VideoDetail detail;
  final Map<String, String> thumbHeaders;
  final double coverAspectRatio;
  final BoxFit coverFit;

  @override
  Widget build(BuildContext context) {
    // 横版（3:2）封面给 180 宽；竖版（≈0.72）回到原先的 110 宽，避免占太多。
    final isLandscape = coverAspectRatio >= 1.0;
    final coverWidth = isLandscape ? 180.0 : 110.0;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: coverWidth,
          child: AspectRatio(
            aspectRatio: coverAspectRatio,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Container(
                color: const Color(0xFF1A1A1A),
                child: detail.cover == null
                    ? null
                    : Image.network(
                        detail.cover!,
                        headers: thumbHeaders,
                        fit: coverFit,
                        errorBuilder: (_, _, _) => const Center(
                          child: Icon(Icons.broken_image,
                              color: Colors.white24),
                        ),
                      ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                detail.title,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              if (detail.description != null) ...[
                const SizedBox(height: 8),
                Text(
                  detail.description!,
                  maxLines: 6,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: Colors.white60),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _Error extends StatelessWidget {
  const _Error({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white54)),
            const SizedBox(height: 12),
            FilledButton(onPressed: onRetry, child: const Text('重试')),
          ],
        ),
      ),
    );
  }
}
