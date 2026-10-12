import 'package:flutter_test/flutter_test.dart';
import 'package:zipclip/core/utils/batch_parser.dart';

void main() {
  group('BatchParser.parse', () {
    test('parses one link per line, ignoring blanks and junk', () {
      final links = BatchParser.parse('''
https://short.example/ZK3pL9
https://short.example/Qm7xT2

not a link

https://other.example/watch?v=88
''');
      expect(links.map((l) => l.raw), [
        'https://short.example/ZK3pL9',
        'https://short.example/Qm7xT2',
        'https://other.example/watch?v=88',
      ]);
    });

    test('dedupes by normalized URL, keeping first occurrence order', () {
      final links = BatchParser.parse(
        'https://example.com/v/1?utm_source=x\n'
        'https://example.com/v/2\n'
        'https://www.example.com/v/1\n',
      );
      expect(links.length, 2);
      expect(links[0].raw, 'https://example.com/v/1?utm_source=x');
      expect(links[1].raw, 'https://example.com/v/2');
    });

    test('empty input yields no links', () {
      expect(BatchParser.parse('  \n\n'), isEmpty);
    });
  });
}
