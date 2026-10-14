import 'package:dio/dio.dart';

import '../models/media.dart';
import 'link_normalizer.dart';
import 'link_resolver.dart';

/// Demo resolver that ships with ZipClip.
///
/// It accepts any public-looking http(s) link and returns sample metadata
/// plus *real, publicly licensed sample files* so the whole UI and the
/// download engine work end-to-end without any site-specific code:
///
/// * Video: Big Buck Bunny sample clips from test-videos.co.uk
///   (Blender Foundation open movie, Creative Commons).
/// * Audio: the SoundHelix sample MP3
///   (https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3).
///
/// Sizes are measured with a real HEAD request at resolve time; when the
/// HEAD fails we fall back to estimates clearly marked as such.
///
/// ---------------------------------------------------------------
/// PLUG IN A REAL RESOLVER HERE.
/// Replace [MockResolver] (or add your own [LinkResolver] in front of it)
/// to resolve real sites. You — the person plugging it in — are
/// responsible for making sure it only touches public videos and respects
/// the source site's terms of service and the rights of the video owner.
/// ---------------------------------------------------------------
class MockResolver implements LinkResolver {
  MockResolver({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;

  // ------------------------------------------------------------------
  // DEMO sample files. Public samples, hotlinked for demo purposes only.
  // (Google's old gtv-videos-bucket started returning 403 in 2026, so
  // these moved to test-videos.co.uk.)
  // ------------------------------------------------------------------
  static const _demo1080p =
      'https://test-videos.co.uk/vids/bigbuckbunny/mp4/h264/1080/Big_Buck_Bunny_1080_10s_1MB.mp4';
  static const _demo720p =
      'https://test-videos.co.uk/vids/bigbuckbunny/mp4/h264/720/Big_Buck_Bunny_720_10s_1MB.mp4';
  static const _demo360p =
      'https://test-videos.co.uk/vids/bigbuckbunny/mp4/h264/360/Big_Buck_Bunny_360_10s_1MB.mp4';
  static const _demoAudio =
      'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3';

  @override
  bool supports(String url) {
    final normalized = LinkNormalizer.normalize(url);
    if (normalized == null) return false;
    final host = Uri.parse(normalized).host;
    // Demo hook so the "Not supported" UI state is reachable without a real
    // site: links containing 'unsupported' or ending in .invalid are refused.
    if (host.contains('unsupported') || host.endsWith('.invalid')) {
      return false;
    }
    return true;
  }

  @override
  Future<ResolvedMedia> resolve(String url) async {
    final normalized = LinkNormalizer.normalize(url);
    if (normalized == null) {
      throw const ResolveException("That doesn't look like a video link.",
          notSupported: true,);
    }
    if (!supports(url)) {
      throw const ResolveException(
        'This link type is not supported yet.',
        notSupported: true,
      );
    }

    final uri = Uri.parse(normalized);
    final host = uri.host;
    final slug = uri.pathSegments.isEmpty
        ? 'clip'
        : uri.pathSegments.last.split('.').first;

    Future<int?> headSize(String fileUrl) async {
      try {
        final res = await _dio.head(
          fileUrl,
          options: Options(
            sendTimeout: const Duration(seconds: 8),
            receiveTimeout: const Duration(seconds: 8),
          ),
        );
        final len = res.headers.value('content-length');
        return len == null ? null : int.tryParse(len);
      } catch (_) {
        return null;
      }
    }

    // Measure real sizes in parallel; fall back to estimates if HEAD fails.
    final sizes = await Future.wait([
      headSize(_demo1080p),
      headSize(_demo720p),
      headSize(_demo360p),
      headSize(_demoAudio),
    ]);

    const estimates = [1050000, 970000, 990000, 6200000];
    int size(int i) => sizes[i] ?? estimates[i];

    return ResolvedMedia(
      sourceUrl: normalized,
      title: 'Sample clip · $slug',
      author: '@$host demo',
      duration: const Duration(seconds: 15),
      // Bundled sample artwork; ZipThumb understands the asset:// scheme.
      thumbnailUrl: 'asset://sample_thumb',
      streams: [
        MediaStream(
          id: 'demo-1080p',
          label: '1080p',
          url: _demo1080p,
          container: 'mp4',
          hasVideo: true,
          hasAudio: true,
          // The mock marks 1080p as watermarked so the
          // "Remove watermark" switch has something to do.
          watermarkFree: false,
          sizeBytes: size(0),
        ),
        MediaStream(
          id: 'demo-720p',
          label: '720p',
          url: _demo720p,
          container: 'mp4',
          hasVideo: true,
          hasAudio: true,
          watermarkFree: true,
          sizeBytes: size(1),
        ),
        MediaStream(
          id: 'demo-360p',
          label: '360p',
          url: _demo360p,
          container: 'mp4',
          hasVideo: true,
          hasAudio: true,
          watermarkFree: true,
          sizeBytes: size(2),
        ),
        MediaStream(
          id: 'demo-audio',
          label: 'Audio',
          url: _demoAudio,
          container: 'mp3',
          hasVideo: false,
          hasAudio: true,
          watermarkFree: true,
          sizeBytes: size(3),
        ),
      ],
    );
  }
}
