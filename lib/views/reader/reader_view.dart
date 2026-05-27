import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/book.dart';
import '../../models/chapter.dart';
import '../../services/database/book_storage_provider.dart';
import '../../services/tts/tts_handler.dart';

class ReaderView extends ConsumerStatefulWidget {
  const ReaderView({
    super.key,
    required this.book,
    required this.chapters,
    required this.initialChapterIndex,
    this.initialScrollProgress = 0,
    this.initialTtsSentenceIndex = 0,
  });

  final Book book;
  final List<Chapter> chapters;
  final int initialChapterIndex;
  final double initialScrollProgress;
  final int initialTtsSentenceIndex;

  @override
  ConsumerState<ReaderView> createState() => _ReaderViewState();
}

class _ReaderViewState extends ConsumerState<ReaderView> {
  final ScrollController _scrollController = ScrollController();
  late int _chapterIndex;
  bool _chromeVisible = true;
  double _fontSize = 19;
  double _speechRate = 1;
  double _pitch = 1;
  TtsVoiceOption? _voice;
  double _scrollFraction = 0;
  int? _highlightedSentenceIndex;
  StreamSubscription<int?>? _ttsIndexSubscription;
  final Map<int, GlobalKey> _paragraphKeys = {};
  Timer? _saveTimer;
  Timer? _chromeTimer;
  int _ttsSentenceIndex = 0;
  bool _restoredInitialScroll = false;
  bool _restoringInitialScroll = false;

  Chapter get _chapter => widget.chapters[_chapterIndex];

  double get _progress {
    if (widget.chapters.isEmpty) {
      return 0;
    }
    return (_chapterIndex + _scrollFraction) / widget.chapters.length;
  }

  @override
  void initState() {
    super.initState();
    _chapterIndex =
        widget.initialChapterIndex.clamp(0, widget.chapters.length - 1);
    _scrollFraction = widget.initialScrollProgress.clamp(0.0, 1.0);
    _ttsSentenceIndex = widget.initialTtsSentenceIndex;
    _fontSize = widget.book.fontSize;
    _speechRate = widget.book.speechRate;
    _pitch = widget.book.pitch;
    final voiceName = widget.book.ttsVoiceName;
    if (voiceName != null) {
      _voice = TtsVoiceOption(
        name: voiceName,
        locale: widget.book.ttsVoiceLocale ?? '',
      );
    }
    _scrollController.addListener(_updateScrollProgress);
    _ttsIndexSubscription =
        ref.read(ttsAudioHandlerProvider).currentIndexStream.listen(
              _handleTtsIndexChanged,
            );
    unawaited(_applySavedReadingPreferences());
    _scheduleChromeAutoHide();
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _chromeTimer?.cancel();
    unawaited(_saveReadingState(touchLastOpened: true));
    _ttsIndexSubscription?.cancel();
    _scrollController.removeListener(_updateScrollProgress);
    _scrollController.dispose();
    unawaited(_stopTtsIfCurrentChapter());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final background = Theme.of(context).colorScheme.surface;
    final ttsHandler = ref.watch(ttsAudioHandlerProvider);

    return Scaffold(
      backgroundColor: background,
      body: SafeArea(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _showChromeTemporarily,
          child: Stack(
            children: [
              Positioned.fill(
                child: ListView(
                  controller: _scrollController,
                  padding: EdgeInsets.fromLTRB(
                    22,
                    _chromeVisible ? 84 : 24,
                    22,
                    _chromeVisible ? 164 : 28,
                  ),
                  children: [
                    _ChapterNavButton(
                      label: '上一章',
                      enabled: _chapterIndex > 0,
                      onPressed: () => _switchChapter(_chapterIndex - 1),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      _chapter.title,
                      style:
                          Theme.of(context).textTheme.headlineSmall?.copyWith(
                                height: 1.25,
                                fontWeight: FontWeight.w600,
                              ),
                    ),
                    const SizedBox(height: 22),
                    _SentenceContent(
                      chapter: _chapter,
                      fontSize: _fontSize,
                      highlightedSentenceIndex: _highlightedSentenceIndex,
                      paragraphKeyBuilder: _keyForParagraph,
                    ),
                    const SizedBox(height: 28),
                    _ChapterNavButton(
                      label: '下一章',
                      enabled: _chapterIndex < widget.chapters.length - 1,
                      onPressed: () => _switchChapter(_chapterIndex + 1),
                    ),
                  ],
                ),
              ),
              AnimatedPositioned(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                left: 0,
                right: 0,
                top: _chromeVisible ? 0 : -72,
                child: _TopBar(
                  title: widget.book.title,
                  chapterTitle: _chapter.title,
                  onBack: () => Navigator.of(context).pop(),
                  onShowChapters: _showChapterList,
                ),
              ),
              AnimatedPositioned(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                left: 0,
                right: 0,
                bottom: _chromeVisible ? 0 : -160,
                child: _BottomBar(
                  progress: _progress,
                  fontSize: _fontSize,
                  playbackStateStream: ttsHandler.playbackState,
                  onFontSizeChanged: (value) {
                    setState(() {
                      _fontSize = value;
                    });
                    _scheduleSave();
                    _scheduleChromeAutoHide();
                  },
                  onPlayPause: _toggleTts,
                  onPreviousSentence: _previousSentence,
                  onNextSentence: _nextSentence,
                  onTtsSettings: _showTtsSettings,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _restoreInitialScrollOnce();
  }

  Future<void> _switchChapter(int nextIndex) async {
    if (nextIndex < 0 ||
        nextIndex >= widget.chapters.length ||
        nextIndex == _chapterIndex) {
      return;
    }

    final ttsHandler = ref.read(ttsAudioHandlerProvider);
    final shouldContinueTts = ttsHandler.playbackState.value.playing &&
        ttsHandler.isLoadedFor(
          bookTitle: widget.book.title,
          chapterTitle: _chapter.title,
        );

    setState(() {
      _chapterIndex = nextIndex;
      _scrollFraction = 0;
      _ttsSentenceIndex = 0;
      _highlightedSentenceIndex = null;
      _paragraphKeys.clear();
    });
    _scheduleSave();

    if (shouldContinueTts) {
      await _loadCurrentChapterForTts();
      await ttsHandler.play();
    }

    await Future<void>.delayed(Duration.zero);
    if (!_scrollController.hasClients) {
      return;
    }
    await _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  void _updateScrollProgress() {
    if (!_scrollController.hasClients || _restoringInitialScroll) {
      return;
    }

    final position = _scrollController.position;
    final maxExtent = position.maxScrollExtent;
    final nextFraction =
        maxExtent <= 0 ? 1.0 : (position.pixels / maxExtent).clamp(0.0, 1.0);

    if ((nextFraction - _scrollFraction).abs() < 0.002) {
      return;
    }

    setState(() {
      _scrollFraction = nextFraction;
    });
    _scheduleSave();
  }

  Future<void> _toggleTts() async {
    final ttsHandler = ref.read(ttsAudioHandlerProvider);
    if (ttsHandler.playbackState.value.playing) {
      await ttsHandler.pause();
      return;
    }

    if (!ttsHandler.isLoadedFor(
      bookTitle: widget.book.title,
      chapterTitle: _chapter.title,
    )) {
      await _loadCurrentChapterForTts();
    }
    await ttsHandler.play();
  }

  Future<void> _previousSentence() async {
    final ttsHandler = ref.read(ttsAudioHandlerProvider);
    if (!ttsHandler.isLoadedFor(
      bookTitle: widget.book.title,
      chapterTitle: _chapter.title,
    )) {
      await _loadCurrentChapterForTts();
    }
    await ttsHandler.skipToPrevious();
  }

  Future<void> _nextSentence() async {
    final ttsHandler = ref.read(ttsAudioHandlerProvider);
    if (!ttsHandler.isLoadedFor(
      bookTitle: widget.book.title,
      chapterTitle: _chapter.title,
    )) {
      await _loadCurrentChapterForTts();
    }
    await ttsHandler.skipToNext();
  }

  Future<void> _loadCurrentChapterForTts() {
    return ref.read(ttsAudioHandlerProvider).loadChapter(
          bookTitle: widget.book.title,
          chapterTitle: _chapter.title,
          sentences: _chapter.sentences,
          initialSentenceIndex: _ttsSentenceIndex,
        );
  }

  Future<void> _applySavedReadingPreferences() async {
    final ttsHandler = ref.read(ttsAudioHandlerProvider);
    await ttsHandler.setSpeechRate(_speechRate);
    await ttsHandler.setPitch(_pitch);
    final voice = _voice;
    if (voice != null) {
      await ttsHandler.setVoice(voice);
    }
  }

  Future<void> _stopTtsIfCurrentChapter() async {
    final ttsHandler = ref.read(ttsAudioHandlerProvider);
    if (ttsHandler.isLoadedFor(
      bookTitle: widget.book.title,
      chapterTitle: _chapter.title,
    )) {
      await ttsHandler.stop();
    }
  }

  GlobalKey _keyForParagraph(int index) {
    return _paragraphKeys.putIfAbsent(index, GlobalKey.new);
  }

  void _handleTtsIndexChanged(int? index) {
    final ttsHandler = ref.read(ttsAudioHandlerProvider);
    if (!ttsHandler.isLoadedFor(
      bookTitle: widget.book.title,
      chapterTitle: _chapter.title,
    )) {
      if (_highlightedSentenceIndex != null && mounted) {
        setState(() {
          _highlightedSentenceIndex = null;
        });
      }
      return;
    }

    if (!mounted || _highlightedSentenceIndex == index) {
      return;
    }

    setState(() {
      _highlightedSentenceIndex = index;
      _ttsSentenceIndex = index ?? 0;
    });
    _scheduleSave();

    if (index != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _scrollToSentence(index);
        }
      });
    }
  }

  void _restoreInitialScrollOnce() {
    if (_restoredInitialScroll || widget.initialScrollProgress <= 0) {
      return;
    }
    _restoredInitialScroll = true;
    _restoringInitialScroll = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future<void>.delayed(const Duration(milliseconds: 80));
      if (!mounted) {
        return;
      }
      if (!_scrollController.hasClients) {
        _restoringInitialScroll = false;
        return;
      }
      final target = _scrollController.position.maxScrollExtent *
          widget.initialScrollProgress;
      _scrollController.jumpTo(
        target.clamp(0.0, _scrollController.position.maxScrollExtent),
      );
      if (mounted) {
        setState(() {
          _scrollFraction = widget.initialScrollProgress.clamp(0.0, 1.0);
        });
      }
      _restoringInitialScroll = false;
    });
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 500), () {
      unawaited(_saveReadingState(touchLastOpened: false));
    });
  }

  Future<void> _saveReadingState({required bool touchLastOpened}) {
    return ref.read(bookStorageProvider).updateReadingState(
          bookId: widget.book.id,
          chapterIndex: _chapterIndex,
          scrollProgress: _scrollFraction,
          ttsSentenceIndex: _ttsSentenceIndex,
          fontSize: _fontSize,
          speechRate: _speechRate,
          pitch: _pitch,
          ttsVoiceName: _voice?.name,
          ttsVoiceLocale: _voice?.locale,
          touchLastOpened: touchLastOpened,
        );
  }

  Future<void> _scrollToSentence(int index) async {
    final paragraphIndex = _paragraphIndexForSentence(index);
    final context = _paragraphKeys[paragraphIndex]?.currentContext;
    if (context == null || !_scrollController.hasClients) {
      return;
    }

    await Scrollable.ensureVisible(
      context,
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
      alignment: 0.42,
      alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
    );
  }

  int _paragraphIndexForSentence(int sentenceIndex) {
    final paragraphs = _chapter.sentenceParagraphs.isNotEmpty
        ? _chapter.sentenceParagraphs
        : [_chapter.sentences];
    var offset = 0;
    for (var i = 0; i < paragraphs.length; i++) {
      final nextOffset = offset + paragraphs[i].length;
      if (sentenceIndex < nextOffset) {
        return i;
      }
      offset = nextOffset;
    }
    return paragraphs.isEmpty ? 0 : paragraphs.length - 1;
  }

  Future<void> _showTtsSettings() async {
    final ttsHandler = ref.read(ttsAudioHandlerProvider);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return _TtsSettingsSheet(
          ttsHandler: ttsHandler,
          onSpeechRateChanged: (value) {
            _speechRate = value;
            _scheduleSave();
          },
          onPitchChanged: (value) {
            _pitch = value;
            _scheduleSave();
          },
          onVoiceChanged: (voice) {
            _voice = voice;
            _scheduleSave();
          },
        );
      },
    );
    _scheduleChromeAutoHide();
  }

  Future<void> _showChapterList() async {
    final selectedIndex = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return _ChapterListSheet(
          chapters: widget.chapters,
          currentIndex: _chapterIndex,
        );
      },
    );

    if (selectedIndex != null && mounted) {
      await _switchChapter(selectedIndex);
    }
    _scheduleChromeAutoHide();
  }

  void _showChromeTemporarily() {
    if (!_chromeVisible) {
      setState(() {
        _chromeVisible = true;
      });
    }
    _scheduleChromeAutoHide();
  }

  void _scheduleChromeAutoHide() {
    _chromeTimer?.cancel();
    _chromeTimer = Timer(const Duration(seconds: 10), () {
      if (!mounted || !_chromeVisible) {
        return;
      }
      setState(() {
        _chromeVisible = false;
      });
    });
  }
}

class _SentenceContent extends StatelessWidget {
  const _SentenceContent({
    required this.chapter,
    required this.fontSize,
    required this.highlightedSentenceIndex,
    required this.paragraphKeyBuilder,
  });

  final Chapter chapter;
  final double fontSize;
  final int? highlightedSentenceIndex;
  final GlobalKey Function(int index) paragraphKeyBuilder;

  @override
  Widget build(BuildContext context) {
    final sentenceParagraphs = chapter.sentenceParagraphs.isNotEmpty
        ? chapter.sentenceParagraphs
        : [chapter.sentences];
    final sentences = [
      for (final paragraph in sentenceParagraphs) ...paragraph,
    ];
    if (sentences.isEmpty) {
      return Text(
        '本章暂无可朗读文本',
        style: TextStyle(
          fontSize: fontSize,
          height: 1.72,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: _buildParagraphWidgets(context, sentenceParagraphs),
    );
  }

  List<Widget> _buildParagraphWidgets(
    BuildContext context,
    List<List<String>> sentenceParagraphs,
  ) {
    var globalIndex = 0;
    final widgets = <Widget>[];
    final baseStyle = TextStyle(
      fontSize: fontSize,
      height: 1.72,
      color: Theme.of(context).colorScheme.onSurface,
    );
    final highlightStyle = baseStyle.copyWith(
      backgroundColor: const Color(0xFFFFF0A8),
    );

    for (var paragraphIndex = 0;
        paragraphIndex < sentenceParagraphs.length;
        paragraphIndex++) {
      final paragraph = sentenceParagraphs[paragraphIndex];
      final spans = <InlineSpan>[];
      for (var localIndex = 0; localIndex < paragraph.length; localIndex++) {
        final sentence = paragraph[localIndex];
        final sentenceIndex = globalIndex;
        spans.add(
          TextSpan(
            text: _displaySentence(
              sentence,
              isLastInParagraph: localIndex == paragraph.length - 1,
            ),
            style: highlightedSentenceIndex == sentenceIndex
                ? highlightStyle
                : null,
          ),
        );
        globalIndex++;
      }

      widgets.add(
        Padding(
          key: paragraphKeyBuilder(paragraphIndex),
          padding: const EdgeInsets.only(bottom: 16),
          child: RichText(
            text: TextSpan(
              style: baseStyle,
              children: spans,
            ),
          ),
        ),
      );
    }

    return widgets;
  }

  String _displaySentence(String sentence, {required bool isLastInParagraph}) {
    if (isLastInParagraph || sentence.isEmpty) {
      return sentence;
    }

    final codeUnit = sentence.codeUnitAt(sentence.length - 1);
    final isAscii = codeUnit <= 0x7F;
    return isAscii ? '$sentence ' : sentence;
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.title,
    required this.chapterTitle,
    required this.onBack,
    required this.onShowChapters,
  });

  final String title;
  final String chapterTitle;
  final VoidCallback onBack;
  final VoidCallback onShowChapters;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.96),
      elevation: 1,
      child: SizedBox(
        height: 64,
        child: Row(
          children: [
            IconButton(
              tooltip: '返回',
              icon: const Icon(Icons.arrow_back),
              onPressed: onBack,
            ),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(
                    chapterTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: '目录',
              icon: const Icon(Icons.format_list_bulleted),
              onPressed: onShowChapters,
            ),
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }
}

class _ChapterListSheet extends StatelessWidget {
  const _ChapterListSheet({
    required this.chapters,
    required this.currentIndex,
  });

  final List<Chapter> chapters;
  final int currentIndex;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.72,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text(
                '目录',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            Expanded(
              child: ListView.separated(
                itemCount: chapters.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final selected = index == currentIndex;
                  final chapter = chapters[index];
                  return ListTile(
                    selected: selected,
                    selectedTileColor:
                        colorScheme.primaryContainer.withValues(alpha: 0.42),
                    leading: Text('${index + 1}'),
                    title: Text(
                      chapter.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: selected ? const Icon(Icons.check) : null,
                    onTap: () => Navigator.of(context).pop(index),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.progress,
    required this.fontSize,
    required this.playbackStateStream,
    required this.onFontSizeChanged,
    required this.onPlayPause,
    required this.onPreviousSentence,
    required this.onNextSentence,
    required this.onTtsSettings,
  });

  final double progress;
  final double fontSize;
  final Stream<PlaybackState> playbackStateStream;
  final ValueChanged<double> onFontSizeChanged;
  final VoidCallback onPlayPause;
  final VoidCallback onPreviousSentence;
  final VoidCallback onNextSentence;
  final VoidCallback onTtsSettings;

  @override
  Widget build(BuildContext context) {
    final percent = (progress * 100).clamp(0, 100).toStringAsFixed(1);

    return Material(
      color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.96),
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text('进度 $percent%'),
                const Spacer(),
                StreamBuilder<PlaybackState>(
                  stream: playbackStateStream,
                  builder: (context, snapshot) {
                    final playing = snapshot.data?.playing ?? false;
                    return Row(
                      children: [
                        IconButton(
                          tooltip: '上一句',
                          icon: const Icon(Icons.skip_previous),
                          onPressed: onPreviousSentence,
                        ),
                        IconButton.filled(
                          tooltip: playing ? '暂停' : '播放',
                          icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                          onPressed: onPlayPause,
                        ),
                        IconButton(
                          tooltip: '下一句',
                          icon: const Icon(Icons.skip_next),
                          onPressed: onNextSentence,
                        ),
                      ],
                    );
                  },
                ),
                const Spacer(),
                IconButton(
                  tooltip: '朗读设置',
                  icon: const Icon(Icons.tune),
                  onPressed: onTtsSettings,
                ),
                const Icon(Icons.text_fields, size: 20),
                const SizedBox(width: 8),
                Text(fontSize.round().toString()),
              ],
            ),
            Slider(
              value: fontSize,
              min: 15,
              max: 28,
              divisions: 13,
              label: fontSize.round().toString(),
              onChanged: onFontSizeChanged,
            ),
          ],
        ),
      ),
    );
  }
}

class _TtsSettingsSheet extends StatefulWidget {
  const _TtsSettingsSheet({
    required this.ttsHandler,
    required this.onSpeechRateChanged,
    required this.onPitchChanged,
    required this.onVoiceChanged,
  });

  final MyTtsAudioHandler ttsHandler;
  final ValueChanged<double> onSpeechRateChanged;
  final ValueChanged<double> onPitchChanged;
  final ValueChanged<TtsVoiceOption> onVoiceChanged;

  @override
  State<_TtsSettingsSheet> createState() => _TtsSettingsSheetState();
}

class _TtsSettingsSheetState extends State<_TtsSettingsSheet> {
  late double _speechRate;
  late double _pitch;
  late Future<List<TtsVoiceOption>> _voicesFuture;

  @override
  void initState() {
    super.initState();
    _speechRate = widget.ttsHandler.speechRate;
    _pitch = widget.ttsHandler.pitch;
    _voicesFuture = widget.ttsHandler.getVoiceOptions();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '朗读设置',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            _LabeledSlider(
              label: '语速',
              valueText: '${_speechRate.toStringAsFixed(2)}x',
              value: _speechRate,
              min: 0.75,
              max: 2.5,
              divisions: 7,
              onChanged: (value) {
                final stepped = (value * 4).round() / 4;
                setState(() {
                  _speechRate = stepped;
                });
                widget.ttsHandler.setSpeechRate(stepped);
                widget.onSpeechRateChanged(stepped);
              },
            ),
            _LabeledSlider(
              label: '音调',
              valueText: _pitch.toStringAsFixed(1),
              value: _pitch,
              min: 0.6,
              max: 1.6,
              divisions: 10,
              onChanged: (value) {
                setState(() {
                  _pitch = value;
                });
                widget.ttsHandler.setPitch(value);
                widget.onPitchChanged(value);
              },
            ),
            const SizedBox(height: 8),
            FutureBuilder<List<TtsVoiceOption>>(
              future: _voicesFuture,
              builder: (context, snapshot) {
                final voices = snapshot.data ?? const <TtsVoiceOption>[];
                if (snapshot.connectionState != ConnectionState.done) {
                  return const LinearProgressIndicator();
                }
                if (voices.isEmpty) {
                  return const Text('当前系统 TTS 没有返回可选音色');
                }

                final current = widget.ttsHandler.voice;
                final selected = voices.any((voice) =>
                        voice.name == current?.name &&
                        voice.locale == current?.locale)
                    ? current
                    : null;

                return DropdownButtonFormField<TtsVoiceOption>(
                  initialValue: selected,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: '音色',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final voice in voices)
                      DropdownMenuItem<TtsVoiceOption>(
                        value: voice,
                        child: Text(
                          voice.label,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (voice) {
                    if (voice != null) {
                      widget.ttsHandler.setVoice(voice);
                      widget.onVoiceChanged(voice);
                    }
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _LabeledSlider extends StatelessWidget {
  const _LabeledSlider({
    required this.label,
    required this.valueText,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
  });

  final String label;
  final String valueText;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Text(label),
            const Spacer(),
            Text(valueText),
          ],
        ),
        Slider(
          value: value,
          min: min,
          max: max,
          divisions: divisions,
          label: valueText,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _ChapterNavButton extends StatelessWidget {
  const _ChapterNavButton({
    required this.label,
    required this.enabled,
    required this.onPressed,
  });

  final String label;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.center,
      child: OutlinedButton(
        onPressed: enabled ? onPressed : null,
        child: Text(label),
      ),
    );
  }
}
