import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/channel_source.dart';
import 'data/match_detail_source.dart';
import 'data/video_source.dart';
import 'providers/auth_provider.dart';
import 'providers/live_provider.dart';
import 'providers/video_provider.dart';
import 'router.dart';
import 'services/auth_service.dart';

class FlocPlayerApp extends StatelessWidget {
  const FlocPlayerApp({
    super.key,
    required this.authService,
    required this.channelSource,
    required this.matchDetailSource,
    required this.videoSource,
    required this.prefs,
  });

  final AuthService authService;
  final ChannelSource channelSource;
  final MatchDetailSource matchDetailSource;
  final VideoSource videoSource;
  final SharedPreferences prefs;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<MatchDetailSource>.value(value: matchDetailSource),
        ChangeNotifierProvider(create: (_) => AuthProvider(authService)),
        ChangeNotifierProvider(create: (_) => LiveProvider(channelSource)),
        ChangeNotifierProvider(
          create: (_) => VideoProvider(videoSource, prefs),
        ),
      ],
      child: MaterialApp.router(
        title: 'floc player',
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark(),
        routerConfig: appRouter,
      ),
    );
  }
}
