import 'dart:convert';
import 'dart:io';

import 'package:epubx/epubx.dart';

import '../../models/chapter.dart';
import '../../models/paragraph.dart';
import 'txt_parser.dart';

class EpubParser {
  Future<List<Chapter>> parse(File file) async {
    final bytes = await file.readAsBytes();
    final dynamic epubBook = await EpubReader.readBook(bytes);
    final dynamic rawChapters = epubBook.Chapters;
    final imageDataUris = _buildImageDataUriMap(epubBook);

    final chapters = <Chapter>[];
    if (rawChapters is Iterable) {
      for (final dynamic chapter in rawChapters) {
        _collectChapter(chapter, chapters, imageDataUris);
      }
    }

    if (chapters.isNotEmpty) {
      return chapters;
    }

    final dynamic title = epubBook.Title;
    return [
      Chapter(
        title: title is String && title.trim().isNotEmpty
            ? title.trim()
            : 'EPUB 正文',
        sentences: const [],
        paragraphs: const [],
      ),
    ];
  }

  void _collectChapter(
    dynamic chapter,
    List<Chapter> output,
    Map<String, String> imageDataUris,
  ) {
    final title = _readString(chapter, 'Title') ?? '未命名章节';
    final rawHtml = _readString(chapter, 'HtmlContent') ?? '';
    final contentFileName = _readString(chapter, 'ContentFileName');
    final html = _inlineImages(rawHtml, contentFileName, imageDataUris);
    final plainText = _htmlToPlainText(html);
    final sentenceParagraphs = _splitSentenceParagraphs(plainText);

    if (plainText.isNotEmpty || html.trim().isNotEmpty) {
      output.add(
        Chapter(
          title: title,
          sentences: [
            for (final paragraph in sentenceParagraphs) ...paragraph,
          ],
          sentenceParagraphs: sentenceParagraphs,
          paragraphs: [
            Paragraph(kind: ParagraphKind.html, content: html),
          ],
          htmlContent: html,
          contentFileName: contentFileName,
        ),
      );
    }

    final dynamic children = chapter.SubChapters;
    if (children is Iterable) {
      for (final dynamic child in children) {
        _collectChapter(child, output, imageDataUris);
      }
    }
  }

  String? _readString(dynamic object, String property) {
    try {
      final dynamic value = switch (property) {
        'Title' => object.Title,
        'HtmlContent' => object.HtmlContent,
        'ContentFileName' => object.ContentFileName,
        _ => null,
      };
      return value is String ? value.trim() : null;
    } on Object {
      return null;
    }
  }

  Map<String, String> _buildImageDataUriMap(dynamic epubBook) {
    final result = <String, String>{};
    try {
      final dynamic images = epubBook.Content?.Images;
      if (images is! Map) {
        return result;
      }

      for (final entry in images.entries) {
        final key = entry.key?.toString();
        final dynamic file = entry.value;
        final dynamic content = file.Content;
        if (key == null || content is! List<int>) {
          continue;
        }

        final mimeType = _readContentMimeType(file) ?? _guessImageMimeType(key);
        final dataUri = 'data:$mimeType;base64,${base64Encode(content)}';
        result[_normalizePath(key)] = dataUri;
      }
    } on Object {
      return result;
    }
    return result;
  }

  String? _readContentMimeType(dynamic file) {
    try {
      final dynamic value = file.ContentMimeType;
      return value is String && value.trim().isNotEmpty ? value.trim() : null;
    } on Object {
      return null;
    }
  }

  String _guessImageMimeType(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
      return 'image/jpeg';
    }
    if (lower.endsWith('.gif')) {
      return 'image/gif';
    }
    if (lower.endsWith('.webp')) {
      return 'image/webp';
    }
    if (lower.endsWith('.svg')) {
      return 'image/svg+xml';
    }
    return 'image/png';
  }

  String _inlineImages(
    String html,
    String? contentFileName,
    Map<String, String> imageDataUris,
  ) {
    if (html.isEmpty || imageDataUris.isEmpty) {
      return html;
    }

    return html.replaceAllMapped(
      RegExp(r'''(<img\b[^>]*?\bsrc\s*=\s*["'])([^"']+)(["'][^>]*>)''',
          caseSensitive: false),
      (match) {
        final prefix = match.group(1)!;
        final source = match.group(2)!;
        final suffix = match.group(3)!;

        if (source.startsWith('data:') ||
            source.startsWith('http://') ||
            source.startsWith('https://')) {
          return match.group(0)!;
        }

        final resolved = _resolveImagePath(source, contentFileName);
        final dataUri =
            imageDataUris[resolved] ?? imageDataUris[_normalizePath(source)];
        if (dataUri == null) {
          return match.group(0)!;
        }
        return '$prefix$dataUri$suffix';
      },
    );
  }

  String _resolveImagePath(String source, String? contentFileName) {
    final cleanedSource =
        _normalizePath(source.split('#').first.split('?').first);
    if (contentFileName == null || !contentFileName.contains('/')) {
      return cleanedSource;
    }

    final baseSegments = _normalizePath(contentFileName).split('/')
      ..removeLast();
    for (final segment in cleanedSource.split('/')) {
      if (segment.isEmpty || segment == '.') {
        continue;
      }
      if (segment == '..') {
        if (baseSegments.isNotEmpty) {
          baseSegments.removeLast();
        }
      } else {
        baseSegments.add(segment);
      }
    }
    return baseSegments.join('/');
  }

  String _normalizePath(String path) {
    return path.replaceAll('\\', '/').replaceFirst(RegExp(r'^/+'), '');
  }

  String _htmlToPlainText(String html) {
    if (html.trim().isEmpty) {
      return '';
    }

    final readableHtml = _stripNonReadableHtml(html);
    final withBreaks = readableHtml
        .replaceAll(RegExp(r'<\s*br\s*/?\s*>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'</\s*p\s*>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'</\s*div\s*>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'</\s*h[1-6]\s*>', caseSensitive: false), '\n');

    final withoutTags = withBreaks.replaceAll(RegExp(r'<[^>]+>'), '');
    return _decodeHtmlEntities(withoutTags)
        .replaceAll(RegExp(r'[ \t\u00A0]+'), ' ')
        .replaceAll(RegExp(r'\n\s+'), '\n')
        .replaceAll(RegExp(r'\s+\n'), '\n')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }

  String _stripNonReadableHtml(String html) {
    var result = html;

    for (final tag in const [
      'head',
      'script',
      'style',
      'svg',
      'math',
      'nav',
      'object',
      'iframe',
      'canvas',
    ]) {
      result = result.replaceAll(
        RegExp('<$tag\\b[^>]*>.*?</$tag>', caseSensitive: false, dotAll: true),
        ' ',
      );
    }

    result = result
        .replaceAll(
          RegExp(
            r'''<([a-zA-Z][\w:-]*)\b[^>]*(?:epub:type|role|class|id)\s*=\s*["'][^"']*(?:pagebreak|pagenum|page-num|page_number|noteref)[^"']*["'][^>]*>.*?</\1>''',
            caseSensitive: false,
            dotAll: true,
          ),
          ' ',
        )
        .replaceAll(
          RegExp(
            r'''<[^>]*(?:epub:type|role|class|id)\s*=\s*["'][^"']*(?:pagebreak|pagenum|page-num|page_number|noteref)[^"']*["'][^>]*>''',
            caseSensitive: false,
          ),
          ' ',
        )
        .replaceAll(
          RegExp(
            r'''<([a-zA-Z][\w:-]*)\b[^>]*(?:hidden|aria-hidden\s*=\s*["']true["']|style\s*=\s*["'][^"']*(?:display\s*:\s*none|visibility\s*:\s*hidden)[^"']*["'])[^>]*>.*?</\1>''',
            caseSensitive: false,
            dotAll: true,
          ),
          ' ',
        );

    return result;
  }

  String _decodeHtmlEntities(String text) {
    return text
        .replaceAllMapped(
          RegExp(r'&#x([0-9a-fA-F]+);'),
          (match) => String.fromCharCode(int.parse(match.group(1)!, radix: 16)),
        )
        .replaceAllMapped(
          RegExp(r'&#(\d+);'),
          (match) => String.fromCharCode(int.parse(match.group(1)!)),
        )
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'")
        .replaceAll('&#39;', "'");
  }

  List<List<String>> _splitSentenceParagraphs(String text) {
    return text
        .split(RegExp(r'\n{2,}|\n'))
        .map((paragraph) => TxtParser.splitSentences(paragraph))
        .where((sentences) => sentences.isNotEmpty)
        .toList(growable: false);
  }
}
