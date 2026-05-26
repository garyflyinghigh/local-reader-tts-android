enum BookFormat {
  txt,
  epub,
}

class Book {
  const Book({
    required this.id,
    required this.title,
    required this.path,
    required this.format,
    this.currentChapterIndex = 0,
    this.progress = 0,
    this.ttsSentenceIndex = 0,
    this.lastOpenedAt,
  });

  final String id;
  final String title;
  final String path;
  final BookFormat format;
  final int currentChapterIndex;
  final double progress;
  final int ttsSentenceIndex;
  final DateTime? lastOpenedAt;

  Book copyWith({
    String? id,
    String? title,
    String? path,
    BookFormat? format,
    int? currentChapterIndex,
    double? progress,
    int? ttsSentenceIndex,
    DateTime? lastOpenedAt,
  }) {
    return Book(
      id: id ?? this.id,
      title: title ?? this.title,
      path: path ?? this.path,
      format: format ?? this.format,
      currentChapterIndex: currentChapterIndex ?? this.currentChapterIndex,
      progress: progress ?? this.progress,
      ttsSentenceIndex: ttsSentenceIndex ?? this.ttsSentenceIndex,
      lastOpenedAt: lastOpenedAt ?? this.lastOpenedAt,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'title': title,
      'path': path,
      'format': format.name,
      'currentChapterIndex': currentChapterIndex,
      'progress': progress,
      'ttsSentenceIndex': ttsSentenceIndex,
      'lastOpenedAt': lastOpenedAt?.toIso8601String(),
    };
  }

  static Book fromJson(Map<String, Object?> json) {
    return Book(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      path: json['path']?.toString() ?? '',
      format: BookFormat.values.firstWhere(
        (format) => format.name == json['format'],
        orElse: () => BookFormat.txt,
      ),
      currentChapterIndex: _readInt(json['currentChapterIndex']),
      progress: _readDouble(json['progress']).clamp(0.0, 1.0),
      ttsSentenceIndex: _readInt(json['ttsSentenceIndex']),
      lastOpenedAt: DateTime.tryParse(json['lastOpenedAt']?.toString() ?? ''),
    );
  }

  static int _readInt(Object? value) {
    if (value is int) {
      return value;
    }
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static double _readDouble(Object? value) {
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }
}
