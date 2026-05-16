import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/play_history.dart';
import '../../providers/play_history_provider.dart';
import '../../services/play_history_replay.dart';
import '../../services/site_registry.dart';

class PlayHistoryScreen extends StatelessWidget {
  const PlayHistoryScreen({super.key});

  Future<bool?> _confirmClear(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空全部播放历史？'),
        content: const Text('此操作不可恢复'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('清空',
                style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('播放历史'),
        actions: [
          Consumer<PlayHistoryProvider>(
            builder: (context, p, _) => IconButton(
              icon: const Icon(Icons.delete_sweep),
              tooltip: '清空',
              onPressed: p.items.isEmpty
                  ? null
                  : () async {
                      final ok = await _confirmClear(context);
                      if (ok == true) {
                        await p.clear();
                      }
                    },
            ),
          ),
        ],
      ),
      body: Consumer<PlayHistoryProvider>(
        builder: (context, p, _) {
          if (p.items.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  '暂无播放记录',
                  style: TextStyle(color: Colors.white54),
                ),
              ),
            );
          }
          final registry = context.read<SiteRegistry>();
          return ListView.separated(
            padding: const EdgeInsets.only(bottom: 24),
            itemCount: p.items.length,
            separatorBuilder: (_, _) =>
                const Divider(height: 1, color: Colors.white10),
            itemBuilder: (ctx, i) {
              final entry = p.items[i];
              final headers = entry.isSite
                  ? (registry.byId(entry.siteId ?? '')?.thumbHeaders() ??
                      const <String, String>{})
                  : const <String, String>{};
              return Dismissible(
                key: ValueKey(entry.id),
                direction: DismissDirection.endToStart,
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 16),
                  color: Colors.redAccent,
                  child: const Icon(Icons.delete, color: Colors.white),
                ),
                onDismissed: (_) => p.remove(entry.id),
                child: _HistoryTile(
                  entry: entry,
                  thumbHeaders: headers,
                  onTap: () => replayHistory(context, entry),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({
    required this.entry,
    required this.thumbHeaders,
    required this.onTap,
  });

  final PlayHistoryEntry entry;
  final Map<String, String> thumbHeaders;
  final VoidCallback onTap;

  String _subtitle() {
    final parts = <String>[];
    if (entry.isSite && entry.siteName != null) parts.add(entry.siteName!);
    if (entry.isPaste && entry.url != null) {
      parts.add(Uri.tryParse(entry.url!)?.host ?? entry.url!);
    }
    parts.add(_fmtDate(entry.lastPlayedAt));
    final progress = _progressLabel();
    if (progress != null) parts.add(progress);
    return parts.join(' · ');
  }

  String? _progressLabel() {
    final pos = entry.lastPosition;
    final dur = entry.duration;
    if (pos == null || pos <= Duration.zero) return null;
    if (dur != null && dur > Duration.zero) {
      final pct = (pos.inMilliseconds * 100 / dur.inMilliseconds).round();
      return '已看 $pct%';
    }
    return '已看 ${_fmtDuration(pos)}';
  }

  static String _fmtDate(DateTime d) {
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inHours < 1) return '${diff.inMinutes}分钟前';
    if (diff.inDays < 1) return '${diff.inHours}小时前';
    if (diff.inDays < 7) return '${diff.inDays}天前';
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  static String _fmtDuration(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    if (d.inHours > 0) {
      final h = d.inHours;
      return '${h}h${(m % 60).toString().padLeft(2, '0')}m';
    }
    return '${m}m${s.toString().padLeft(2, '0')}s';
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: SizedBox(
        width: 56,
        height: 56,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: entry.thumb == null
              ? Container(
                  color: const Color(0xFF222222),
                  child: Icon(
                    entry.isSite ? Icons.live_tv : Icons.link,
                    color: Colors.white24,
                  ),
                )
              : Image.network(
                  entry.thumb!,
                  headers: thumbHeaders,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Container(
                    color: const Color(0xFF222222),
                    child: const Icon(Icons.broken_image,
                        color: Colors.white24, size: 18),
                  ),
                ),
        ),
      ),
      title: Text(
        entry.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 14),
      ),
      subtitle: Text(
        _subtitle(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 11, color: Colors.white54),
      ),
      trailing: const Icon(Icons.play_arrow, color: Colors.white60),
    );
  }
}
