import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/transcription_event.dart';
import '../models/transcription_exceptions.dart';
import '../models/transcription_settings.dart';
import 'transcription_service.dart';

/// Runs the whisper.cpp command line tool (whisper-cli.exe) as a child
/// process. Everything runs locally: the audio never leaves the machine.
class WhisperCppService implements TranscriptionService {
  static final RegExp _progressRegExp = RegExp(r'progress\s*=\s*(\d+)\s*%');
  static final RegExp _audioReadErrorRegExp = RegExp(
    r'failed to (read|open|decode) (audio|input)',
    caseSensitive: false,
  );
  static final RegExp _errorLineRegExp = RegExp(
    r'error|failed|unable|cannot',
    caseSensitive: false,
  );
  static const Utf8Decoder _decoder = Utf8Decoder(allowMalformed: true);

  Process? _currentProcess;
  bool _cancelRequested = false;

  @override
  Stream<TranscriptionEvent> transcribe({
    required String audioFilePath,
    required TranscriptionSettings settings,
  }) {
    // Events are buffered by the controller until the caller listens.
    final StreamController<TranscriptionEvent> controller =
        StreamController<TranscriptionEvent>();
    unawaited(_run(audioFilePath, settings, controller));
    return controller.stream;
  }

  @override
  Future<void> cancel() async {
    _cancelRequested = true;
    _currentProcess?.kill();
  }

  Future<void> _run(
    String audioFilePath,
    TranscriptionSettings settings,
    StreamController<TranscriptionEvent> controller,
  ) async {
    _cancelRequested = false;
    final Stopwatch stopwatch = Stopwatch()..start();
    Directory? workDir;

    try {
      await _checkInputs(audioFilePath, settings);
      workDir = await Directory.systemTemp.createTemp('mp3_to_text_');

      String whisperInputPath;

      if (settings.usesFfmpeg) {
        controller.add(
          const TranscriptionStageChanged(TranscriptionStage.converting),
        );
        whisperInputPath = await _convertToWav(
          audioFilePath,
          workDir.path,
          settings.ffmpegExecutablePath,
        );
      } else {
        // whisper-cli.exe reads its arguments in the ANSI code page, so
        // accented or special characters in the original path can make the
        // file unreadable. The temp directory copy has a plain ASCII name.
        whisperInputPath = p.join(workDir.path, 'input.mp3');
        await File(audioFilePath).copy(whisperInputPath);
      }

      _throwIfCancelled();
      controller.add(
        const TranscriptionStageChanged(TranscriptionStage.transcribing),
      );

      final String outputBase = p.join(workDir.path, 'transcript');
      final String diagnostics = await _runWhisper(
        whisperInputPath,
        outputBase,
        settings,
        controller,
      );

      final File txtFile = File('$outputBase.txt');

      if (!await txtFile.exists()) {
        // whisper-cli exits with code 0 even when it cannot read the audio
        // file, so the missing output is the only failure signal.
        final bool audioUnreadable =
            _audioReadErrorRegExp.hasMatch(diagnostics);

        throw TranscriptionException(
          audioUnreadable && !settings.usesFfmpeg
              ? "whisper.cpp n'a pas pu décoder ce MP3. Indiquez ffmpeg.exe "
                  'dans les réglages : le fichier sera converti en WAV avant '
                  'la transcription.'
              : "whisper.cpp n'a produit aucun fichier texte.",
          details: _relevantLines(diagnostics),
        );
      }

      final String rawText = utf8.decode(
        await txtFile.readAsBytes(),
        allowMalformed: true,
      );

      controller.add(
        TranscriptionCompleted(
          text: _toProse(rawText),
          elapsed: stopwatch.elapsed,
        ),
      );
    } catch (error, stackTrace) {
      controller.addError(error, stackTrace);
    } finally {
      _currentProcess = null;
      await controller.close();
      await _deleteQuietly(workDir);
    }
  }

  Future<void> _checkInputs(
    String audioFilePath,
    TranscriptionSettings settings,
  ) async {
    final List<(String, String)> requiredFiles = <(String, String)>[
      (audioFilePath, 'Fichier audio introuvable'),
      (settings.whisperExecutablePath, 'Exécutable whisper.cpp introuvable'),
      (settings.modelPath, 'Modèle Whisper introuvable'),
      if (settings.usesFfmpeg)
        (settings.ffmpegExecutablePath, 'Exécutable ffmpeg introuvable'),
    ];

    for (final (String path, String message) in requiredFiles) {
      if (path.isEmpty || !await File(path).exists()) {
        throw TranscriptionException(
          '$message.',
          details: path.isEmpty ? null : path,
        );
      }
    }
  }

  /// Converts the MP3 to 16 kHz mono PCM WAV, the native whisper format.
  Future<String> _convertToWav(
    String mp3Path,
    String workDirPath,
    String ffmpegPath,
  ) async {
    final String wavPath = p.join(workDirPath, 'input.wav');
    final Process process = await _start(
      ffmpegPath,
      <String>[
        '-hide_banner',
        '-loglevel',
        'error',
        '-y',
        '-i',
        mp3Path,
        '-ar',
        '16000',
        '-ac',
        '1',
        '-c:a',
        'pcm_s16le',
        wavPath,
      ],
    );

    final Future<String> errorOutput =
        process.stderr.transform(_decoder).join();
    await process.stdout.drain<void>();
    final int exitCode = await process.exitCode;
    final String errors = await errorOutput;
    _currentProcess = null;
    _throwIfCancelled();

    if (exitCode != 0) {
      throw TranscriptionException(
        'La conversion du MP3 par ffmpeg a échoué.',
        details: errors.trim(),
      );
    }

    return wavPath;
  }

  /// Runs whisper-cli and returns its non-progress stderr output.
  Future<String> _runWhisper(
    String inputPath,
    String outputBase,
    TranscriptionSettings settings,
    StreamController<TranscriptionEvent> controller,
  ) async {
    final Process process = await _start(
      settings.whisperExecutablePath,
      <String>[
        '--model',
        settings.modelPath,
        '--file',
        inputPath,
        '--language',
        settings.language,
        '--threads',
        '${settings.threadCount}',
        '--no-timestamps',
        '--print-progress',
        '--output-txt',
        '--output-file',
        outputBase,
      ],
      // whisper.dll and ggml*.dll live next to whisper-cli.exe.
      workingDirectory: p.dirname(settings.whisperExecutablePath),
    );

    final StringBuffer diagnostics = StringBuffer();

    // stdout: decoded segments, printed as soon as they are available.
    final Future<void> stdoutDone = process.stdout
        .transform(_decoder)
        .transform(const LineSplitter())
        .forEach((String line) {
      final String text = line.trim();

      if (text.isNotEmpty) {
        controller.add(TranscriptionSegment(text));
      }
    });

    // stderr: progress lines plus model / system information.
    final Future<void> stderrDone = process.stderr
        .transform(_decoder)
        .transform(const LineSplitter())
        .forEach((String line) {
      final RegExpMatch? match = _progressRegExp.firstMatch(line);

      if (match != null) {
        controller.add(
          TranscriptionProgress(int.parse(match.group(1)!) / 100),
        );
      } else {
        diagnostics.writeln(line);
      }
    });

    final int exitCode = await process.exitCode;
    await Future.wait(<Future<void>>[stdoutDone, stderrDone]);
    _currentProcess = null;
    _throwIfCancelled();

    if (exitCode != 0) {
      throw TranscriptionException(
        "whisper.cpp s'est arrêté avec le code $exitCode.",
        details: _relevantLines(diagnostics.toString()),
      );
    }

    return diagnostics.toString();
  }

  Future<Process> _start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
  }) async {
    try {
      final Process process = await Process.start(
        executable,
        arguments,
        workingDirectory: workingDirectory,
      );
      _currentProcess = process;

      // Cancel may have been requested while the process was starting.
      if (_cancelRequested) {
        process.kill();
      }

      return process;
    } on ProcessException catch (e) {
      throw TranscriptionException(
        'Impossible de lancer ${p.basename(executable)}.',
        details: e.message,
      );
    }
  }

  void _throwIfCancelled() {
    if (_cancelRequested) {
      throw const TranscriptionCancelledException();
    }
  }

  /// whisper.cpp writes one segment per line; join them into prose.
  static String _toProse(String rawText) {
    return rawText
        .split(RegExp(r'\r?\n'))
        .map((String line) => line.trim())
        .where((String line) => line.isNotEmpty)
        .join(' ')
        .replaceAll(RegExp(r'\s{2,}'), ' ');
  }

  /// Error lines first (they may appear early in a long log), then the
  /// last lines of the output for context.
  static String? _relevantLines(
    String text, {
    int tailCount = 12,
  }) {
    final List<String> lines = text
        .split(RegExp(r'\r?\n'))
        .where((String line) => line.trim().isNotEmpty)
        .toList();

    if (lines.isEmpty) {
      return null;
    }

    final List<String> errorLines =
        lines.where((String line) => _errorLineRegExp.hasMatch(line)).toList();
    final List<String> tail = lines
        .skip(lines.length > tailCount ? lines.length - tailCount : 0)
        .where((String line) => !errorLines.contains(line))
        .toList();

    return <String>[
      ...errorLines,
      if (errorLines.isNotEmpty && tail.isNotEmpty) '…',
      ...tail,
    ].join('\n');
  }

  static Future<void> _deleteQuietly(Directory? directory) async {
    if (directory == null) {
      return;
    }

    try {
      await directory.delete(recursive: true);
    } on FileSystemException {
      // Temporary files are left to the OS if they are still locked.
    }
  }
}
