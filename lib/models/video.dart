class VideoItem {
  const VideoItem({
    required this.path,
    required this.name,
    this.lastPosition,
    this.duration,
  });

  final String path;
  final String name;
  final Duration? lastPosition;
  final Duration? duration;

  VideoItem copyWith({
    Duration? lastPosition,
    Duration? duration,
    bool clearLastPosition = false,
  }) {
    return VideoItem(
      path: path,
      name: name,
      lastPosition: clearLastPosition
          ? null
          : (lastPosition ?? this.lastPosition),
      duration: duration ?? this.duration,
    );
  }

  static String basename(String path) {
    final sep = path.lastIndexOf('/');
    final fileName = sep >= 0 ? path.substring(sep + 1) : path;
    final dot = fileName.lastIndexOf('.');
    return dot > 0 ? fileName.substring(0, dot) : fileName;
  }
}
