import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../providers/video_provider.dart';
import '../../widgets/video_card.dart';

class _PermissionRequired extends StatelessWidget {
  const _PermissionRequired({
    required this.onOpenSettings,
    required this.onRetry,
  });

  final Future<void> Function() onOpenSettings;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '需要"所有文件访问"权限',
              style: TextStyle(fontSize: 16, color: Colors.white),
            ),
            const SizedBox(height: 8),
            const Text(
              '开启后可以扫描 /sdcard/floc-player/videos/ 下的 mp4 文件',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.white54),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: onOpenSettings,
              child: const Text('去设置'),
            ),
            const SizedBox(height: 8),
            TextButton(onPressed: onRetry, child: const Text('已开启，重试')),
          ],
        ),
      ),
    );
  }
}

class VideoScreen extends StatefulWidget {
  const VideoScreen({super.key});

  @override
  State<VideoScreen> createState() => _VideoScreenState();
}

class _VideoScreenState extends State<VideoScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<VideoProvider>().load();
    });
  }

  Future<void> _refresh() => context.read<VideoProvider>().load();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('本地视频'),
        centerTitle: false,
        actions: [
          Consumer<VideoProvider>(
            builder: (context, p, _) => IconButton(
              icon: p.loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh),
              tooltip: '刷新',
              onPressed: p.loading ? null : _refresh,
            ),
          ),
        ],
      ),
      body: Consumer<VideoProvider>(
        builder: (context, p, _) {
          if (p.loading && p.items.isEmpty) {
            return const Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            );
          }
          if (p.permission == VideoPermissionState.denied) {
            return _PermissionRequired(
              onOpenSettings: p.openSystemSettings,
              onRetry: _refresh,
            );
          }
          if (p.error != null && p.items.isEmpty) {
            return _Message(text: '扫描失败：${p.error}');
          }
          if (p.items.isEmpty) {
            final dir = p.baseDirPath;
            return _Message(
              text: dir == null ? '暂无视频' : '把 mp4 文件放到:\n$dir',
            );
          }
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: p.items.length,
              separatorBuilder: (_, _) =>
                  const Divider(height: 1, color: Colors.white10),
              itemBuilder: (ctx, i) {
                final v = p.items[i];
                return VideoCard(
                  video: v,
                  onTap: () => context.push('/video/player', extra: v),
                  onDelete: () => p.remove(v.path),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                text,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white54),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
