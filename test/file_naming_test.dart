import 'package:flutter_test/flutter_test.dart';
import 'package:zipclip/core/engine/file_naming.dart';

void main() {
  group('FileNameTemplate.render', () {
    final date = DateTime(2026, 10, 11, 13, 30, 5);

    test('renders all tokens', () {
      expect(
        FileNameTemplate.render(
          '{author}_{title}_{date}',
          author: '@creator',
          title: 'My Clip',
          date: date,
          quality: '1080p',
        ),
        '@creator_My Clip_20261011-133005',
      );
    });

    test('renders quality token', () {
      expect(
        FileNameTemplate.render(
          '{title}_{quality}',
          author: 'a',
          title: 't',
          date: date,
          quality: '720p',
        ),
        't_720p',
      );
    });

    test('strips illegal filename characters', () {
      expect(
        FileNameTemplate.render(
          '{title}',
          author: 'a',
          title: 'a/b\\c:d*e?f"g<h>i|j',
          date: date,
          quality: 'q',
        ),
        'abcdefghij',
      );
    });

    test('collapses whitespace and trims', () {
      expect(
        FileNameTemplate.render(
          '{title}',
          author: 'a',
          title: '  lots   of   space  ',
          date: date,
          quality: 'q',
        ),
        'lots of space',
      );
    });

    test('falls back when everything is stripped', () {
      expect(
        FileNameTemplate.render(
          '///',
          author: 'a',
          title: 't',
          date: date,
          quality: 'q',
        ),
        'zipclip_20261011-133005',
      );
    });

    test('caps length at 120 chars', () {
      final long = 'x' * 200;
      final out = FileNameTemplate.render(
        '{title}',
        author: 'a',
        title: long,
        date: date,
        quality: 'q',
      );
      expect(out.length, lessThanOrEqualTo(120));
    });
  });
}
