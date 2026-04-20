import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';

import '../../models/video.dart';
import '../../providers/video_provider.dart';

class VideoPlayerScreen extends StatefulWidget {
  const VideoPlayerScreen({super.key, required this.video});

  final VideoItem video;

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  late final Player _player = Player();
  late final VideoController _controller = VideoController(_player);
  final List<StreamSubscription<dynamic>> _subs = [];
  VideoProvider? _provider;
  Duration _lastDuration = Duration.zero;
  int _videoWidth = 0;
  int _videoHeight = 0;
  Timer? _saveTimer;
  bool _seeked = false;

  @override
  void initState() {
    super.initState();
    _subs.add(
      _player.stream.duration.listen((d) {
        _lastDuration = d;
        _maybeSeek();
      }),
    );
    _subs.add(
      _player.stream.width.listen((w) {
        if (w != null) _videoWidth = w;
      }),
    );
    _subs.add(
      _player.stream.height.listen((h) {
        if (h != null) _videoHeight = h;
      }),
    );
    _subs.add(
      _player.stream.error.listen((e) {
        debugPrint('[video-player] error: $e');
      }),
    );
    _player.open(Media(widget.video.path));
    _saveTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _saveProgress(),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _provider = context.read<VideoProvider>();
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
    final provider = useProviderRef ? _provider : context.read<VideoProvider>();
    if (provider == null) return;
    final pos = _player.state.position;
    if (pos <= Duration.zero) return;
    final dur = _lastDuration > Duration.zero ? _lastDuration : null;
    provider.saveProgress(widget.video.path, pos, duration: dur);
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
          widget.video.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 14),
        ),
      ),
      body: SafeArea(
        top: false,
        bottom: true,
        minimum: const EdgeInsets.only(bottom: 8),
        child: Center(
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

const _gesturesTheme = MaterialVideoControlsThemeData(
  volumeGesture: true,
  brightnessGesture: true,
  seekGesture: true,
  seekOnDoubleTap: true,
  speedUpOnLongPress: true,
  speedUpFactor: 3.0,
  speedUpIndicatorBuilder: _speedUpIndicator,
  volumeIndicatorBuilder: _volumeIndicator,
  brightnessIndicatorBuilder: _brightnessIndicator,
);

final _fullscreenGesturesTheme = kDefaultMaterialVideoControlsThemeDataFullscreen
    .copyWith(
      speedUpOnLongPress: true,
      speedUpFactor: 3.0,
      speedUpIndicatorBuilder: _speedUpIndicator,
      volumeIndicatorBuilder: _volumeIndicator,
      brightnessIndicatorBuilder: _brightnessIndicator,
    );
