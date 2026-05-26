enum ParagraphKind {
  text,
  html,
  image,
}

class Paragraph {
  const Paragraph({
    required this.kind,
    required this.content,
  });

  final ParagraphKind kind;
  final String content;
}
