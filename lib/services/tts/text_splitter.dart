class TtsTextSplitter {
  const TtsTextSplitter._();

  static List<String> split(String text) {
    return text
        .replaceAll('\r\n', '\n')
        .split(RegExp(r'(?<=[。！？!?；;])|\n+'))
        .map((sentence) => sentence.trim())
        .where((sentence) => sentence.isNotEmpty)
        .toList(growable: false);
  }
}
