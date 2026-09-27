import 'package:shared_preferences/shared_preferences.dart';

import '../models/transcription_settings.dart';

/// Persists TranscriptionSettings between application launches.
class SettingsService {
  static const String _whisperKey = 'whisperExecutablePath';
  static const String _modelKey = 'modelPath';
  static const String _ffmpegKey = 'ffmpegExecutablePath';
  static const String _languageKey = 'language';
  static const String _threadCountKey = 'threadCount';

  Future<TranscriptionSettings> load() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final TranscriptionSettings defaults = TranscriptionSettings.defaults();

    return TranscriptionSettings(
      whisperExecutablePath:
          prefs.getString(_whisperKey) ?? defaults.whisperExecutablePath,
      modelPath: prefs.getString(_modelKey) ?? defaults.modelPath,
      ffmpegExecutablePath:
          prefs.getString(_ffmpegKey) ?? defaults.ffmpegExecutablePath,
      language: prefs.getString(_languageKey) ?? defaults.language,
      threadCount: prefs.getInt(_threadCountKey) ?? defaults.threadCount,
    );
  }

  Future<void> save(TranscriptionSettings settings) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();

    await prefs.setString(_whisperKey, settings.whisperExecutablePath);
    await prefs.setString(_modelKey, settings.modelPath);
    await prefs.setString(_ffmpegKey, settings.ffmpegExecutablePath);
    await prefs.setString(_languageKey, settings.language);
    await prefs.setInt(_threadCountKey, settings.threadCount);
  }
}
