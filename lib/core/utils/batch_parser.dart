import '../resolver/link_normalizer.dart';

/// One parsed line from the "Paste many links" field.
class BatchLink {
  BatchLink({required this.raw, required this.normalized});

  final String raw;
  final String normalized;
}

/// Parses the multi-line batch field: one link per line. Empty lines and
/// non-links are ignored; duplicates (by normalized URL) collapse to the
/// first occurrence, preserving order.
abstract final class BatchParser {
  static List<BatchLink> parse(String text) {
    final out = <BatchLink>[];
    final seen = <String>{};
    for (final line in text.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      final normalized = LinkNormalizer.normalize(trimmed);
      if (normalized == null) continue;
      if (seen.add(normalized)) {
        out.add(BatchLink(raw: trimmed, normalized: normalized));
      }
    }
    return out;
  }
}
