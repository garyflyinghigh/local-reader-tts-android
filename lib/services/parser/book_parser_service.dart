import 'dart:io';

import '../../models/book.dart';
import '../../models/chapter.dart';
import 'epub_parser.dart';
import 'txt_parser.dart';

class ParsedBook {
  const ParsedBook({
    required this.book,
    required this.chapters,
  });

  final Book book;
  final List<Chapter> chapters;

  ParsedBook copyWith({
    Book? book,
    List<Chapter>? chapters,
  }) {
    return ParsedBook(
      book: book ?? this.book,
      chapters: chapters ?? this.chapters,
    );
  }
}

class BookParserService {
  BookParserService({
    TxtParser? txtParser,
    EpubParser? epubParser,
  })  : _txtParser = txtParser ?? TxtParser(),
        _epubParser = epubParser ?? EpubParser();

  final TxtParser _txtParser;
  final EpubParser _epubParser;

  Future<ParsedBook> parse(String path) async {
    final file = File(path);
    final format = _detectFormat(path);
    final fileName = path.split(Platform.pathSeparator).last;
    final title = fileName.replaceFirst(
        RegExp(r'\.(txt|epub)$', caseSensitive: false), '');

    final chapters = switch (format) {
      BookFormat.txt => await _txtParser.parse(file),
      BookFormat.epub => await _epubParser.parse(file),
    };

    return ParsedBook(
      book: Book(
        id: path,
        title: title,
        path: path,
        format: format,
      ),
      chapters: chapters,
    );
  }

  BookFormat _detectFormat(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.txt')) {
      return BookFormat.txt;
    }
    if (lower.endsWith('.epub')) {
      return BookFormat.epub;
    }
    throw UnsupportedError('仅支持 TXT 和 EPUB 文件');
  }
}
