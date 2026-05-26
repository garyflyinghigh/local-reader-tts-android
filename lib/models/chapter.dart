import 'paragraph.dart';

class Chapter {
  const Chapter({
    required this.title,
    required this.sentences,
    required this.paragraphs,
    this.sentenceParagraphs = const [],
    this.htmlContent,
    this.contentFileName,
  });

  final String title;
  final List<String> sentences;
  final List<List<String>> sentenceParagraphs;
  final List<Paragraph> paragraphs;

  /// Preserves EPUB markup for high fidelity rendering in Reader UI.
  final String? htmlContent;

  /// EPUB internal chapter file path, used to resolve relative image paths.
  final String? contentFileName;
}
