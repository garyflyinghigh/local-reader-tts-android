import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'services/tts/tts_handler.dart';
import 'views/shelf/shelf_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final audioHandler = await AudioService.init(
    builder: MyTtsAudioHandler.new,
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.android_reader.tts',
      androidNotificationChannelName: '听书播放',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
      androidNotificationIcon: 'mipmap/ic_launcher',
    ),
  );

  runApp(
    ProviderScope(
      overrides: [
        ttsAudioHandlerProvider.overrideWithValue(audioHandler),
      ],
      child: const ReaderApp(),
    ),
  );
}

class ReaderApp extends StatelessWidget {
  const ReaderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: '本地听书',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2E6F57)),
        useMaterial3: true,
      ),
      home: const ShelfPage(),
    );
  }
}
