import 'dart:io';

import '../../models/chapter.dart';
import '../../models/paragraph.dart';
import 'text_decoder.dart';
import '../tts/text_splitter.dart';

class TxtParser {
  static final RegExp _chapterHeading = RegExp(
    r'^\s*第\s*[一二三四五六七八九十百千万零〇\d]+\s*[章回卷节部].*$',
    multiLine: true,
  );

  Future<List<Chapter>> parse(File file) async {
    final bytes = await file.readAsBytes();
    final text = await TextDecoder.decodeChineseText(bytes);
    return _splitChapters(text);
  }

  List<Chapter> _splitChapters(String text) {
    final normalized = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final matches = _chapterHeading.allMatches(normalized).toList();

    if (matches.isEmpty) {
      return [
        _buildChapter(
          title: '正文',
          body: normalized,
        ),
      ];
    }

    final chapters = <Chapter>[];
    for (var i = 0; i < matches.length; i++) {
      final current = matches[i];
      final nextStart =
          i + 1 < matches.length ? matches[i + 1].start : normalized.length;
      final title = current.group(0)?.trim();
      final body = normalized.substring(current.end, nextStart).trim();
      chapters.add(
        _buildChapter(
          title: title == null || title.isEmpty ? '第 ${i + 1} 章' : title,
          body: body,
        ),
      );
    }

    final preface = normalized.substring(0, matches.first.start).trim();
    if (preface.isNotEmpty) {
      chapters.insert(
        0,
        _buildChapter(title: '序章', body: preface),
      );
    }
    return chapters;
  }

  Chapter _buildChapter({
    required String title,
    required String body,
  }) {
    final paragraphTexts = body
        .split(RegExp(r'\n{2,}|\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
    final sentenceParagraphs = paragraphTexts
        .map(splitSentences)
        .where((sentences) => sentences.isNotEmpty)
        .toList(growable: false);
    final paragraphs = paragraphTexts
        .map((line) => Paragraph(kind: ParagraphKind.text, content: line))
        .toList(growable: false);

    return Chapter(
      title: title,
      sentences: [
        for (final paragraph in sentenceParagraphs) ...paragraph,
      ],
      sentenceParagraphs: sentenceParagraphs,
      paragraphs: paragraphs,
    );
  }

  static List<String> splitSentences(String text) {
    return TtsTextSplitter.split(text);
  }
}
