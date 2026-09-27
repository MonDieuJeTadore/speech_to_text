import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/transcription_event.dart';
import '../models/transcription_settings.dart';
import '../viewmodels/transcription_view_model.dart';
import 'settings_dialog.dart';

/// Main screen: pick an MP3, run the transcription, edit and export text.
class TranscriptionView extends StatefulWidget {
  const TranscriptionView({super.key});

  @override
  State<TranscriptionView> createState() => _TranscriptionViewState();
}

class _TranscriptionViewState extends State<TranscriptionView> {
  final TextEditingController _transcriptController = TextEditingController();
  final ScrollController _liveScrollController = ScrollController();
  late final TranscriptionViewModel _viewModel;
  int _shownRevision = -1;

  @override
  void initState() {
    super.initState();
    _viewModel = context.read<TranscriptionViewModel>();
    _viewModel.addListener(_syncTranscriptEditor);
    _syncTranscriptEditor();
  }

  @override
  void dispose() {
    _viewModel.removeListener(_syncTranscriptEditor);
    _transcriptController.dispose();
    _liveScrollController.dispose();
    super.dispose();
  }

  /// Refreshes the editor only when the engine replaced the transcript,
  /// so user edits are never overwritten while typing.
  void _syncTranscriptEditor() {
    if (_viewModel.transcriptRevision == _shownRevision) {
      return;
    }

    _shownRevision = _viewModel.transcriptRevision;
    _transcriptController.text = _viewModel.transcript;
  }

  Future<void> _pickAudioFile() async {
    final FilePickerResult? result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Choisir un fichier MP3',
      type: FileType.custom,
      allowedExtensions: <String>['mp3'],
    );
    final String? path = result?.files.single.path;

    if (path != null) {
      _viewModel.selectAudioFile(path);
    }
  }

  Future<void> _openSettings() async {
    final TranscriptionSettings? updated =
        await showDialog<TranscriptionSettings>(
      context: context,
      builder: (_) => SettingsDialog(
        initialSettings: _viewModel.settings,
      ),
    );

    if (updated != null) {
      await _viewModel.updateSettings(updated);
    }
  }

  Future<void> _copyTranscript() async {
    await Clipboard.setData(
      ClipboardData(text: _viewModel.transcript),
    );

    if (!mounted) {
      return;
    }

    _showMessage('Texte copié dans le presse-papiers.');
  }

  Future<void> _saveTranscript() async {
    final String? path = await FilePicker.platform.saveFile(
      dialogTitle: 'Enregistrer la transcription',
      fileName: _viewModel.suggestedOutputFileName,
      type: FileType.custom,
      allowedExtensions: <String>['txt'],
    );

    if (path == null) {
      return;
    }

    try {
      final String savedPath = await _viewModel.saveTranscript(path);

      if (!mounted) {
        return;
      }

      _showMessage('Transcription enregistrée : $savedPath');
    } on FileSystemException catch (e) {
      if (!mounted) {
        return;
      }

      _showMessage("Échec de l'enregistrement : ${e.message}");
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final TranscriptionViewModel vm = context.watch<TranscriptionViewModel>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Transcription MP3 en texte'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Réglages de whisper.cpp',
            icon: const Icon(Icons.tune),
            onPressed: vm.isRunning ? null : _openSettings,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                if (vm.settingsLoaded && !vm.settings.isComplete)
                  _SetupBanner(onConfigure: _openSettings),
                _AudioFileRow(
                  fileName: vm.audioFileName,
                  enabled: !vm.isRunning,
                  onPick: _pickAudioFile,
                ),
                const SizedBox(height: 16),
                _ControlRow(
                  viewModel: vm,
                  onStart: vm.startTranscription,
                  onCancel: vm.cancelTranscription,
                ),
                const SizedBox(height: 12),
                if (vm.status == TranscriptionStatus.failed)
                  _ErrorPanel(
                    message: vm.errorMessage ?? '',
                    details: vm.errorDetails,
                  ),
                Expanded(
                  child: vm.isRunning
                      ? _buildLiveTranscript(vm)
                      : _buildTranscriptEditor(vm),
                ),
                const SizedBox(height: 12),
                Row(
                  children: <Widget>[
                    Text(
                      vm.hasTranscript ? '${vm.wordCount} mots' : '',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const Spacer(),
                    OutlinedButton.icon(
                      onPressed: vm.hasTranscript && !vm.isRunning
                          ? _copyTranscript
                          : null,
                      icon: const Icon(Icons.copy_outlined),
                      label: const Text('Copier'),
                    ),
                    const SizedBox(width: 12),
                    FilledButton.icon(
                      onPressed: vm.hasTranscript && !vm.isRunning
                          ? _saveTranscript
                          : null,
                      icon: const Icon(Icons.save_alt),
                      label: const Text('Enregistrer en .txt'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLiveTranscript(TranscriptionViewModel vm) {
    final ThemeData theme = Theme.of(context);

    // Keep the latest segment visible while whisper.cpp prints text.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_liveScrollController.hasClients) {
        _liveScrollController.jumpTo(
          _liveScrollController.position.maxScrollExtent,
        );
      }
    });

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(6),
      ),
      child: SingleChildScrollView(
        controller: _liveScrollController,
        padding: const EdgeInsets.all(16),
        child: SelectableText(
          vm.liveText.isEmpty
              ? 'Les premières phrases apparaîtront ici dès que le modèle '
                  'aura commencé à décoder.'
              : vm.liveText,
          style: theme.textTheme.bodyLarge?.copyWith(
            height: 1.6,
            color: vm.liveText.isEmpty
                ? theme.colorScheme.onSurfaceVariant
                : theme.colorScheme.onSurface,
          ),
        ),
      ),
    );
  }

  Widget _buildTranscriptEditor(TranscriptionViewModel vm) {
    return TextField(
      controller: _transcriptController,
      onChanged: vm.editTranscript,
      expands: true,
      maxLines: null,
      minLines: null,
      textAlignVertical: TextAlignVertical.top,
      style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.6),
      decoration: InputDecoration(
        hintText: 'Choisissez un fichier MP3, puis lancez la transcription. '
            'Le texte obtenu pourra être corrigé ici avant enregistrement.',
        hintMaxLines: 3,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
        ),
        contentPadding: const EdgeInsets.all(16),
      ),
    );
  }
}

class _SetupBanner extends StatelessWidget {
  const _SetupBanner({required this.onConfigure});

  final VoidCallback onConfigure;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Material(
        color: colors.secondaryContainer,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: <Widget>[
              Icon(Icons.info_outline, color: colors.onSecondaryContainer),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  "Indiquez l'emplacement de whisper-cli.exe et du modèle "
                  'Whisper pour pouvoir transcrire.',
                  style: TextStyle(color: colors.onSecondaryContainer),
                ),
              ),
              TextButton(
                onPressed: onConfigure,
                child: const Text('Configurer'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AudioFileRow extends StatelessWidget {
  const _AudioFileRow({
    required this.fileName,
    required this.enabled,
    required this.onPick,
  });

  final String? fileName;
  final bool enabled;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Row(
      children: <Widget>[
        OutlinedButton.icon(
          onPressed: enabled ? onPick : null,
          icon: const Icon(Icons.audio_file_outlined),
          label: const Text('Choisir un fichier MP3'),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            fileName ?? 'Aucun fichier sélectionné',
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleMedium?.copyWith(
              color: fileName == null
                  ? theme.colorScheme.onSurfaceVariant
                  : theme.colorScheme.onSurface,
            ),
          ),
        ),
      ],
    );
  }
}

class _ControlRow extends StatelessWidget {
  const _ControlRow({
    required this.viewModel,
    required this.onStart,
    required this.onCancel,
  });

  final TranscriptionViewModel viewModel;
  final VoidCallback onStart;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final TranscriptionViewModel vm = viewModel;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            if (vm.isRunning)
              OutlinedButton.icon(
                onPressed: onCancel,
                icon: const Icon(Icons.stop_circle_outlined),
                label: const Text('Annuler'),
              )
            else
              FilledButton.icon(
                onPressed: vm.canStart ? onStart : null,
                icon: const Icon(Icons.record_voice_over_outlined),
                label: const Text('Transcrire'),
              ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                _statusText(vm),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ],
        ),
        if (vm.isRunning) ...<Widget>[
          const SizedBox(height: 12),
          LinearProgressIndicator(value: vm.progress),
        ],
      ],
    );
  }

  static String _statusText(TranscriptionViewModel vm) {
    switch (vm.status) {
      case TranscriptionStatus.idle:
        return vm.audioFileName == null ? '' : 'Prêt à transcrire.';
      case TranscriptionStatus.running:
        if (vm.stage == TranscriptionStage.converting) {
          return 'Conversion du MP3 en WAV…';
        }

        final double? progress = vm.progress;
        return progress == null
            ? 'Chargement du modèle…'
            : 'Transcription en cours : ${(progress * 100).round()} %';
      case TranscriptionStatus.completed:
        final Duration? elapsed = vm.elapsed;
        return elapsed == null
            ? 'Transcription terminée.'
            : 'Transcription terminée en ${_formatDuration(elapsed)}.';
      case TranscriptionStatus.failed:
        return 'La transcription a échoué.';
      case TranscriptionStatus.cancelled:
        return 'Transcription annulée.';
    }
  }

  static String _formatDuration(Duration duration) {
    final int minutes = duration.inMinutes;
    final int seconds = duration.inSeconds.remainder(60);
    return minutes == 0 ? '$seconds s' : '$minutes min $seconds s';
  }
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({
    required this.message,
    required this.details,
  });

  final String message;
  final String? details;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final String? detailText = details;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: colors.errorContainer,
        borderRadius: BorderRadius.circular(6),
        child: Theme(
          data: theme.copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            leading: Icon(Icons.error_outline, color: colors.onErrorContainer),
            title: Text(
              message,
              style: TextStyle(color: colors.onErrorContainer),
            ),
            subtitle: detailText == null
                ? null
                : Text(
                    'Afficher les détails techniques',
                    style: TextStyle(color: colors.onErrorContainer),
                  ),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: <Widget>[
              if (detailText != null)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 160),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      detailText,
                      style: const TextStyle(
                        fontFamily: 'Consolas',
                        fontSize: 12,
                      ).copyWith(color: colors.onErrorContainer),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
