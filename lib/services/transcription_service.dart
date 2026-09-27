import '../models/transcription_event.dart';
import '../models/transcription_settings.dart';

/// Speech-to-text engine abstraction, so the view model does not depend
/// on whisper.cpp and can be tested with a fake implementation.
abstract class TranscriptionService {
  /// Starts a transcription. The stream emits TranscriptionEvents and ends
  /// with a TranscriptionCompleted on success, or with an error
  /// (TranscriptionException / TranscriptionCancelledException).
  Stream<TranscriptionEvent> transcribe({
    required String audioFilePath,
    required TranscriptionSettings settings,
  });

  /// Stops the running transcription, if any.
  Future<void> cancel();
}
