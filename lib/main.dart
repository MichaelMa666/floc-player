import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'data/channel_source.dart';
import 'data/match_detail_source.dart';
import 'data/video_source.dart';
import 'services/api_client.dart';
import 'services/auth_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  final prefs = await SharedPreferences.getInstance();
  final authService = AuthService(prefs);
  await authService.loadFromPrefs();

  final apiClient = ApiClient(
    tokenReader: () => authService.token,
    tokenRefresher: authService.refresh,
    hostGetter: () => authService.currentHost,
  );
  final channelSource = ApiChannelSource(apiClient);
  final matchDetailSource = ApiMatchDetailSource(apiClient);
  final videoSource = FileSystemVideoSource();

  runApp(
    FlocPlayerApp(
      authService: authService,
      channelSource: channelSource,
      matchDetailSource: matchDetailSource,
      videoSource: videoSource,
      prefs: prefs,
    ),
  );
}
