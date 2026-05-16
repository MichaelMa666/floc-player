import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'models/channel.dart';
import 'models/online_video.dart';
import 'models/site_models.dart';
import 'models/video.dart';
import 'screens/home_screen.dart';
import 'screens/live/live_player_screen.dart';
import 'screens/live/live_screen.dart';
import 'screens/online/online_player_screen.dart';
import 'screens/online/online_screen.dart';
import 'screens/online/play_history_screen.dart';
import 'screens/online/site_detail_screen.dart';
import 'screens/online/site_listing_screen.dart';
import 'screens/online/site_search_screen.dart';
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
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/online',
              builder: (context, state) => const OnlineScreen(),
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
    GoRoute(
      path: '/online/player',
      pageBuilder: (context, state) {
        final video = state.extra as OnlineVideo;
        return MaterialPage(
          fullscreenDialog: true,
          child: OnlinePlayerScreen(video: video),
        );
      },
    ),
    GoRoute(
      path: '/online/history',
      builder: (context, state) => const PlayHistoryScreen(),
    ),
    GoRoute(
      path: '/online/site/:siteId',
      builder: (context, state) =>
          SiteListingScreen(siteId: state.pathParameters['siteId']!),
    ),
    GoRoute(
      path: '/online/site/:siteId/search',
      builder: (context, state) =>
          SiteSearchScreen(siteId: state.pathParameters['siteId']!),
    ),
    GoRoute(
      path: '/online/site/:siteId/detail',
      builder: (context, state) => SiteDetailScreen(
        siteId: state.pathParameters['siteId']!,
        summary: state.extra as VideoSummary,
      ),
    ),
  ],
);
