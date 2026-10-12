/// Formats the user can save a resolved link as.
enum SaveFormat { video, audio, cover }

extension SaveFormatX on SaveFormat {
  String get label => switch (this) {
        SaveFormat.video => 'Video',
        SaveFormat.audio => 'Audio MP3',
        SaveFormat.cover => 'Cover',
      };

  /// MIME type used when opening/sharing the saved file.
  String get mimeType => switch (this) {
        SaveFormat.video => 'video/mp4',
        SaveFormat.audio => 'audio/mpeg',
        SaveFormat.cover => 'image/jpeg',
      };

  /// Tab label used on the Downloads screen.
  String get tabLabel => switch (this) {
        SaveFormat.video => 'Video',
        SaveFormat.audio => 'Audio',
        SaveFormat.cover => 'Images',
      };
}

/// Lifecycle of a download task.
enum TaskStatus {
  queued,
  waitingForWifi,
  downloading,
  paused,
  completed,
  failed,
  canceled,
}

extension TaskStatusX on TaskStatus {
  bool get isActive =>
      this == TaskStatus.downloading || this == TaskStatus.queued;

  String get label => switch (this) {
        TaskStatus.queued => 'Queued',
        TaskStatus.waitingForWifi => 'Waiting for Wi-Fi',
        TaskStatus.downloading => 'Downloading',
        TaskStatus.paused => 'Paused',
        TaskStatus.completed => 'Saved',
        TaskStatus.failed => 'Failed',
        TaskStatus.canceled => 'Canceled',
      };
}

/// One downloadable rendition of a resolved video.
class MediaStream {
  const MediaStream({
    required this.id,
    required this.label,
    required this.url,
    required this.container,
    required this.hasVideo,
    required this.hasAudio,
    required this.watermarkFree,
    this.sizeBytes,
  });

  final String id;
  final String label; // e.g. '1080p', '720p', '480p', 'Audio'
  final String url;
  final String container; // 'mp4', 'mp3', 'jpg'
  final bool hasVideo;
  final bool hasAudio;
  final bool watermarkFree;
  final int? sizeBytes; // filled after a HEAD request when known

  MediaStream copyWith({int? sizeBytes}) => MediaStream(
        id: id,
        label: label,
        url: url,
        container: container,
        hasVideo: hasVideo,
        hasAudio: hasAudio,
        watermarkFree: watermarkFree,
        sizeBytes: sizeBytes ?? this.sizeBytes,
      );
}

/// Result of resolving a public video link. Produced by a [LinkResolver].
class ResolvedMedia {
  const ResolvedMedia({
    required this.sourceUrl,
    required this.title,
    required this.author,
    required this.thumbnailUrl,
    required this.streams,
    this.duration,
  });

  /// Normalized source URL (see LinkNormalizer).
  final String sourceUrl;
  final String title;
  final String author;
  final Duration? duration;

  /// Either an https:// URL or an `asset://` path understood by ZipThumb.
  final String thumbnailUrl;
  final List<MediaStream> streams;

  List<MediaStream> get videoStreams =>
      streams.where((s) => s.hasVideo).toList();

  List<MediaStream> get audioStreams =>
      streams.where((s) => !s.hasVideo && s.hasAudio).toList();

  /// True when at least one stream is flagged watermark-free.
  bool get offersWatermarkFree => streams.any((s) => s.watermarkFree);

  /// Picks the stream matching the user's choices.
  ///
  /// * [SaveFormat.cover] returns null; the caller saves [thumbnailUrl].
  /// * [SaveFormat.audio] returns the best audio-only stream.
  /// * [SaveFormat.video] returns the [qualityLabel] stream, or the closest
  ///   one at or below it when missing. When [watermarkFree] is true the
  ///   choice is restricted to watermark-free streams.
  MediaStream? pickStream({
    required SaveFormat format,
    required String qualityLabel,
    required bool watermarkFree,
  }) {
    if (format == SaveFormat.cover) return null;
    var pool = format == SaveFormat.audio ? audioStreams : videoStreams;
    if (pool.isEmpty) return null;
    if (watermarkFree) {
      final clean = pool.where((s) => s.watermarkFree).toList();
      if (clean.isNotEmpty) pool = clean;
    }
    if (format == SaveFormat.audio) {
      pool.sort((a, b) => (b.sizeBytes ?? 0).compareTo(a.sizeBytes ?? 0));
      return pool.first;
    }
    int rank(String label) {
      final m = RegExp(r'(\d+)').firstMatch(label);
      return m == null ? 0 : int.parse(m.group(1)!);
    }

    final want = rank(qualityLabel);
    pool.sort((a, b) => rank(b.label).compareTo(rank(a.label)));
    // Exact match first, then closest at-or-below, then anything.
    for (final s in pool) {
      if (rank(s.label) == want) return s;
    }
    for (final s in pool) {
      if (rank(s.label) < want) return s;
    }
    return pool.first;
  }
}
