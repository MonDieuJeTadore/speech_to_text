/// Processing stage reported while a transcription runs.
enum TranscriptionStage {
  converting,
  transcribing,
}

/// Events emitted by a TranscriptionService during one transcription.
sealed class TranscriptionEvent {
  const TranscriptionEvent();
}

final class TranscriptionStageChanged extends TranscriptionEvent {
  const TranscriptionStageChanged(this.stage);

  final TranscriptionStage stage;
}

/// Progress reported by the engine, from 0.0 to 1.0.
final class TranscriptionProgress extends TranscriptionEvent {
  const TranscriptionProgress(this.fraction);

  final double fraction;
}

/// A decoded segment, emitted as soon as the engine prints it.
final class TranscriptionSegment extends TranscriptionEvent {
  const TranscriptionSegment(this.text);

  final String text;
}

/// Final result, emitted once when the transcription succeeds.
final class TranscriptionCompleted extends TranscriptionEvent {
  const TranscriptionCompleted({
    required this.text,
    required this.elapsed,
  });

  final String text;
  final Duration elapsed;
}
