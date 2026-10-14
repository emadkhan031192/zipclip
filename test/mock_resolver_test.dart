import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zipclip/core/models/media.dart';
import 'package:zipclip/core/resolver/link_resolver.dart';
import 'package:zipclip/core/resolver/mock_resolver.dart';

/// Dio that answers HEAD with a canned content-length: no network in tests.
Dio _cannedHeadDio({int length = 14889779}) {
  final dio = Dio();
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        if (options.method == 'HEAD') {
          return handler.resolve(
            Response(
              requestOptions: options,
              statusCode: 200,
              headers: Headers.fromMap({
                'content-length': ['$length'],
              }),
            ),
          );
        }
        return handler.next(options);
      },
    ),
  );
  return dio;
}

void main() {
  group('MockResolver', () {
    test('supports ordinary http(s) links', () {
      final r = MockResolver(dio: _cannedHeadDio());
      expect(r.supports('https://short.example/ZK3pL9'), isTrue);
      expect(r.supports('http://example.com/v'), isTrue);
    });

    test('refuses non-links and the demo unsupported hosts', () {
      final r = MockResolver(dio: _cannedHeadDio());
      expect(r.supports('not a link'), isFalse);
      expect(r.supports('https://unsupported.example/v/1'), isFalse);
      expect(r.supports('https://example.invalid/v/1'), isFalse);
    });

    test('resolve returns the documented ResolvedMedia shape', () async {
      final r = MockResolver(dio: _cannedHeadDio());
      final media =
          await r.resolve('https://short.example/ZK3pL9?utm_source=x');
      expect(media.sourceUrl, 'https://short.example/ZK3pL9');
      expect(media.title, isNotEmpty);
      expect(media.author, isNotEmpty);
      expect(media.thumbnailUrl, isNotEmpty);
      expect(media.streams.map((s) => s.label),
          containsAll(['1080p', '720p', '360p', 'Audio']),);
      expect(media.offersWatermarkFree, isTrue);
      // Sizes come from the (canned) HEAD request: real measured values.
      expect(media.streams.every((s) => s.sizeBytes == 14889779), isTrue);
    });

    test('resolve throws a user-facing error for unsupported links',
        () async {
      final r = MockResolver(dio: _cannedHeadDio());
      expect(
        () => r.resolve('https://unsupported.example/v/1'),
        throwsA(isA<ResolveException>().having(
            (e) => e.notSupported, 'notSupported', isTrue,),),
      );
    });

    test('pickStream honors quality and the watermark-free flag', () async {
      final r = MockResolver(dio: _cannedHeadDio());
      final media = await r.resolve('https://short.example/ZK3pL9');

      final clean720 = media.pickStream(
        format: SaveFormat.video,
        qualityLabel: '720p',
        watermarkFree: true,
      );
      expect(clean720?.label, '720p');
      expect(clean720?.watermarkFree, isTrue);

      // 1080p is watermarked in the mock; asking watermark-free falls back
      // to the best clean stream.
      final clean1080 = media.pickStream(
        format: SaveFormat.video,
        qualityLabel: '1080p',
        watermarkFree: true,
      );
      expect(clean1080?.watermarkFree, isTrue);
      expect(clean1080?.label, isNot('1080p'));

      final audio = media.pickStream(
        format: SaveFormat.audio,
        qualityLabel: 'Audio',
        watermarkFree: false,
      );
      expect(audio?.hasVideo, isFalse);
      expect(audio?.hasAudio, isTrue);

      expect(
        media.pickStream(
          format: SaveFormat.cover,
          qualityLabel: '1080p',
          watermarkFree: false,
        ),
        isNull,
      );
    });
  });
}
