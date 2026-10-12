import '../models/media.dart';

/// 10-minute in-memory cache of resolved links so re-pasting or re-opening
/// the same link is instant and costs no network.
class ResolverCache {
  ResolverCache({this.ttl = const Duration(minutes: 10)});

  final Duration ttl;
  final _entries = <String, _Entry>{};

  ResolvedMedia? get(String normalizedUrl) {
    final entry = _entries[normalizedUrl];
    if (entry == null) return null;
    if (DateTime.now().difference(entry.at) > ttl) {
      _entries.remove(normalizedUrl);
      return null;
    }
    return entry.media;
  }

  void put(String normalizedUrl, ResolvedMedia media) {
    _entries[normalizedUrl] = _Entry(media, DateTime.now());
    // Keep the cache small; drop the oldest entries beyond 50.
    if (_entries.length > 50) {
      final oldest = _entries.keys.first;
      _entries.remove(oldest);
    }
  }

  void clear() => _entries.clear();
}

class _Entry {
  _Entry(this.media, this.at);
  final ResolvedMedia media;
  final DateTime at;
}
