import 'package:android_reader/services/parser/txt_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('TXT sentence splitter handles Chinese punctuation and newlines', () {
    final sentences = TxtParser.splitSentences('第一句。第二句！\n第三句？');

    expect(sentences, ['第一句。', '第二句！', '第三句？']);
  });
}
