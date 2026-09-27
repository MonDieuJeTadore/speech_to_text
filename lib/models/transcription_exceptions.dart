/// Failure with a user-facing message (French) and optional technical
/// details (engine output, path, ...).
class TranscriptionException implements Exception {
  const TranscriptionException(
    this.message, {
    this.details,
  });

  final String message;
  final String? details;

  @override
  String toString() => details == null ? message : '$message\n$details';
}

/// Raised when the user cancels a running transcription.
class TranscriptionCancelledException implements Exception {
  const TranscriptionCancelledException();

  @override
  String toString() => 'Transcription cancelled';
}
