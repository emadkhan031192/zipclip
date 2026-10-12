import '../models/media.dart';

/// Persisted download task. Segment progress is stored as JSON so
/// pause/resume survives app restarts.
class StoredTask {
  StoredTask({
    required this.id,
    required this.normalizedUrl,
    required this.originalUrl,
    required this.title,
    required this.author,
    required this.thumbSource,
    required this.format,
    required this.qualityLabel,
    required this.streamUrl,
    required this.container,
    required this.status,
    required this.bytesDone,
    required this.createdAt,
    required this.updatedAt,
    this.durationMs,
    this.totalBytes,
    this.segmentsJson,
    this.fileUri,
    this.error,
    this.elapsedMs = 0,
  });

  final String id;
  final String normalizedUrl;
  final String originalUrl;
  final String title;
  final String author;
  final String thumbSource;
  final SaveFormat format;
  final String qualityLabel;
  final String streamUrl;
  final String container;
  final TaskStatus status;
  final int bytesDone;
  final int createdAt;
  final int updatedAt;
  final int? durationMs;
  final int? totalBytes;
  final String? segmentsJson;
  final String? fileUri;
  final String? error;
  final int elapsedMs;

  StoredTask copyWith({
    TaskStatus? status,
    int? bytesDone,
    int? totalBytes,
    String? segmentsJson,
    String? fileUri,
    String? error,
    int? updatedAt,
    int? elapsedMs,
  }) =>
      StoredTask(
        id: id,
        normalizedUrl: normalizedUrl,
        originalUrl: originalUrl,
        title: title,
        author: author,
        thumbSource: thumbSource,
        format: format,
        qualityLabel: qualityLabel,
        streamUrl: streamUrl,
        container: container,
        status: status ?? this.status,
        bytesDone: bytesDone ?? this.bytesDone,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        durationMs: durationMs,
        totalBytes: totalBytes ?? this.totalBytes,
        segmentsJson: segmentsJson ?? this.segmentsJson,
        fileUri: fileUri ?? this.fileUri,
        error: error,
        elapsedMs: elapsedMs ?? this.elapsedMs,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'normalized_url': normalizedUrl,
        'original_url': originalUrl,
        'title': title,
        'author': author,
        'thumb_source': thumbSource,
        'format': format.name,
        'quality_label': qualityLabel,
        'stream_url': streamUrl,
        'container': container,
        'status': status.name,
        'bytes_done': bytesDone,
        'created_at': createdAt,
        'updated_at': updatedAt,
        'duration_ms': durationMs,
        'total_bytes': totalBytes,
        'segments_json': segmentsJson,
        'file_uri': fileUri,
        'error': error,
        'elapsed_ms': elapsedMs,
      };

  factory StoredTask.fromMap(Map<String, dynamic> m) => StoredTask(
        id: m['id'] as String,
        normalizedUrl: m['normalized_url'] as String,
        originalUrl: m['original_url'] as String,
        title: m['title'] as String,
        author: m['author'] as String,
        thumbSource: m['thumb_source'] as String,
        format: SaveFormat.values.byName(m['format'] as String),
        qualityLabel: m['quality_label'] as String,
        streamUrl: m['stream_url'] as String,
        container: m['container'] as String,
        status: TaskStatus.values.byName(m['status'] as String),
        bytesDone: (m['bytes_done'] as num).toInt(),
        createdAt: (m['created_at'] as num).toInt(),
        updatedAt: (m['updated_at'] as num).toInt(),
        durationMs: (m['duration_ms'] as num?)?.toInt(),
        totalBytes: (m['total_bytes'] as num?)?.toInt(),
        segmentsJson: m['segments_json'] as String?,
        fileUri: m['file_uri'] as String?,
        error: m['error'] as String?,
        elapsedMs: (m['elapsed_ms'] as num?)?.toInt() ?? 0,
      );
}

/// A finished, saved file (download history).
class SavedItem {
  SavedItem({
    required this.id,
    required this.normalizedUrl,
    required this.originalUrl,
    required this.title,
    required this.author,
    required this.thumbPath,
    required this.format,
    required this.qualityLabel,
    required this.sizeBytes,
    required this.fileUri,
    required this.savedAt,
    this.durationMs,
  });

  final String id;
  final String normalizedUrl;
  final String originalUrl;
  final String title;
  final String author;
  final String thumbPath;
  final SaveFormat format;
  final String qualityLabel;
  final int sizeBytes;
  final String fileUri;
  final int savedAt;
  final int? durationMs;

  Map<String, dynamic> toMap() => {
        'id': id,
        'normalized_url': normalizedUrl,
        'original_url': originalUrl,
        'title': title,
        'author': author,
        'thumb_path': thumbPath,
        'format': format.name,
        'quality_label': qualityLabel,
        'size_bytes': sizeBytes,
        'file_uri': fileUri,
        'saved_at': savedAt,
        'duration_ms': durationMs,
      };

  factory SavedItem.fromMap(Map<String, dynamic> m) => SavedItem(
        id: m['id'] as String,
        normalizedUrl: m['normalized_url'] as String,
        originalUrl: m['original_url'] as String,
        title: m['title'] as String,
        author: m['author'] as String,
        thumbPath: m['thumb_path'] as String,
        format: SaveFormat.values.byName(m['format'] as String),
        qualityLabel: m['quality_label'] as String,
        sizeBytes: (m['size_bytes'] as num).toInt(),
        fileUri: m['file_uri'] as String,
        savedAt: (m['saved_at'] as num).toInt(),
        durationMs: (m['duration_ms'] as num?)?.toInt(),
      );
}

/// Persistence seam for the download engine. sqflite-backed in the app,
/// in-memory in unit tests.
abstract class DownloadStore {
  Future<void> saveTask(StoredTask task);
  Future<void> updateTask(StoredTask task);
  Future<StoredTask?> getTask(String id);
  Future<List<StoredTask>> listTasks();
  Future<void> deleteTask(String id);

  Future<void> addHistory(SavedItem item);
  Future<SavedItem?> findByUrl(String normalizedUrl);
  Future<List<SavedItem>> listHistory({SaveFormat? format, int? limit});
  Future<void> deleteHistory(String id);
  Future<void> clearHistory();
  Future<int> historyCount();
}

/// Non-persistent [DownloadStore] for tests and previews.
class MemoryDownloadStore implements DownloadStore {
  final _tasks = <String, StoredTask>{};
  final _history = <String, SavedItem>{};

  @override
  Future<void> saveTask(StoredTask task) async => _tasks[task.id] = task;

  @override
  Future<void> updateTask(StoredTask task) async => _tasks[task.id] = task;

  @override
  Future<StoredTask?> getTask(String id) async => _tasks[id];

  @override
  Future<List<StoredTask>> listTasks() async => _tasks.values.toList()
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  @override
  Future<void> deleteTask(String id) async => _tasks.remove(id);

  @override
  Future<void> addHistory(SavedItem item) async => _history[item.id] = item;

  @override
  Future<SavedItem?> findByUrl(String normalizedUrl) async {
    for (final item in _history.values) {
      if (item.normalizedUrl == normalizedUrl) return item;
    }
    return null;
  }

  @override
  Future<List<SavedItem>> listHistory({SaveFormat? format, int? limit}) async {
    var items = _history.values.toList()
      ..sort((a, b) => b.savedAt.compareTo(a.savedAt));
    if (format != null) {
      items = items.where((i) => i.format == format).toList();
    }
    if (limit != null && items.length > limit) {
      items = items.sublist(0, limit);
    }
    return items;
  }

  @override
  Future<void> deleteHistory(String id) async => _history.remove(id);

  @override
  Future<void> clearHistory() async => _history.clear();

  @override
  Future<int> historyCount() async => _history.length;
}
