import 'dart:io';

/// Configuration required to run a whisper.cpp transcription.
class TranscriptionSettings {
  const TranscriptionSettings({
    required this.whisperExecutablePath,
    required this.modelPath,
    required this.ffmpegExecutablePath,
    required this.language,
    required this.threadCount,
  });

  factory TranscriptionSettings.defaults() {
    return TranscriptionSettings(
      whisperExecutablePath: '',
      modelPath: '',
      ffmpegExecutablePath: '',
      language: 'fr',
      threadCount: defaultThreadCount(),
    );
  }

  /// Path to whisper-cli.exe (whisper.cpp command line tool).
  final String whisperExecutablePath;

  /// Path to a ggml model file, e.g. ggml-large-v3-turbo.bin.
  final String modelPath;

  /// Optional path to ffmpeg.exe. When empty, the MP3 file is passed
  /// directly to whisper.cpp, which decodes MP3 natively.
  final String ffmpegExecutablePath;

  /// Spoken language code passed to whisper.cpp ('fr' by default).
  final String language;

  /// Number of CPU threads used by whisper.cpp.
  final int threadCount;

  bool get isComplete =>
      whisperExecutablePath.isNotEmpty && modelPath.isNotEmpty;

  bool get usesFfmpeg => ffmpegExecutablePath.isNotEmpty;

  TranscriptionSettings copyWith({
    String? whisperExecutablePath,
    String? modelPath,
    String? ffmpegExecutablePath,
    String? language,
    int? threadCount,
  }) {
    return TranscriptionSettings(
      whisperExecutablePath:
          whisperExecutablePath ?? this.whisperExecutablePath,
      modelPath: modelPath ?? this.modelPath,
      ffmpegExecutablePath: ffmpegExecutablePath ?? this.ffmpegExecutablePath,
      language: language ?? this.language,
      threadCount: threadCount ?? this.threadCount,
    );
  }

  /// Leaves one core free for the UI; whisper.cpp gains little above 8.
  static int defaultThreadCount() {
    final int cores = Platform.numberOfProcessors;
    return (cores > 2 ? cores - 1 : cores).clamp(1, 8);
  }
}
