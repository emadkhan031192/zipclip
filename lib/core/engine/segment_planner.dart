import 'dart:math';

/// Inclusive byte range [start, end].
class ByteRange {
  const ByteRange(this.start, this.end);

  final int start;
  final int end;

  int get length => end - start + 1;

  Map<String, dynamic> toJson() => {'start': start, 'end': end};

  factory ByteRange.fromJson(Map<String, dynamic> json) =>
      ByteRange(json['start'] as int, json['end'] as int);
}

/// Decides how to split a download into parallel Range segments.
///
/// Files smaller than [minSegmentBytes] (or with unknown size) download in
/// one piece; larger files split into up to [maxSegments] ranges.
abstract final class SegmentPlanner {
  static List<ByteRange> plan({
    required int? totalBytes,
    int maxSegments = 4,
    int minSegmentBytes = 2 * 1024 * 1024,
  }) {
    if (totalBytes == null || totalBytes <= 0) {
      return const [ByteRange(0, -1)]; // unknown size: single open stream
    }
    var count = totalBytes ~/ minSegmentBytes;
    count = max(1, min(count, maxSegments));
    if (count == 1) return [ByteRange(0, totalBytes - 1)];

    final ranges = <ByteRange>[];
    final base = totalBytes ~/ count;
    final remainder = totalBytes % count;
    var start = 0;
    for (var i = 0; i < count; i++) {
      // Spread the remainder one byte per leading segment so sizes differ
      // by at most 1.
      final size = base + (i < remainder ? 1 : 0);
      final end = start + size - 1;
      ranges.add(ByteRange(start, end));
      start = end + 1;
    }
    return ranges;
  }
}
