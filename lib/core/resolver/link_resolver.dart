import '../models/media.dart';

/// Thrown when a link cannot be resolved. [message] is user-facing.
class ResolveException implements Exception {
  const ResolveException(this.message, {this.notSupported = false});

  final String message;
  final bool notSupported;

  @override
  String toString() => 'ResolveException: $message';
}

/// The single seam between ZipClip and any video source.
///
/// Implementations must only ever resolve *public* videos: never attempt to
/// access private, protected or login-only content, and never bypass DRM or
/// other access controls. Whoever plugs in a resolver is responsible for
/// making sure it respects the source site's terms of service and the rights
/// of the video owner (see README.md).
abstract class LinkResolver {
  /// Whether this resolver can handle [url] at all.
  bool supports(String url);

  /// Resolves a public video URL into downloadable media.
  ///
  /// Throws [ResolveException] with a user-facing message on failure.
  Future<ResolvedMedia> resolve(String url);
}
