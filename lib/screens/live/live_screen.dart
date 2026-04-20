import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../providers/live_provider.dart';
import '../../widgets/live_channel_card.dart';

class LiveScreen extends StatefulWidget {
  const LiveScreen({super.key});

  @override
  State<LiveScreen> createState() => _LiveScreenState();
}

class _LiveScreenState extends State<LiveScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  Future<void> _bootstrap() async {
    final auth = context.read<AuthProvider>();
    if (!auth.isAuthenticated) {
      await auth.ensureAuthenticated();
    }
    if (!mounted || !auth.isAuthenticated) return;
    await context.read<LiveProvider>().load();
  }

  Future<void> _refresh() async {
    final auth = context.read<AuthProvider>();
    if (!auth.isAuthenticated) {
      await auth.ensureAuthenticated();
    }
    if (!mounted || !auth.isAuthenticated) return;
    await context.read<LiveProvider>().load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('热门直播'), centerTitle: false),
      body: Consumer2<AuthProvider, LiveProvider>(
        builder: (context, auth, live, _) {
          final initialLoading =
              auth.loading || (live.loading && live.channels.isEmpty);
          if (initialLoading) return const _LoadingView();

          return RefreshIndicator(
            onRefresh: _refresh,
            child: _buildContent(auth, live),
          );
        },
      ),
    );
  }

  Widget _buildContent(AuthProvider auth, LiveProvider live) {
    if (!auth.isAuthenticated) {
      return _ScrollableMessage(
        message: '登录失败：${auth.error ?? ''}',
      );
    }
    if (live.error != null && live.channels.isEmpty) {
      return _ScrollableMessage(
        message: '加载失败：${live.error}',
      );
    }
    if (live.channels.isEmpty) {
      return const _ScrollableMessage(message: '暂无直播');
    }
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: live.channels.length,
      separatorBuilder: (_, _) =>
          const Divider(height: 1, color: Colors.white10),
      itemBuilder: (context, i) {
        final ch = live.channels[i];
        return LiveChannelCard(
          channel: ch,
          onTap: () => context.push('/live/player', extra: ch),
        );
      },
    );
  }
}

class _LoadingView extends StatelessWidget {
  const _LoadingView();
  @override
  Widget build(BuildContext context) => const Center(
    child: SizedBox(
      width: 24,
      height: 24,
      child: CircularProgressIndicator(strokeWidth: 2),
    ),
  );
}

class _ScrollableMessage extends StatelessWidget {
  const _ScrollableMessage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white54),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
