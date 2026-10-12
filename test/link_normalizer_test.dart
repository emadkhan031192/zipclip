import 'package:flutter_test/flutter_test.dart';
import 'package:zipclip/core/resolver/link_normalizer.dart';

void main() {
  group('LinkNormalizer.normalize', () {
    test('strips tracking params, fragments and sorts the rest', () {
      expect(
        LinkNormalizer.normalize(
            'https://www.example.com/watch?v=88&fbclid=abc&utm_source=x#frag',),
        'https://example.com/watch?v=88',
      );
    });

    test('lowercases host and strips www/m prefixes', () {
      expect(
        LinkNormalizer.normalize('https://WWW.Example.COM/abc'),
        'https://example.com/abc',
      );
      expect(
        LinkNormalizer.normalize('https://m.example.com/abc'),
        'https://example.com/abc',
      );
    });

    test('upgrades http to https and drops trailing slash', () {
      expect(
        LinkNormalizer.normalize('http://example.com/abc/'),
        'https://example.com/abc',
      );
    });

    test('same video in different forms normalizes identically', () {
      final a = LinkNormalizer.normalize(
          'https://example.com/v/123?utm_campaign=a&x=1',);
      final b =
          LinkNormalizer.normalize('https://www.example.com/v/123?x=1');
      expect(a, isNotNull);
      expect(a, b);
    });

    test('rejects non-links', () {
      expect(LinkNormalizer.normalize('not a link'), isNull);
      expect(LinkNormalizer.normalize('ftp://example.com/x'), isNull);
      expect(LinkNormalizer.normalize(''), isNull);
      expect(LinkNormalizer.normalize('just some text'), isNull);
    });
  });

  group('LinkNormalizer.looksLikeLink', () {
    test('accepts http links, rejects the rest', () {
      expect(
          LinkNormalizer.looksLikeLink('https://example.com/v/1'), isTrue,);
      expect(LinkNormalizer.looksLikeLink('hello world'), isFalse);
      expect(LinkNormalizer.looksLikeLink('https://a b.com'), isFalse);
      expect(LinkNormalizer.looksLikeLink(''), isFalse);
    });
  });

  group('LinkNormalizer.shortForm', () {
    test('shows host + path compactly', () {
      expect(
        LinkNormalizer.shortForm('https://www.short.example/ZK3pL9'),
        'short.example/ZK3pL9',
      );
    });
  });
}
