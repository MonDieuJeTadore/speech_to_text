import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mp3_to_text/models/transcription_event.dart';
import 'package:mp3_to_text/models/transcription_exceptions.dart';
import 'package:mp3_to_text/models/transcription_settings.dart';
import 'package:mp3_to_text/services/settings_service.dart';
import 'package:mp3_to_text/services/transcription_service.dart';
import 'package:mp3_to_text/viewmodels/transcription_view_model.dart';

class FakeTranscriptionService implements TranscriptionService {
  StreamController<TranscriptionEvent>? controller;
  bool cancelCalled = false;

  @override
  Stream<TranscriptionEvent> transcribe({
    required String audioFilePath,
    required TranscriptionSettings settings,
  }) {
    controller = StreamController<TranscriptionEvent>();
    return controller!.stream;
  }

  @override
  Future<void> cancel() async {
    cancelCalled = true;
    controller?.addError(const TranscriptionCancelledException());
    await controller?.close();
  }
}

class FakeSettingsService implements SettingsService {
  TranscriptionSettings stored = TranscriptionSettings.defaults().copyWith(
    whisperExecutablePath: r'C:\whisper\whisper-cli.exe',
    modelPath: r'C:\whisper\ggml-medium.bin',
  );

  @override
  Future<TranscriptionSettings> load() async => stored;

  @override
  Future<void> save(TranscriptionSettings settings) async {
    stored = settings;
  }
}

Future<void> flushEvents() => Future<void>.delayed(Duration.zero);

void main() {
  late FakeTranscriptionService service;
  late TranscriptionViewModel viewModel;

  setUp(() async {
    service = FakeTranscriptionService();
    viewModel = TranscriptionViewModel(
      transcriptionService: service,
      settingsService: FakeSettingsService(),
    );
    await viewModel.loadSettings();
  });

  tearDown(() => viewModel.dispose());

  test('cannot start without an audio file', () {
    expect(viewModel.canStart, isFalse);
  });

  test('successful transcription exposes the final text', () async {
    viewModel.selectAudioFile(r'C:\audio\cours.mp3');
    viewModel.startTranscription();
    expect(viewModel.status, TranscriptionStatus.running);

    service.controller!
      ..add(const TranscriptionProgress(0.5))
      ..add(const TranscriptionSegment('Bonjour à tous.'));
    await flushEvents();

    expect(viewModel.progress, 0.5);
    expect(viewModel.liveText, 'Bonjour à tous.');

    service.controller!.add(
      const TranscriptionCompleted(
        text: 'Bonjour à tous. Voici le cours.',
        elapsed: Duration(seconds: 42),
      ),
    );
    await service.controller!.close();
    await flushEvents();

    expect(viewModel.status, TranscriptionStatus.completed);
    expect(viewModel.transcript, 'Bonjour à tous. Voici le cours.');
    expect(viewModel.wordCount, 6);
    expect(viewModel.suggestedOutputFileName, 'cours.txt');
  });

  test('cancellation sets the cancelled status', () async {
    viewModel.selectAudioFile(r'C:\audio\cours.mp3');
    viewModel.startTranscription();

    await viewModel.cancelTranscription();
    await flushEvents();

    expect(service.cancelCalled, isTrue);
    expect(viewModel.status, TranscriptionStatus.cancelled);
  });

  test('engine failure exposes a user-facing message', () async {
    viewModel.selectAudioFile(r'C:\audio\cours.mp3');
    viewModel.startTranscription();

    service.controller!.addError(
      const TranscriptionException(
        'Modèle Whisper introuvable.',
        details: r'C:\whisper\ggml-medium.bin',
      ),
    );
    await service.controller!.close();
    await flushEvents();

    expect(viewModel.status, TranscriptionStatus.failed);
    expect(viewModel.errorMessage, 'Modèle Whisper introuvable.');
  });
}
