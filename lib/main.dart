import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'services/settings_service.dart';
import 'services/whisper_cpp_service.dart';
import 'viewmodels/transcription_view_model.dart';
import 'views/transcription_view.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    ChangeNotifierProvider<TranscriptionViewModel>(
      create: (_) => TranscriptionViewModel(
        transcriptionService: WhisperCppService(),
        settingsService: SettingsService(),
      )..loadSettings(),
      child: const Mp3ToTextApp(),
    ),
  );
}

class Mp3ToTextApp extends StatelessWidget {
  const Mp3ToTextApp({super.key});

  // Deep ink blue: the app turns voice into written text.
  static const Color _seedColor = Color(0xFF1F5C73);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MP3 vers texte',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'Segoe UI',
        colorScheme: ColorScheme.fromSeed(seedColor: _seedColor),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        fontFamily: 'Segoe UI',
        colorScheme: ColorScheme.fromSeed(
          seedColor: _seedColor,
          brightness: Brightness.dark,
        ),
      ),
      home: const TranscriptionView(),
    );
  }
}
