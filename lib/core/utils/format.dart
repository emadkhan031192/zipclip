/// Human-readable formatting. All numbers shown in the UI are real measured
/// values; these helpers only format them.
abstract final class ZipFormat {
  /// e.g. 14.2 MB, 980 KB, 512 B, 4.2 GB. Null/negative -> '—'.
  static String bytes(int? bytes) {
    if (bytes == null || bytes < 0) return '—';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  /// e.g. 6.8 MB/s. Null -> '—'.
  static String speed(double? bytesPerSecond) {
    if (bytesPerSecond == null || bytesPerSecond.isNaN) return '—';
    return '${bytes(bytesPerSecond.round())}/s';
  }

  /// e.g. 0:24, 1:02:03. Null -> '—'.
  static String duration(Duration? d) {
    if (d == null) return '—';
    final totalSeconds = d.inSeconds;
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    final mm = hours > 0 ? minutes.toString().padLeft(2, '0') : '$minutes';
    final ss = seconds.toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$mm:$ss' : '$mm:$ss';
  }

  /// e.g. 1.8 s, 45 s, 2.0 min. Measured elapsed time, never fake.
  static String elapsed(int milliseconds) {
    if (milliseconds < 1000) return '${milliseconds}ms';
    final s = milliseconds / 1000;
    if (s < 60) return '${s.toStringAsFixed(1)} s';
    return '${(s / 60).toStringAsFixed(1)} min';
  }

  /// e.g. '4 links found', '1 link found'.
  static String linkCount(int n) => n == 1 ? '1 link found' : '$n links found';

  /// e.g. 'Download 2 videos · 24.0 MB'.
  static String batchButton(int n, int totalBytes) =>
      'Download $n ${n == 1 ? 'video' : 'videos'} · ${bytes(totalBytes)}';
}
