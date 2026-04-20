import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'models/channel.dart';
import 'models/video.dart';
import 'screens/home_screen.dart';
import 'screens/live/live_player_screen.dart';
import 'screens/live/live_screen.dart';
import 'screens/video/video_player_screen.dart';
import 'screens/video/video_screen.dart';

final GoRouter appRouter = GoRouter(
  initialLocation: '/live',
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) =>
          HomeScreen(navigationShell: navigationShell),
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/live',
              builder: (context, state) => const LiveScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/video',
              builder: (context, state) => const VideoScreen(),
            ),
          ],
        ),
      ],
    ),
    GoRoute(
      path: '/live/player',
      pageBuilder: (context, state) {
        final channel = state.extra as Channel;
        return MaterialPage(
          fullscreenDialog: true,
          child: LivePlayerScreen(channel: channel),
        );
      },
    ),
    GoRoute(
      path: '/video/player',
      pageBuilder: (context, state) {
        final video = state.extra as VideoItem;
        return MaterialPage(
          fullscreenDialog: true,
          child: VideoPlayerScreen(video: video),
        );
      },
    ),
  ],
);
