# MP3 vers texte (Flutter / Windows / MVVM)

Application de bureau Windows qui transcrit en texte l'audio parlé en français
d'un fichier MP3. La reconnaissance vocale est faite **localement** par
[whisper.cpp](https://github.com/ggml-org/whisper.cpp) (modèles Whisper
d'OpenAI) : aucun fichier audio n'est envoyé sur Internet, pas de clé d'API.

## Architecture MVVM

```
lib/
├── main.dart                               Injection des dépendances (Provider)
├── models/
│   ├── transcription_settings.dart         Configuration (chemins, langue, threads)
│   ├── transcription_event.dart            Événements scellés émis par le moteur
│   └── transcription_exceptions.dart       Erreurs métier + annulation
├── services/
│   ├── transcription_service.dart          Interface abstraite du moteur
│   ├── whisper_cpp_service.dart            Implémentation via whisper-cli.exe
│   └── settings_service.dart               Persistance (shared_preferences)
├── viewmodels/
│   └── transcription_view_model.dart       État de l'écran (ChangeNotifier)
└── views/
    ├── transcription_view.dart             Écran principal
    └── settings_dialog.dart                Dialogue de réglages
test/
└── transcription_view_model_test.dart      Tests du ViewModel avec un faux service
```

La vue ne connaît que le ViewModel ; le ViewModel ne connaît que l'interface
`TranscriptionService`. On peut donc remplacer whisper.cpp par un autre moteur
(API OpenAI, Vosk, whisper via FFI…) sans toucher à l'interface utilisateur.

## Installation

### 1. Créer le projet Flutter

```powershell
flutter create --platforms=windows mp3_to_text
```

Remplacez ensuite `pubspec.yaml`, `lib/` et `test/` par ceux de cette archive,
puis :

```powershell
cd mp3_to_text
flutter pub get
```

### 2. Installer whisper.cpp

Téléchargez l'archive Windows depuis la page *Releases* du dépôt
`ggml-org/whisper.cpp` :

- `whisper-bin-x64.zip` : version CPU, fonctionne partout ;
- `whisper-cublas-…-bin-x64.zip` : version GPU NVIDIA (CUDA), bien plus rapide.

Décompressez-la, par exemple dans `C:\whisper\`. L'exécutable à indiquer dans
l'application est `whisper-cli.exe` (dossier `Release`). Les DLL qui
l'accompagnent doivent rester dans le même dossier.

### 3. Télécharger un modèle

Les modèles se trouvent sur Hugging Face, dépôt `ggerganov/whisper.cpp`.
Pour le français :

| Modèle                    | Taille  | Qualité en français | Vitesse (CPU) |
|---------------------------|---------|---------------------|---------------|
| `ggml-small.bin`          | 466 Mo  | correcte            | rapide        |
| `ggml-medium.bin`         | 1,5 Go  | très bonne          | moyenne       |
| `ggml-large-v3-turbo.bin` | 1,6 Go  | excellente          | moyenne       |

`ggml-large-v3-turbo.bin` offre le meilleur compromis. Évitez les modèles
`.en` : ils ne comprennent que l'anglais.

### 4. (Facultatif) ffmpeg

whisper.cpp lit directement les MP3. Si un fichier pose problème, indiquez le
chemin de `ffmpeg.exe` dans les réglages : l'application convertira alors
d'abord le MP3 en WAV 16 kHz mono.

### 5. Lancer

```powershell
flutter run -d windows
```

Au premier lancement, cliquez sur **Configurer** et indiquez
`whisper-cli.exe` et le modèle. Les réglages sont mémorisés.

Pour produire l'exécutable :

```powershell
flutter build windows --release
```

## Utilisation

1. **Choisir un fichier MP3**
2. **Transcrire** : la progression s'affiche et les phrases apparaissent au fur
   et à mesure du décodage. **Annuler** arrête le processus immédiatement.
3. Corrigez le texte si besoin, puis **Copier** ou **Enregistrer en .txt**
   (UTF-8).

## Tests

```powershell
flutter test
```
