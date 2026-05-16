import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';

import '../../models/online_video.dart';
import '../../providers/play_history_provider.dart';

const _kDefaultUserAgent =
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/147.0.0.0 Safari/537.36';

class OnlinePlayerScreen extends StatefulWidget {
  const OnlinePlayerScreen({super.key, required this.video});

  final OnlineVideo video;

  @override
  State<OnlinePlayerScreen> createState() => _OnlinePlayerScreenState();
}

class _OnlinePlayerScreenState extends State<OnlinePlayerScreen> {
  late final Player _player = Player();
  late final VideoController _controller = VideoController(_player);
  final List<StreamSubscription<dynamic>> _subs = [];
  PlayHistoryProvider? _historyProvider;
  Duration _lastDuration = Duration.zero;
  int _videoWidth = 0;
  int _videoHeight = 0;
  Timer? _saveTimer;
  bool _seeked = false;
  String? _fatalError;

  @override
  void initState() {
    super.initState();
    _subs.add(
      _player.stream.duration.listen((d) {
        _lastDuration = d;
        _maybeSeek();
      }),
    );
    _subs.add(_player.stream.width.listen((w) {
      if (w != null) _videoWidth = w;
    }));
    _subs.add(_player.stream.height.listen((h) {
      if (h != null) _videoHeight = h;
    }));
    _subs.add(_player.stream.error.listen((e) {
      if (e.contains('property not found')) return;
      debugPrint('[online-player] error: $e  url=${widget.video.url}');
      if (e.contains('Failed to open') || e.contains('No such') ||
          e.contains('forbidden') || e.contains('403')) {
        if (mounted) {
          setState(() => _fatalError = e);
        }
      }
    }));
    _subs.add(_player.stream.log.listen((log) {
      if (log.level == 'error' || log.level == 'warn') {
        debugPrint('[online-player] ${log.level}: ${log.text}');
      }
    }));

    _player.open(Media(widget.video.url, httpHeaders: _buildHeaders()));
    _saveTimer =
        Timer.periodic(const Duration(seconds: 5), (_) => _saveProgress());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _historyProvider = context.read<PlayHistoryProvider>();
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _saveProgress(useProviderRef: true);
    for (final s in _subs) {
      s.cancel();
    }
    _player.dispose();
    super.dispose();
  }

  Map<String, String> _buildHeaders() {
    return {
      'User-Agent': widget.video.userAgent?.trim().isNotEmpty == true
          ? widget.video.userAgent!.trim()
          : _kDefaultUserAgent,
      if (widget.video.referer?.trim().isNotEmpty == true)
        'Referer': widget.video.referer!.trim(),
    };
  }

  void _maybeSeek() {
    if (_seeked) return;
    final target = widget.video.lastPosition;
    if (target == null || target <= Duration.zero) {
      _seeked = true;
      return;
    }
    if (_lastDuration <= Duration.zero) return;
    final clamped = target >= _lastDuration
        ? _lastDuration - const Duration(seconds: 2)
        : target;
    if (clamped > Duration.zero) {
      _player.seek(clamped);
    }
    _seeked = true;
  }

  void _saveProgress({bool useProviderRef = false}) {
    final id = widget.video.historyId;
    if (id == null) return;
    final provider =
        useProviderRef ? _historyProvider : context.read<PlayHistoryProvider>();
    if (provider == null) return;
    final pos = _player.state.position;
    if (pos <= Duration.zero) return;
    final dur = _lastDuration > Duration.zero ? _lastDuration : null;
    provider.saveProgress(id, pos, duration: dur);
  }

  Future<void> _onEnterFullscreen() async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    final isPortrait =
        _videoHeight > 0 && _videoWidth > 0 && _videoHeight > _videoWidth;
    await Future.wait([
      SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.immersiveSticky,
        overlays: const [],
      ),
      SystemChrome.setPreferredOrientations(
        isPortrait
            ? const [
                DeviceOrientation.portraitUp,
                DeviceOrientation.portraitDown,
              ]
            : const [
                DeviceOrientation.landscapeLeft,
                DeviceOrientation.landscapeRight,
              ],
      ),
    ]);
  }

  Future<void> _onExitFullscreen() async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    await Future.wait([
      SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.manual,
        overlays: SystemUiOverlay.values,
      ),
      SystemChrome.setPreferredOrientations(const []),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        titleSpacing: 0,
        title: Text(
          widget.video.displayTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 14),
        ),
      ),
      body: SafeArea(
        top: false,
        bottom: true,
        minimum: const EdgeInsets.only(bottom: 8),
        child: Stack(
          children: [
            Center(
              child: MaterialVideoControlsTheme(
                normal: _gesturesTheme,
                fullscreen: _fullscreenGesturesTheme,
                child: Video(
                  controller: _controller,
                  onEnterFullscreen: _onEnterFullscreen,
                  onExitFullscreen: _onExitFullscreen,
                ),
              ),
            ),
            if (_fatalError != null)
              Positioned.fill(
                child: ColoredBox(
                  color: const Color(0xCC000000),
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.error_outline,
                              color: Colors.redAccent, size: 36),
                          const SizedBox(height: 8),
                          const Text(
                            '播放失败',
                            style: TextStyle(fontSize: 16),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _fatalError!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                fontSize: 12, color: Colors.white60),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            '可能是该线路被地域屏蔽或失效，返回后试试其他线路。',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 12, color: Colors.white60),
                          ),
                          const SizedBox(height: 12),
                          FilledButton(
                            onPressed: () => Navigator.of(context).maybePop(),
                            child: const Text('返回'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

Widget _levelIndicator(IconData icon, double value) {
  final pct = (value.clamp(0.0, 1.0) * 100).round();
  return Align(
    alignment: Alignment.topCenter,
    child: Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 14),
            const SizedBox(width: 6),
            SizedBox(
              width: 60,
              height: 3,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: value.clamp(0.0, 1.0),
                  backgroundColor: Colors.white24,
                  valueColor: const AlwaysStoppedAnimation(Colors.white),
                ),
              ),
            ),
            const SizedBox(width: 6),
            SizedBox(
              width: 30,
              child: Text(
                '$pct',
                textAlign: TextAlign.right,
                style: const TextStyle(color: Colors.white, fontSize: 11),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

Widget _volumeIndicator(BuildContext context, double value) =>
    _levelIndicator(Icons.volume_up, value);

Widget _brightnessIndicator(BuildContext context, double value) =>
    _levelIndicator(Icons.brightness_6, value);

Widget _speedUpIndicator(BuildContext context, double factor) {
  return Align(
    alignment: Alignment.topCenter,
    child: Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: const BoxDecoration(
          color: Colors.black54,
          shape: BoxShape.circle,
        ),
        child: const Icon(
          Icons.fast_forward,
          color: Colors.white,
          size: 14,
        ),
      ),
    ),
  );
}

Widget _buildSmallSpinner(BuildContext context) {
  return const Center(
    child: SizedBox(
      width: 24,
      height: 24,
      child: CircularProgressIndicator(strokeWidth: 2),
    ),
  );
}

// 进度条放大：
// - seekBarContainerHeight 是手势命中区高度（默认 36，太窄经常点不到）。
// - seekBarThumbSize 是拖拽小球（默认 12.8）。
// - seekBarHeight 是细条本身（默认 2.4）。
// 把命中区扩到 64、小球 20、细条 5，单手在底栏附近随意点都能拖到。
// controlsHoverDuration 从默认 3s 提到 5s，避免用户刚点完控件还没看清就消失。
const _kSeekBarContainerHeight = 64.0;
const _kSeekBarHeight = 5.0;
const _kSeekBarThumbSize = 20.0;
const _kControlsHoverDuration = Duration(seconds: 5);

const _gesturesTheme = MaterialVideoControlsThemeData(
  volumeGesture: true,
  brightnessGesture: true,
  seekGesture: true,
  seekOnDoubleTap: true,
  speedUpOnLongPress: true,
  speedUpFactor: 3.0,
  controlsHoverDuration: _kControlsHoverDuration,
  seekBarContainerHeight: _kSeekBarContainerHeight,
  seekBarHeight: _kSeekBarHeight,
  seekBarThumbSize: _kSeekBarThumbSize,
  speedUpIndicatorBuilder: _speedUpIndicator,
  volumeIndicatorBuilder: _volumeIndicator,
  brightnessIndicatorBuilder: _brightnessIndicator,
  bufferingIndicatorBuilder: _buildSmallSpinner,
);

final _fullscreenGesturesTheme =
    kDefaultMaterialVideoControlsThemeDataFullscreen.copyWith(
  speedUpOnLongPress: true,
  speedUpFactor: 3.0,
  controlsHoverDuration: _kControlsHoverDuration,
  seekBarContainerHeight: _kSeekBarContainerHeight,
  seekBarHeight: _kSeekBarHeight,
  seekBarThumbSize: _kSeekBarThumbSize,
  speedUpIndicatorBuilder: _speedUpIndicator,
  volumeIndicatorBuilder: _volumeIndicator,
  brightnessIndicatorBuilder: _brightnessIndicator,
  bufferingIndicatorBuilder: _buildSmallSpinner,
);
