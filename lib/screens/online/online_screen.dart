import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../models/play_history.dart';
import '../../providers/play_history_provider.dart';
import '../../services/play_history_replay.dart';
import '../../services/site_registry.dart';

class OnlineScreen extends StatelessWidget {
  const OnlineScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('在线'),
        centerTitle: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: '播放历史',
            onPressed: () => context.push('/online/history'),
          ),
        ],
      ),
      body: Consumer<PlayHistoryProvider>(
        builder: (context, history, _) {
          final sites = context.read<SiteRegistry>().sites;
          final recents = history.items.take(8).toList();
          return ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              const _SectionTitle('站点'),
              SizedBox(
                height: 84,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: sites.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (ctx, i) {
                    final s = sites[i];
                    return SizedBox(
                      width: 130,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () => context.push('/online/site/${s.id}'),
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E1E1E),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                s.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                Uri.parse(s.baseUrl).host,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.white54,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const _SectionTitle('最近播放'),
              if (recents.isEmpty)
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 8, 16, 24),
                  child: Text(
                    '从站点选一集看，记录会出现在这里',
                    style: TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                )
              else
                ..._buildRecents(context, recents),
              if (history.items.length > recents.length)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: () => context.push('/online/history'),
                      child: const Text('查看全部历史 →'),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  List<Widget> _buildRecents(
    BuildContext context,
    List<PlayHistoryEntry> items,
  ) {
    final registry = context.read<SiteRegistry>();
    return [
      for (var i = 0; i < items.length; i++) ...[
        if (i > 0) const Divider(height: 1, color: Colors.white10),
        _RecentTile(
          entry: items[i],
          thumbHeaders: items[i].isSite
              ? (registry.byId(items[i].siteId ?? '')?.thumbHeaders() ??
                  const {})
              : const {},
          onTap: () => replayHistory(context, items[i]),
        ),
      ],
    ];
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        text,
        style: const TextStyle(fontSize: 13, color: Colors.white54),
      ),
    );
  }
}

class _RecentTile extends StatelessWidget {
  const _RecentTile({
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
    return null;
  }

  static String _fmtDate(DateTime d) {
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inHours < 1) return '${diff.inMinutes}分钟前';
    if (diff.inDays < 1) return '${diff.inHours}小时前';
    if (diff.inDays < 7) return '${diff.inDays}天前';
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
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
