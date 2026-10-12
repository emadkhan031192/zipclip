/// Canonicalizes video links so the same video pasted in different forms
/// (tracking params, fragments, www vs bare host, case) maps to one key.
/// Used for duplicate detection and the 10-minute resolve cache.
abstract final class LinkNormalizer {
  /// Query parameters that never identify the video; stripped on normalize.
  static const Set<String> trackingParams = {
    'utm_source',
    'utm_medium',
    'utm_campaign',
    'utm_term',
    'utm_content',
    'utm_id',
    'fbclid',
    'gclid',
    'igshid',
    'mc_cid',
    'mc_eid',
    'vero_conv',
    'vero_id',
    'ref',
    'referrer',
    'si', // e.g. youtu.be share ids
  };

  /// Returns the canonical form of [url], or null when [url] is not a usable
  /// http(s) link.
  static String? normalize(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !uri.hasScheme) return null;
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') return null;
    if (uri.host.isEmpty) return null;

    var host = uri.host.toLowerCase();
    for (final prefix in ['www.', 'm.', 'mobile.']) {
      if (host.startsWith(prefix)) {
        host = host.substring(prefix.length);
        break;
      }
    }

    var path = uri.path;
    if (path.length > 1 && path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }

    final kept = <String, String>{};
    uri.queryParameters.forEach((key, value) {
      if (!trackingParams.contains(key.toLowerCase())) {
        kept[key] = value;
      }
    });
    final sortedKeys = kept.keys.toList()..sort();
    final sortedQuery = {for (final k in sortedKeys) k: kept[k]!};

    final canonical = uri.replace(
      scheme: 'https',
      host: host,
      path: path,
      // NB: empty collections clear the component; null leaves it unchanged.
      queryParameters: sortedQuery,
      fragment: '',
      userInfo: null,
    );
    var result = canonical.toString();
    // Uri keeps a dangling '?' / '#' for emptied components; drop them.
    while (result.endsWith('?') || result.endsWith('#')) {
      result = result.substring(0, result.length - 1);
    }
    return result;
  }

  /// Quick check used for the clipboard card and batch parsing.
  static bool looksLikeLink(String text) {
    final t = text.trim();
    if (t.isEmpty || t.contains(' ') || t.contains('\n')) return false;
    return normalize(t) != null;
  }

  /// Short host/path form shown under titles, e.g. `short.example/ZK3pL9`.
  static String shortForm(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || uri.host.isEmpty) return url.trim();
    var host = uri.host.toLowerCase();
    if (host.startsWith('www.')) host = host.substring(4);
    final path = uri.path.length > 1 ? uri.path : '';
    final shown = '$host$path';
    return shown.length > 34 ? '${shown.substring(0, 33)}…' : shown;
  }
}
