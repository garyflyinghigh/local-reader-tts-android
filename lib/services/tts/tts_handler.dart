import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'text_splitter.dart';

final ttsAudioHandlerProvider = Provider<MyTtsAudioHandler>((ref) {
  throw UnimplementedError(
      'ttsAudioHandlerProvider must be overridden in main.');
});

class TtsVoiceOption {
  const TtsVoiceOption({
    required this.name,
    required this.locale,
  });

  final String name;
  final String locale;

  String get label {
    if (locale.isEmpty) {
      return name;
    }
    return '$name ($locale)';
  }

  Map<String, String> toFlutterTtsVoice() {
    return {
      'name': name,
      if (locale.isNotEmpty) 'locale': locale,
    };
  }
}

class MyTtsAudioHandler extends BaseAudioHandler with QueueHandler {
  MyTtsAudioHandler() {
    _init();
  }

  final FlutterTts _tts = FlutterTts();
  final StreamController<int?> _currentIndexController =
      StreamController<int?>.broadcast();

  List<String> _sentences = const [];
  String _bookTitle = '';
  String _chapterTitle = '';
  int _sentenceIndex = 0;
  bool _manualStop = false;
  double _speechRate = 1;
  double _pitch = 1;
  TtsVoiceOption? _voice;

  int get sentenceIndex => _sentenceIndex;
  Stream<int?> get currentIndexStream => _currentIndexController.stream;
  double get speechRate => _speechRate;
  double get pitch => _pitch;
  TtsVoiceOption? get voice => _voice;

  bool isLoadedFor({
    required String bookTitle,
    required String chapterTitle,
  }) {
    return _bookTitle == bookTitle &&
        _chapterTitle == chapterTitle &&
        _sentences.isNotEmpty;
  }

  Future<void> _init() async {
    await _tts.setVolume(1);
    await _tts.setPitch(_pitch);
    await _tts.setSpeechRate(_mapSpeechRate(_speechRate));

    _tts.setCompletionHandler(() {
      if (!_manualStop && playbackState.value.playing) {
        skipToNext();
      }
    });

    _tts.setCancelHandler(() {});
    _tts.setErrorHandler((message) {
      playbackState.add(
        playbackState.value.copyWith(
          processingState: AudioProcessingState.error,
          playing: false,
          errorMessage: message,
        ),
      );
    });

    _broadcastState(
      playing: false,
      processingState: AudioProcessingState.idle,
    );
  }

  Future<void> loadChapter({
    required String bookTitle,
    required String chapterTitle,
    required List<String> sentences,
    int initialSentenceIndex = 0,
  }) async {
    final cleanedSentences =
        sentences.where((sentence) => sentence.trim().isNotEmpty).toList();

    _manualStop = true;
    await _tts.stop();
    _manualStop = false;

    _bookTitle = bookTitle;
    _chapterTitle = chapterTitle;
    _sentences = cleanedSentences;
    _sentenceIndex = cleanedSentences.isEmpty
        ? 0
        : initialSentenceIndex.clamp(0, cleanedSentences.length - 1);

    final items = List<MediaItem>.generate(
      _sentences.length,
      (index) => _mediaItemFor(index),
      growable: false,
    );
    queue.add(items);
    mediaItem.add(items.isEmpty ? null : items[_sentenceIndex]);

    _broadcastState(
      playing: false,
      processingState: items.isEmpty
          ? AudioProcessingState.idle
          : AudioProcessingState.ready,
    );
  }

  Future<void> loadText({
    required String bookTitle,
    required String chapterTitle,
    required String text,
    int initialSentenceIndex = 0,
  }) {
    return loadChapter(
      bookTitle: bookTitle,
      chapterTitle: chapterTitle,
      sentences: TtsTextSplitter.split(text),
      initialSentenceIndex: initialSentenceIndex,
    );
  }

  Future<List<TtsVoiceOption>> getVoiceOptions() async {
    final dynamic voices = await _tts.getVoices;
    if (voices is! List) {
      return const [];
    }

    final result = <TtsVoiceOption>[];
    for (final voice in voices) {
      if (voice is! Map) {
        continue;
      }
      final name = voice['name']?.toString();
      final locale = voice['locale']?.toString() ?? '';
      if (name == null || name.trim().isEmpty) {
        continue;
      }
      result.add(TtsVoiceOption(name: name, locale: locale));
    }

    result.sort((a, b) => a.label.compareTo(b.label));
    return result;
  }

  Future<void> setSpeechRate(double value) async {
    _speechRate = value.clamp(0.75, 2.5);
    await _tts.setSpeechRate(_mapSpeechRate(_speechRate));
    await _restartIfPlaying();
  }

  Future<void> setPitch(double value) async {
    _pitch = value.clamp(0.6, 1.6);
    await _tts.setPitch(_pitch);
    await _restartIfPlaying();
  }

  Future<void> setVoice(TtsVoiceOption voice) async {
    _voice = voice;
    await _tts.setVoice(voice.toFlutterTtsVoice());
    await _restartIfPlaying();
  }

  @override
  Future<void> play() async {
    if (_sentences.isEmpty) {
      return;
    }

    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.speech());
    final activated = await session.setActive(true);
    if (!activated) {
      return;
    }

    _broadcastState(
      playing: true,
      processingState: AudioProcessingState.ready,
    );
    await _speakCurrentSentence();
  }

  @override
  Future<void> pause() async {
    _manualStop = true;
    await _tts.stop();
    _manualStop = false;

    _broadcastState(
      playing: false,
      processingState: _sentences.isEmpty
          ? AudioProcessingState.idle
          : AudioProcessingState.ready,
    );
  }

  @override
  Future<void> stop() async {
    _manualStop = true;
    await _tts.stop();
    _manualStop = false;

    _sentenceIndex = 0;
    if (queue.value.isNotEmpty) {
      mediaItem.add(queue.value.first);
    }

    _broadcastState(
      playing: false,
      processingState: AudioProcessingState.idle,
    );
    await super.stop();
  }

  @override
  Future<void> skipToNext() async {
    if (_sentences.isEmpty) {
      return;
    }

    if (_sentenceIndex >= _sentences.length - 1) {
      _broadcastState(
        playing: false,
        processingState: AudioProcessingState.completed,
      );
      _manualStop = true;
      await _tts.stop();
      _manualStop = false;
      return;
    }

    _sentenceIndex++;
    await _restartIfPlaying();
  }

  @override
  Future<void> skipToPrevious() async {
    if (_sentences.isEmpty) {
      return;
    }

    _sentenceIndex = (_sentenceIndex - 1).clamp(0, _sentences.length - 1);
    await _restartIfPlaying();
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    if (_sentences.isEmpty) {
      return;
    }

    _sentenceIndex = index.clamp(0, _sentences.length - 1);
    await _restartIfPlaying();
  }

  Future<void> _restartIfPlaying() async {
    final wasPlaying = playbackState.value.playing;
    _manualStop = true;
    await _tts.stop();
    _manualStop = false;

    _broadcastState(
      playing: wasPlaying,
      processingState: AudioProcessingState.ready,
    );

    if (wasPlaying) {
      await _speakCurrentSentence();
    }
  }

  Future<void> _speakCurrentSentence() async {
    if (_sentences.isEmpty || !playbackState.value.playing) {
      return;
    }

    mediaItem.add(_mediaItemFor(_sentenceIndex));
    _broadcastState(
      playing: true,
      processingState: AudioProcessingState.ready,
    );

    await _tts.speak(_sentences[_sentenceIndex]);
  }

  MediaItem _mediaItemFor(int index) {
    return MediaItem(
      id: '$_bookTitle/$_chapterTitle/$index',
      album: _chapterTitle,
      title: '正在播放：$_bookTitle',
      artist: '第 ${index + 1}/${_sentences.length} 句',
      extras: <String, dynamic>{
        'sentenceIndex': index,
        'sentence': _sentences[index],
      },
    );
  }

  void _broadcastState({
    required bool playing,
    required AudioProcessingState processingState,
  }) {
    playbackState.add(
      playbackState.value.copyWith(
        controls: [
          MediaControl.skipToPrevious,
          if (playing) MediaControl.pause else MediaControl.play,
          MediaControl.stop,
          MediaControl.skipToNext,
        ],
        systemActions: const {
          MediaAction.skipToPrevious,
          MediaAction.skipToNext,
        },
        androidCompactActionIndices: const [0, 1, 3],
        processingState: processingState,
        playing: playing,
        queueIndex: _sentences.isEmpty ? null : _sentenceIndex,
        updatePosition: Duration.zero,
      ),
    );
    _currentIndexController.add(_sentences.isEmpty ? null : _sentenceIndex);
  }

  double _mapSpeechRate(double multiplier) {
    const minMultiplier = 0.75;
    const maxMultiplier = 2.5;
    const minFlutterRate = 0.35;
    const maxFlutterRate = 1.0;

    final normalized =
        ((multiplier - minMultiplier) / (maxMultiplier - minMultiplier))
            .clamp(0.0, 1.0);
    return minFlutterRate + normalized * (maxFlutterRate - minFlutterRate);
  }
}
