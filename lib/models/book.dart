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
    this.fontSize = 19,
    this.speechRate = 1,
    this.pitch = 1,
    this.ttsVoiceName,
    this.ttsVoiceLocale,
    this.lastOpenedAt,
  });

  final String id;
  final String title;
  final String path;
  final BookFormat format;
  final int currentChapterIndex;
  final double progress;
  final int ttsSentenceIndex;
  final double fontSize;
  final double speechRate;
  final double pitch;
  final String? ttsVoiceName;
  final String? ttsVoiceLocale;
  final DateTime? lastOpenedAt;

  Book copyWith({
    String? id,
    String? title,
    String? path,
    BookFormat? format,
    int? currentChapterIndex,
    double? progress,
    int? ttsSentenceIndex,
    double? fontSize,
    double? speechRate,
    double? pitch,
    String? ttsVoiceName,
    String? ttsVoiceLocale,
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
      fontSize: fontSize ?? this.fontSize,
      speechRate: speechRate ?? this.speechRate,
      pitch: pitch ?? this.pitch,
      ttsVoiceName: ttsVoiceName ?? this.ttsVoiceName,
      ttsVoiceLocale: ttsVoiceLocale ?? this.ttsVoiceLocale,
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
      'fontSize': fontSize,
      'speechRate': speechRate,
      'pitch': pitch,
      'ttsVoiceName': ttsVoiceName,
      'ttsVoiceLocale': ttsVoiceLocale,
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
      fontSize: _readDouble(json['fontSize'], fallback: 19).clamp(15.0, 28.0),
      speechRate: _readDouble(json['speechRate'], fallback: 1).clamp(0.75, 2.5),
      pitch: _readDouble(json['pitch'], fallback: 1).clamp(0.6, 1.6),
      ttsVoiceName: _readNullableString(json['ttsVoiceName']),
      ttsVoiceLocale: _readNullableString(json['ttsVoiceLocale']),
      lastOpenedAt: DateTime.tryParse(json['lastOpenedAt']?.toString() ?? ''),
    );
  }

  static int _readInt(Object? value) {
    if (value is int) {
      return value;
    }
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static double _readDouble(Object? value, {double fallback = 0}) {
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse(value?.toString() ?? '') ?? fallback;
  }

  static String? _readNullableString(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }
}
