import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';

import '../../data/match_detail_source.dart';
import '../../models/channel.dart';
import '../../models/match_detail.dart';
import '../../providers/match_detail_provider.dart';

const _streamHeaders = {
  'Referer': 'https://fb168168.com/',
  'User-Agent':
      'Mozilla/5.0 (iPhone; CPU iPhone OS 18_5 like Mac OS X) '
      'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.5 '
      'Mobile/15E148 Safari/604.1',
};

Widget _buildSmallSpinner(BuildContext context) {
  return const Center(
    child: SizedBox(
      width: 24,
      height: 24,
      child: CircularProgressIndicator(strokeWidth: 2),
    ),
  );
}

final _liveControlsTheme = MaterialVideoControlsThemeData(
  displaySeekBar: false,
  seekOnDoubleTap: false,
  seekGesture: false,
  automaticallyImplySkipNextButton: false,
  automaticallyImplySkipPreviousButton: false,
  bufferingIndicatorBuilder: _buildSmallSpinner,
  primaryButtonBar: const [
    Spacer(),
    MaterialPlayOrPauseButton(iconSize: 56.0),
    Spacer(),
  ],
  bottomButtonBar: const [
    Spacer(),
    MaterialFullscreenButton(),
  ],
);

class LivePlayerScreen extends StatelessWidget {
  const LivePlayerScreen({super.key, required this.channel});

  final Channel channel;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (ctx) =>
          MatchDetailProvider(ctx.read<MatchDetailSource>())
            ..load(channel.matchId, channel.videoType),
      child: _LivePlayerView(channel: channel),
    );
  }
}

class _LivePlayerView extends StatefulWidget {
  const _LivePlayerView({required this.channel});

  final Channel channel;

  @override
  State<_LivePlayerView> createState() => _LivePlayerViewState();
}

class _LivePlayerViewState extends State<_LivePlayerView> {
  late final Player _player = Player();
  late final VideoController _controller = VideoController(_player);
  String? _currentUrl;
  final List<StreamSubscription<dynamic>> _subs = [];

  @override
  void initState() {
    super.initState();
    _subs.add(
      _player.stream.error.listen((e) {
        // libmpv 这版 build 不含 osc 模块，media_kit 内部设置 osc 属性时会抛，
        // 属于已知噪音，忽略。
        if (e.contains('property not found')) return;
        debugPrint('[live-player] error: $e  url=$_currentUrl');
      }),
    );
    _subs.add(
      _player.stream.log.listen((log) {
        if (log.level == 'error' || log.level == 'warn') {
          debugPrint('[live-player] ${log.level}: ${log.text}');
        }
      }),
    );
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _player.dispose();
    super.dispose();
  }

  void _syncStream(MatchStream? stream) {
    final url = stream?.url;
    if (url == null || url.isEmpty) return;
    if (url == _currentUrl) return;
    _currentUrl = url;
    _player.open(Media(url, httpHeaders: _streamHeaders));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        titleSpacing: 0,
        title: Text(
          widget.channel.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 14),
        ),
      ),
      body: Consumer<MatchDetailProvider>(
        builder: (context, p, _) {
          if (p.loading && p.detail == null) {
            return _buildSmallSpinner(context);
          }
          if (p.error != null && p.detail == null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  '加载失败：${p.error}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white54),
                ),
              ),
            );
          }
          final detail = p.detail;
          if (detail == null || detail.streams.isEmpty) {
            return const Center(
              child: Text(
                '暂无可播放信号源',
                style: TextStyle(color: Colors.white54),
              ),
            );
          }
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => _syncStream(p.selectedStream),
          );
          return SingleChildScrollView(
            child: Column(
              children: [
                AspectRatio(
                  aspectRatio: 16 / 9,
                  child: MaterialVideoControlsTheme(
                    normal: _liveControlsTheme,
                    fullscreen: _liveControlsTheme,
                    child: Video(
                      controller: _controller,
                      controls: (state) => Stack(
                        fit: StackFit.expand,
                        children: [
                          MaterialVideoControls(state),
                          _PausedOverlay(player: state.widget.controller.player),
                        ],
                      ),
                    ),
                  ),
                ),
                _ScoreBar(detail: detail),
                _StreamSwitcher(
                  streams: detail.streams,
                  selectedIndex: p.selectedIndex,
                  onSelect: p.select,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _PausedOverlay extends StatelessWidget {
  const _PausedOverlay({required this.player});

  final Player player;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<bool>(
      stream: player.stream.playing,
      initialData: player.state.playing,
      builder: (context, snap) {
        final playing = snap.data ?? false;
        if (playing) return const SizedBox.shrink();
        return Center(
          child: Material(
            color: Colors.transparent,
            child: InkResponse(
              onTap: player.play,
              radius: 36,
              child: Container(
                width: 64,
                height: 64,
                decoration: const BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.play_arrow,
                  size: 40,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ScoreBar extends StatelessWidget {
  const _ScoreBar({required this.detail});

  final MatchDetail detail;

  @override
  Widget build(BuildContext context) {
    final status = detail.minutes.isNotEmpty
        ? '${detail.statusName} ${detail.minutes}\''
        : detail.statusName;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: Colors.black,
      child: Row(
        children: [
          Expanded(
            child: _TeamCell(
              name: detail.homeTeamName,
              logo: detail.homeTeamLogo,
              alignRight: true,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${detail.homeScore} - ${detail.awayScore}',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  status,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                ),
              ],
            ),
          ),
          Expanded(
            child: _TeamCell(
              name: detail.awayTeamName,
              logo: detail.awayTeamLogo,
              alignRight: false,
            ),
          ),
        ],
      ),
    );
  }
}

class _TeamCell extends StatelessWidget {
  const _TeamCell({
    required this.name,
    required this.logo,
    required this.alignRight,
  });

  final String name;
  final String logo;
  final bool alignRight;

  @override
  Widget build(BuildContext context) {
    final children = [
      if (logo.isNotEmpty)
        Image.network(
          logo,
          width: 28,
          height: 28,
          errorBuilder: (_, _, _) => const SizedBox(width: 28, height: 28),
        )
      else
        const SizedBox(width: 28, height: 28),
      const SizedBox(width: 8),
      Flexible(
        child: Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 14),
        ),
      ),
    ];
    return Row(
      mainAxisAlignment: alignRight
          ? MainAxisAlignment.end
          : MainAxisAlignment.start,
      children: alignRight ? children.reversed.toList() : children,
    );
  }
}

class _StreamSwitcher extends StatelessWidget {
  const _StreamSwitcher({
    required this.streams,
    required this.selectedIndex,
    required this.onSelect,
  });

  final List<MatchStream> streams;
  final int selectedIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      color: const Color(0xFF111111),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            for (var i = 0; i < streams.length; i++)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _StreamChip(
                  stream: streams[i],
                  selected: i == selectedIndex,
                  onTap: () => onSelect(i),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _StreamChip extends StatelessWidget {
  const _StreamChip({
    required this.stream,
    required this.selected,
    required this.onTap,
  });

  final MatchStream stream;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final label = stream.commentatorName.isNotEmpty
        ? stream.commentatorName
        : '信号源 ${stream.id}';
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? Colors.redAccent : Colors.white12,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            if (stream.commentatorAvatar.isNotEmpty) ...[
              CircleAvatar(
                radius: 10,
                backgroundImage: NetworkImage(stream.commentatorAvatar),
              ),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : Colors.white70,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
