import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../models/transcription_event.dart';
import '../models/transcription_exceptions.dart';
import '../models/transcription_settings.dart';
import '../services/settings_service.dart';
import '../services/transcription_service.dart';

enum TranscriptionStatus {
  idle,
  running,
  completed,
  failed,
  cancelled,
}

/// Holds the whole state of the transcription screen. The view only reads
/// this state and forwards user intents; it never talks to services.
class TranscriptionViewModel extends ChangeNotifier {
  TranscriptionViewModel({
    required TranscriptionService transcriptionService,
    required SettingsService settingsService,
  })  : _transcriptionService = transcriptionService,
        _settingsService = settingsService;

  final TranscriptionService _transcriptionService;
  final SettingsService _settingsService;

  TranscriptionSettings _settings = TranscriptionSettings.defaults();
  bool _settingsLoaded = false;
  String? _audioFilePath;
  TranscriptionStatus _status = TranscriptionStatus.idle;
  TranscriptionStage? _stage;
  double? _progress;
  final List<String> _liveSegments = <String>[];
  String _transcript = '';
  int _transcriptRevision = 0;
  Duration? _elapsed;
  String? _errorMessage;
  String? _errorDetails;
  StreamSubscription<TranscriptionEvent>? _subscription;
  bool _isDisposed = false;

  TranscriptionSettings get settings => _settings;
  bool get settingsLoaded => _settingsLoaded;
  String? get audioFilePath => _audioFilePath;
  String? get audioFileName =>
      _audioFilePath == null ? null : p.basename(_audioFilePath!);
  TranscriptionStatus get status => _status;
  TranscriptionStage? get stage => _stage;

  /// Null while the engine has not reported any progress yet.
  double? get progress => _progress;
  String get liveText => _liveSegments.join(' ');
  String get transcript => _transcript;

  /// Incremented when the transcript is replaced by the engine (not when
  /// the user edits it), so the view knows when to refresh its editor.
  int get transcriptRevision => _transcriptRevision;
  Duration? get elapsed => _elapsed;
  String? get errorMessage => _errorMessage;
  String? get errorDetails => _errorDetails;

  bool get isRunning => _status == TranscriptionStatus.running;
  bool get hasTranscript => _transcript.trim().isNotEmpty;

  bool get canStart =>
      _settingsLoaded &&
      _audioFilePath != null &&
      _settings.isComplete &&
      !isRunning;

  int get wordCount {
    final String text = _transcript.trim();
    return text.isEmpty ? 0 : text.split(RegExp(r'\s+')).length;
  }

  String get suggestedOutputFileName {
    final String? path = _audioFilePath;
    return path == null
        ? 'transcription.txt'
        : '${p.basenameWithoutExtension(path)}.txt';
  }

  Future<void> loadSettings() async {
    _settings = await _settingsService.load();
    _settingsLoaded = true;
    _notify();
  }

  Future<void> updateSettings(TranscriptionSettings settings) async {
    _settings = settings;
    _notify();
    await _settingsService.save(settings);
  }

  void selectAudioFile(String path) {
    if (isRunning) {
      return;
    }

    _audioFilePath = path;
    _status = TranscriptionStatus.idle;
    _clearResult();
    _notify();
  }

  void startTranscription() {
    final String? audioFilePath = _audioFilePath;

    if (audioFilePath == null || !canStart) {
      return;
    }

    _status = TranscriptionStatus.running;
    _clearResult();
    _notify();

    _subscription = _transcriptionService
        .transcribe(
          audioFilePath: audioFilePath,
          settings: _settings,
        )
        .listen(
          _onEvent,
          onError: _onError,
          onDone: _onDone,
        );
  }

  Future<void> cancelTranscription() async {
    if (!isRunning) {
      return;
    }

    await _transcriptionService.cancel();
  }

  /// Called on every keystroke in the transcript editor.
  void editTranscript(String text) {
    _transcript = text;
    _notify();
  }

  /// Writes the transcript as UTF-8 and returns the final path.
  Future<String> saveTranscript(String outputPath) async {
    final String path = p.extension(outputPath).toLowerCase() == '.txt'
        ? outputPath
        : '$outputPath.txt';

    await File(path).writeAsString(
      _transcript,
      encoding: utf8,
      flush: true,
    );

    return path;
  }

  void _onEvent(TranscriptionEvent event) {
    switch (event) {
      case TranscriptionStageChanged(:final TranscriptionStage stage):
        _stage = stage;
        _progress = null;
      case TranscriptionProgress(:final double fraction):
        _progress = fraction.clamp(0.0, 1.0);
      case TranscriptionSegment(:final String text):
        _liveSegments.add(text);
      case TranscriptionCompleted(
          :final String text,
          :final Duration elapsed,
        ):
        _transcript = text;
        _transcriptRevision++;
        _elapsed = elapsed;
        _progress = 1.0;
        _status = TranscriptionStatus.completed;
    }

    _notify();
  }

  void _onError(Object error) {
    if (error is TranscriptionCancelledException) {
      _status = TranscriptionStatus.cancelled;
    } else {
      _status = TranscriptionStatus.failed;

      if (error is TranscriptionException) {
        _errorMessage = error.message;
        _errorDetails = error.details;
      } else {
        _errorMessage = 'Erreur inattendue.';
        _errorDetails = error.toString();
      }
    }

    _notify();
  }

  void _onDone() {
    _subscription = null;

    // Defensive: the stream closed without a result nor an error.
    if (isRunning) {
      _status = TranscriptionStatus.failed;
      _errorMessage = "La transcription s'est terminée sans résultat.";
      _notify();
    }
  }

  void _clearResult() {
    _stage = null;
    _progress = null;
    _liveSegments.clear();
    _transcript = '';
    _transcriptRevision++;
    _elapsed = null;
    _errorMessage = null;
    _errorDetails = null;
  }

  void _notify() {
    if (!_isDisposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    unawaited(_subscription?.cancel());

    if (isRunning) {
      unawaited(_transcriptionService.cancel());
    }

    super.dispose();
  }
}
