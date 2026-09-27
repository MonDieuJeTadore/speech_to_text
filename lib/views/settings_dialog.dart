import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models/transcription_settings.dart';

/// Edits the whisper.cpp configuration. Pops the updated settings on
/// save, or null on cancel.
class SettingsDialog extends StatefulWidget {
  const SettingsDialog({
    super.key,
    required this.initialSettings,
  });

  final TranscriptionSettings initialSettings;

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  static const Map<String, String> _languages = <String, String>{
    'fr': 'Français',
    'auto': 'Détection automatique',
  };

  late final TextEditingController _whisperController;
  late final TextEditingController _modelController;
  late final TextEditingController _ffmpegController;
  late String _language;
  late int _threadCount;
  final int _maxThreads = Platform.numberOfProcessors;

  @override
  void initState() {
    super.initState();
    final TranscriptionSettings settings = widget.initialSettings;

    _whisperController = TextEditingController(
      text: settings.whisperExecutablePath,
    );
    _modelController = TextEditingController(text: settings.modelPath);
    _ffmpegController = TextEditingController(
      text: settings.ffmpegExecutablePath,
    );
    _language =
        _languages.containsKey(settings.language) ? settings.language : 'fr';
    _threadCount = settings.threadCount.clamp(1, _maxThreads);
  }

  @override
  void dispose() {
    _whisperController.dispose();
    _modelController.dispose();
    _ffmpegController.dispose();
    super.dispose();
  }

  Future<void> _browse(
    TextEditingController controller,
    List<String> extensions,
    String dialogTitle,
  ) async {
    final FilePickerResult? result = await FilePicker.platform.pickFiles(
      dialogTitle: dialogTitle,
      type: FileType.custom,
      allowedExtensions: extensions,
    );
    final String? path = result?.files.single.path;

    if (path != null) {
      setState(() => controller.text = path);
    }
  }

  void _save() {
    Navigator.of(context).pop(
      widget.initialSettings.copyWith(
        whisperExecutablePath: _whisperController.text.trim(),
        modelPath: _modelController.text.trim(),
        ffmpegExecutablePath: _ffmpegController.text.trim(),
        language: _language,
        threadCount: _threadCount,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Réglages de la transcription'),
      content: SizedBox(
        width: 580,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _PathField(
                controller: _whisperController,
                label: 'Exécutable whisper.cpp',
                helper: 'whisper-cli.exe, dans le dossier Release de '
                    "l'archive whisper.cpp pour Windows.",
                onBrowse: () => _browse(
                  _whisperController,
                  <String>['exe'],
                  'Choisir whisper-cli.exe',
                ),
              ),
              const SizedBox(height: 20),
              _PathField(
                controller: _modelController,
                label: 'Modèle Whisper',
                helper: 'Fichier ggml-*.bin. Pour le français : '
                    'ggml-large-v3-turbo.bin ou ggml-medium.bin.',
                onBrowse: () => _browse(
                  _modelController,
                  <String>['bin'],
                  'Choisir le modèle Whisper',
                ),
              ),
              const SizedBox(height: 20),
              _PathField(
                controller: _ffmpegController,
                label: 'ffmpeg.exe (facultatif)',
                helper: 'À renseigner seulement si certains MP3 ne sont '
                    'pas lus directement par whisper.cpp.',
                onBrowse: () => _browse(
                  _ffmpegController,
                  <String>['exe'],
                  'Choisir ffmpeg.exe',
                ),
              ),
              const SizedBox(height: 20),
              DropdownButtonFormField<String>(
                value: _language,
                decoration: const InputDecoration(
                  labelText: 'Langue parlée',
                  border: OutlineInputBorder(),
                ),
                items: _languages.entries
                    .map(
                      (MapEntry<String, String> entry) =>
                          DropdownMenuItem<String>(
                        value: entry.key,
                        child: Text(entry.value),
                      ),
                    )
                    .toList(),
                onChanged: (String? value) {
                  if (value != null) {
                    setState(() => _language = value);
                  }
                },
              ),
              const SizedBox(height: 20),
              Text(
                'Threads processeur : $_threadCount',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              Slider(
                value: _threadCount.toDouble(),
                min: 1,
                max: _maxThreads.toDouble(),
                divisions: _maxThreads > 1 ? _maxThreads - 1 : null,
                label: '$_threadCount',
                onChanged: _maxThreads > 1
                    ? (double value) =>
                        setState(() => _threadCount = value.round())
                    : null,
              ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: _save,
          child: const Text('Enregistrer'),
        ),
      ],
    );
  }
}

class _PathField extends StatelessWidget {
  const _PathField({
    required this.controller,
    required this.label,
    required this.helper,
    required this.onBrowse,
  });

  final TextEditingController controller;
  final String label;
  final String helper;
  final VoidCallback onBrowse;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        helperText: helper,
        helperMaxLines: 2,
        border: const OutlineInputBorder(),
        suffixIcon: IconButton(
          tooltip: 'Parcourir',
          icon: const Icon(Icons.folder_open_outlined),
          onPressed: onBrowse,
        ),
      ),
    );
  }
}
