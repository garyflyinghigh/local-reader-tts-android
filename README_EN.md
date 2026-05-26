# Local Reader

[中文](README.md)

Local Reader is a Flutter-based Android app for reading local TXT and EPUB books, with built-in system text-to-speech playback. It is designed for offline personal reading: import a book from your device, continue from your last position, and switch between reading and listening at any time.

## Features

- Import local `.txt` and `.epub` books.
- Keep a recent bookshelf and reopen the latest books quickly.
- Save chapter, scroll progress, and current TTS sentence automatically.
- Read TXT files with automatic Chinese chapter detection.
- Read EPUB chapters and inline supported EPUB images.
- Browse the chapter list and jump between chapters.
- Adjust reading font size.
- Play, pause, skip to the previous sentence, and skip to the next sentence.
- Highlight the sentence currently being read aloud.
- Configure TTS speech rate, pitch, and voice from available system voices.
- Use Android media notification controls during TTS playback.

## Download

Download the latest APK from the GitHub Releases page:

<https://github.com/garyflyinghigh/local-reader-tts-android/releases>

The release page provides several APK files:

| File | Device | Notes |
| --- | --- | --- |
| `local-reader-0.1.0+1-arm64-v8a.apk` | Most newer Android phones | Recommended first choice, smaller download |
| `local-reader-0.1.0+1-armeabi-v7a.apk` | Older 32-bit ARM Android phones | Try this for older devices |
| `local-reader-0.1.0+1-x86_64.apk` | x86_64 emulators or rare x86_64 devices | Usually not needed for regular phones |
| `local-reader-0.1.0+1-universal.apk` | When you are not sure which architecture you need | Best compatibility, largest file |

If you are not sure which file to download, choose `local-reader-0.1.0+1-universal.apk`. For most mainstream Android phones from recent years, `local-reader-0.1.0+1-arm64-v8a.apk` should work.

## How to Use

1. Install the APK on an Android device.
2. Open the app and tap the import button.
3. Choose a `.txt` or `.epub` file from local storage.
4. Tap a book on the bookshelf to continue reading.
5. In the reader, use the chapter list button to switch chapters.
6. Use the bottom controls to adjust font size and control TTS playback.
7. Open TTS settings to choose speech rate, pitch, or voice.
8. Long press a book, or use its menu, to remove it from the bookshelf. This only removes the bookshelf record and does not delete the original file.

## Notes

- The app reads local files only; it does not include an online book store or downloader.
- TTS quality and voice options depend on the TTS engine installed on the device.
- If a book file is moved or deleted, re-import it from the new location.
- EPUB rendering focuses on readable text and common inline images; complex layouts may not match dedicated EPUB readers exactly.

## Build from Source

Install Flutter, then run:

```bash
flutter pub get
flutter build apk --release
```

The release APK will be generated at:

```text
build/app/outputs/flutter-apk/app-release.apk
```

## Privacy

Book files stay on your device. The app stores only bookshelf metadata and reading progress locally through platform preferences.

## License

Copyright reserved. This project, including its source code, documentation, assets, build configuration, and release packages, is proprietary material. Without written permission from the copyright holder, you may not copy, modify, distribute, sublicense, sell, host, mirror, reverse engineer, or create derivative works from it.

Downloading, viewing, or forking this repository does not grant any license or ownership rights. Third-party dependencies remain subject to their own licenses.

See [LICENSE](LICENSE) for details.
