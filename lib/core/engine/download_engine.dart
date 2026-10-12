import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart';

import '../models/media.dart';
import '../utils/format.dart';
import 'download_store.dart';
import 'retry_policy.dart';
import 'segment_planner.dart';

/// Where a finished file goes in the public gallery.
enum MediaCollection { video, audio, image }

/// Places a merged download file into the public gallery (MediaStore on
/// Android). Returns the content URI string of the saved file.
abstract class FinishedFilePlacer {
  Future<String> place({
    required File file,
    required String displayName,
    required MediaCollection collection,
    required String subfolder,
  });
}

/// Controls the Android foreground service (type dataSync) that keeps
/// downloads alive when the app is closed.
abstract class ForegroundControl {
  Future<void> start(String id, String title);
  Future<void> update(
      String id, String title, double progress, String statusText,);
  Future<void> stop(String id);
  Future<void> notifySaved(String title, {required bool vibrate});
}

/// Generates a video thumbnail file. Null when unavailable.
abstract class Thumbnailer {
  Future<String?> videoThumbnail(String videoPath, String outPath);
}

/// Current network state, used for the Wi-Fi-only setting.
abstract class NetworkChecker {
  Future<bool> get isWifi;
}

/// Everything the engine needs to start one download.
class EnqueueRequest {
  EnqueueRequest({
    required this.originalUrl,
    required this.normalizedUrl,
    required this.title,
    required this.author,
    required this.thumbSource,
    required this.format,
    required this.qualityLabel,
    required this.stream,
    required this.fileName,
    required this.wifiOnly,
    required this.keepHistory,
    required this.notifyOnDone,
    required this.vibrateOnDone,
    required this.showProgressNotification,
    required this.subfolder,
    this.duration,
  });

  final String originalUrl;
  final String normalizedUrl;
  final String title;
  final String author;
  final String thumbSource;
  final SaveFormat format;
  final String qualityLabel;
  final MediaStream stream;
  final String fileName;
  final bool wifiOnly;
  final bool keepHistory;
  final bool notifyOnDone;
  final bool vibrateOnDone;
  final bool showProgressNotification;
  final String subfolder;
  final Duration? duration;
}

/// UI-facing snapshot of one task.
class TaskProgress {
  TaskProgress({
    required this.id,
    required this.title,
    required this.status,
    required this.bytesDone,
    required this.elapsedMs,
    this.totalBytes,
    this.speedBps,
    this.error,
    this.queuePosition = 0,
  });

  final String id;
  final String title;
  final TaskStatus status;
  final int bytesDone;
  final int? totalBytes;
  final double? speedBps;
  final String? error;
  final int queuePosition;
  final int elapsedMs;

  double? get fraction =>
      totalBytes == null || totalBytes! <= 0 ? null : bytesDone / totalBytes!;
}

class _PauseRequested implements Exception {}

class _CancelRequested implements Exception {}

class _NoRangeSupport implements Exception {}

class _Sample {
  _Sample(this.time, this.bytes);
  final DateTime time;
  final int bytes;
}

class _ActiveTask {
  _ActiveTask(this.task);

  StoredTask task;
  final tokens = <CancelToken>[];
  List<ByteRange> ranges = const [];
  List<int> segDone = const [];
  int? totalBytes;
  int bytesDone = 0;
  final stopwatch = Stopwatch();
  final samples = <_Sample>[];
  bool pauseRequested = false;
  bool cancelRequested = false;
  DateTime lastEmit = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime lastPersist = DateTime.fromMillisecondsSinceEpoch(0);
  late Directory partsDir;
  late String fileName;
  late SaveFormat format;
  late String thumbSource;
  late bool keepHistory;
  late bool notifyOnDone;
  late bool vibrateOnDone;
  late bool showProgressNotification;
  late String subfolder;
  late String originalUrl;
  late String normalizedUrl;
  late String qualityLabel;
  late String streamUrl;
  late String container;
  late Duration? duration;
}

/// Parallel, resumable download engine.
///
/// * Uses one shared [Dio] instance (connection reuse).
/// * Splits large files into up to 4 parallel HTTP Range segments when the
///   server supports it; otherwise streams in one piece.
/// * Queue with configurable max parallelism, retry with exponential
///   backoff (3 tries), pause/resume persisted so it survives restarts,
///   cancel cleans up partial files.
/// * All progress numbers are measured, never fabricated.
class DownloadEngine {
  DownloadEngine({
    required DownloadStore store,
    required Dio dio,
    required Directory workDir,
    required FinishedFilePlacer placer,
    required ForegroundControl foreground,
    required Thumbnailer thumbnailer,
    required NetworkChecker network,
    required int Function() maxParallel,
    Future<void> Function(Duration d)? sleep,
    Duration Function(int attempt)? backoffDelay,
  })  : _store = store,
        _dio = dio,
        _workDir = workDir,
        _placer = placer,
        _foreground = foreground,
        _thumbnailer = thumbnailer,
        _network = network,
        _maxParallel = maxParallel,
        _sleep = sleep ?? ((d) => Future.delayed(d)),
        _backoffDelay = backoffDelay ?? RetryPolicy.delayForAttempt;

  final DownloadStore _store;
  final Dio _dio;
  final Directory _workDir;
  final FinishedFilePlacer _placer;
  final ForegroundControl _foreground;
  final Thumbnailer _thumbnailer;
  final NetworkChecker _network;
  final int Function() _maxParallel;
  final Future<void> Function(Duration d) _sleep;
  final Duration Function(int attempt) _backoffDelay;

  final _active = <String, _ActiveTask>{};
  final _controllers = <String, StreamController<TaskProgress>>{};
  final _changed = StreamController<void>.broadcast();
  bool _pumping = false;
  bool _disposed = false;
  int _idCounter = 0;

  /// Coarse signal: task list changed (enqueue, status change, progress tick).
  /// UI list screens listen to this; per-task widgets use [watch].
  Stream<void> get changed => _changed.stream;

  /// Fine-grained progress for one task. Broadcast; closed when the task is
  /// removed.
  Stream<TaskProgress> watch(String id) {
    return _controllers
        .putIfAbsent(id, () => StreamController<TaskProgress>.broadcast())
        .stream;
  }

  /// Latest known snapshot for a task, or null if unknown.
  Future<TaskProgress?> snapshot(String id) async {
    final a = _active[id];
    if (a != null) return _progressOf(a);
    final t = await _store.getTask(id);
    if (t == null) return null;
    return TaskProgress(
      id: t.id,
      title: t.title,
      status: t.status,
      bytesDone: t.bytesDone,
      totalBytes: t.totalBytes,
      elapsedMs: t.elapsedMs,
      error: t.error,
    );
  }

  /// True when [normalizedUrl] already has a saved file (duplicate check).
  Future<bool> isDuplicate(String normalizedUrl) async =>
      (await _store.findByUrl(normalizedUrl)) != null;

  /// Latest persisted row for a task.
  Future<StoredTask?> getTask(String id) => _store.getTask(id);

  Future<String> enqueue(EnqueueRequest req) async {
    final id = 'dl_${DateTime.now().millisecondsSinceEpoch}_${_idCounter++}';
    final now = DateTime.now().millisecondsSinceEpoch;
    var status = TaskStatus.queued;
    if (req.wifiOnly && !(await _network.isWifi)) {
      status = TaskStatus.waitingForWifi;
    }
    final task = StoredTask(
      id: id,
      normalizedUrl: req.normalizedUrl,
      originalUrl: req.originalUrl,
      title: req.title,
      author: req.author,
      thumbSource: req.thumbSource,
      format: req.format,
      qualityLabel: req.qualityLabel,
      streamUrl: req.stream.url,
      container: req.stream.container,
      status: status,
      bytesDone: 0,
      createdAt: now,
      updatedAt: now,
      durationMs: req.duration?.inMilliseconds,
      totalBytes: req.stream.sizeBytes,
    );
    await _store.saveTask(task);
    // Stash request-scoped fields on the in-memory worker when it starts.
    _pendingRequests[id] = req;
    _emitChanged();
    unawaited(_pump());
    return id;
  }

  final _pendingRequests = <String, EnqueueRequest>{};

  Future<void> pause(String id) async {
    final a = _active[id];
    if (a != null) {
      a.pauseRequested = true;
      for (final t in a.tokens.toList()) {
        if (!t.isCancelled) t.cancel('paused');
      }
      return;
    }
    final t = await _store.getTask(id);
    if (t == null) return;
    if (t.status == TaskStatus.queued ||
        t.status == TaskStatus.waitingForWifi) {
      await _store.updateTask(
          t.copyWith(status: TaskStatus.paused, updatedAt: _now()),);
      _emitChanged();
    }
  }

  Future<void> resume(String id) async {
    final t = await _store.getTask(id);
    if (t == null || _active.containsKey(id)) return;
    if (t.status == TaskStatus.paused ||
        t.status == TaskStatus.failed ||
        t.status == TaskStatus.waitingForWifi) {
      var status = TaskStatus.queued;
      if ((await _currentWifiOnly()) && !(await _network.isWifi)) {
        status = TaskStatus.waitingForWifi;
      }
      await _store.updateTask(
          t.copyWith(status: status, error: null, updatedAt: _now()),);
      _emitChanged();
      unawaited(_pump());
    }
  }

  /// Failed tasks resume from their persisted segment progress.
  Future<void> retry(String id) => resume(id);

  Future<void> cancel(String id) async {
    final a = _active[id];
    if (a != null) {
      a.cancelRequested = true;
      for (final t in a.tokens.toList()) {
        if (!t.isCancelled) t.cancel('canceled');
      }
      return;
    }
    await _store.deleteTask(id);
    _pendingRequests.remove(id);
    _emitChanged();
  }

  /// Call when the app starts: tasks interrupted by a process kill come back
  /// as paused so the user can resume them explicitly.
  Future<void> restore() async {
    final tasks = await _store.listTasks();
    for (final t in tasks) {
      if (t.status == TaskStatus.downloading ||
          t.status == TaskStatus.queued) {
        await _store.updateTask(
            t.copyWith(status: TaskStatus.paused, updatedAt: _now()),);
      }
    }
    _emitChanged();
  }

  /// Re-evaluates tasks waiting for Wi-Fi (call on resume / setting change).
  Future<void> recheckNetwork() async {
    final wifiOnly = await _currentWifiOnly();
    final onWifi = await _network.isWifi;
    final tasks = await _store.listTasks();
    var changed = false;
    for (final t in tasks) {
      if (t.status == TaskStatus.waitingForWifi && (!wifiOnly || onWifi)) {
        await _store.updateTask(
            t.copyWith(status: TaskStatus.queued, updatedAt: _now()),);
        changed = true;
      }
    }
    if (changed) {
      _emitChanged();
      unawaited(_pump());
    }
  }

  // Subclasses/tests override to expose the live Wi-Fi-only setting.
  Future<bool> _currentWifiOnly() async => _wifiOnlyProvider == null
      ? false
      : await _wifiOnlyProvider!();
  Future<bool> Function()? _wifiOnlyProvider;

  /// Wires the live Wi-Fi-only setting (called by the app bootstrap).
  void bindWifiOnly(Future<bool> Function() provider) {
    _wifiOnlyProvider = provider;
  }

  Future<void> dispose() async {
    _disposed = true;
    for (final a in _active.values) {
      a.cancelRequested = true;
      for (final t in a.tokens) {
        if (!t.isCancelled) t.cancel('disposed');
      }
    }
    await _changed.close();
    for (final c in _controllers.values) {
      await c.close();
    }
  }

  // ---------------------------------------------------------------- pump

  Future<void> _pump() async {
    if (_disposed || _pumping) return;
    _pumping = true;
    try {
      while (_active.length < _maxParallel()) {
        final tasks = await _store.listTasks();
        StoredTask? next;
        for (final t in tasks) {
          if (t.status == TaskStatus.queued && !_active.containsKey(t.id)) {
            next = t;
            break;
          }
        }
        if (next == null) break;
        _start(next);
      }
    } finally {
      _pumping = false;
    }
  }

  void _start(StoredTask task) {
    final req = _pendingRequests.remove(task.id);
    final a = _ActiveTask(task)
      ..partsDir = Directory('${_workDir.path}/parts/${task.id}')
      ..fileName = req?.fileName ?? 'zipclip_${task.id}'
      ..format = req?.format ?? task.format
      ..thumbSource = req?.thumbSource ?? task.thumbSource
      ..keepHistory = req?.keepHistory ?? true
      ..notifyOnDone = req?.notifyOnDone ?? true
      ..vibrateOnDone = req?.vibrateOnDone ?? true
      ..showProgressNotification = req?.showProgressNotification ?? true
      ..subfolder = req?.subfolder ?? 'ZipClip'
      ..originalUrl = req?.originalUrl ?? task.originalUrl
      ..normalizedUrl = req?.normalizedUrl ?? task.normalizedUrl
      ..qualityLabel = req?.qualityLabel ?? task.qualityLabel
      ..streamUrl = task.streamUrl
      ..container = task.container
      ..duration = req?.duration;
    _active[task.id] = a;
    unawaited(_runTask(a));
  }

  // ---------------------------------------------------------------- run

  Future<void> _runTask(_ActiveTask a) async {
    final id = a.task.id;
    try {
      await a.partsDir.create(recursive: true);
      a.stopwatch.start();
      await _foreground.start(id, a.task.title);
      _throwIfStopped(a);

      // Probe: does the server support Range, and how big is the file?
      final probe = await _probe(a.streamUrl);
      _throwIfStopped(a);
      final total = probe.totalBytes ?? a.task.totalBytes;
      List<ByteRange> ranges;
      if (probe.rangeSupported && total != null && total > 0) {
        ranges = SegmentPlanner.plan(totalBytes: total);
      } else {
        ranges = const [ByteRange(0, -1)];
      }
      a.ranges = ranges;
      a.totalBytes = total;
      a.segDone = List<int>.filled(ranges.length, 0);
      a.bytesDone = 0;
      _restoreProgress(a);
      // Clamp restored progress to what is actually on disk: part files may
      // be missing/short after a crash or an OS cleanup.
      for (var i = 0; i < a.ranges.length; i++) {
        final part = File('${a.partsDir.path}/part_$i.tmp');
        final onDisk = await part.exists() ? await part.length() : 0;
        if (onDisk < a.segDone[i]) a.segDone[i] = onDisk;
      }
      a.bytesDone = a.segDone.fold(0, (sum, n) => sum + n);

      await _store.updateTask(a.task.copyWith(
        status: TaskStatus.downloading,
        totalBytes: total,
        segmentsJson: _segmentsJson(a),
        updatedAt: _now(),
      ),);
      a.task = (await _store.getTask(id))!;
      _emitProgress(a);

      try {
        await Future.wait(
            [for (var i = 0; i < ranges.length; i++) _downloadSegment(a, i)],);
      } on _NoRangeSupport {
        // Server lied on HEAD; redo as one plain stream.
        a.ranges = const [ByteRange(0, -1)];
        a.segDone = [0];
        a.bytesDone = 0;
        await _clearParts(a);
        await a.partsDir.create(recursive: true);
        await _downloadSegment(a, 0);
      }
      _throwIfStopped(a);

      final merged = await _merge(a);
      _throwIfStopped(a);

      final thumbPath = await _makeThumbnail(a, merged);
      final ext = a.format == SaveFormat.cover ? 'jpg' : a.container;
      final collection = switch (a.format) {
        SaveFormat.video => MediaCollection.video,
        SaveFormat.audio => MediaCollection.audio,
        SaveFormat.cover => MediaCollection.image,
      };
      final uri = await _placer.place(
        file: merged,
        displayName: '${a.fileName}.$ext',
        collection: collection,
        subfolder: a.subfolder,
      );
      final sizeBytes = await merged.length();

      if (a.keepHistory) {
        await _store.addHistory(SavedItem(
          id: id,
          normalizedUrl: a.normalizedUrl,
          originalUrl: a.originalUrl,
          title: a.task.title,
          author: a.task.author,
          thumbPath: thumbPath ?? a.thumbSource,
          format: a.format,
          qualityLabel: a.qualityLabel,
          sizeBytes: sizeBytes,
          fileUri: uri,
          savedAt: _now(),
          durationMs: a.task.durationMs,
        ),);
      }

      a.stopwatch.stop();
      await _store.updateTask(a.task.copyWith(
        status: TaskStatus.completed,
        bytesDone: sizeBytes,
        totalBytes: sizeBytes,
        fileUri: uri,
        elapsedMs: a.stopwatch.elapsedMilliseconds,
        updatedAt: _now(),
      ),);
      a.task = (await _store.getTask(id))!;
      _emitProgress(a);
      await _foreground.stop(id);
      if (a.notifyOnDone) {
        await _foreground.notifySaved(a.task.title,
            vibrate: a.vibrateOnDone,);
      }
      await _clearParts(a);
    } on _PauseRequested {
      a.stopwatch.stop();
      await _persistProgress(a);
      final t = await _store.getTask(id);
      if (t != null) {
        await _store.updateTask(t.copyWith(
          status: TaskStatus.paused,
          bytesDone: a.bytesDone,
          segmentsJson: _segmentsJson(a),
          elapsedMs: a.stopwatch.elapsedMilliseconds,
          updatedAt: _now(),
        ),);
        a.task = (await _store.getTask(id))!;
        _emitProgress(a);
      }
      await _foreground.stop(id);
    } on _CancelRequested {
      await _clearParts(a);
      await _store.deleteTask(id);
      await _foreground.stop(id);
      _controllers[id]?.add(TaskProgress(
        id: id,
        title: a.task.title,
        status: TaskStatus.canceled,
        bytesDone: 0,
        elapsedMs: 0,
      ),);
    } catch (e) {
      a.stopwatch.stop();
      await _persistProgress(a);
      final t = await _store.getTask(id);
      if (t != null) {
        await _store.updateTask(t.copyWith(
          status: TaskStatus.failed,
          bytesDone: a.bytesDone,
          segmentsJson: _segmentsJson(a),
          error: _friendlyError(e),
          elapsedMs: a.stopwatch.elapsedMilliseconds,
          updatedAt: _now(),
        ),);
        a.task = (await _store.getTask(id))!;
        _emitProgress(a);
      }
      await _foreground.stop(id);
    } finally {
      _active.remove(id);
      _pendingRequests.remove(id);
      _emitChanged();
      unawaited(_pump());
    }
  }

  // ------------------------------------------------------------- segments

  Future<({bool rangeSupported, int? totalBytes})> _probe(String url) async {
    try {
      final res = await _dio.head(
        url,
        options: Options(
          sendTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 15),
        ),
      );
      final acceptRanges =
          (res.headers.value('accept-ranges') ?? '').toLowerCase();
      final total =
          int.tryParse(res.headers.value('content-length') ?? '');
      return (
        rangeSupported: acceptRanges == 'bytes',
        totalBytes: total,
      );
    } on DioException {
      return (rangeSupported: false, totalBytes: null);
    }
  }

  Future<void> _downloadSegment(_ActiveTask a, int index) async {
    final range = a.ranges[index];
    final ranged = range.end >= 0;
    var attempt = 0;
    while (true) {
      attempt++;
      _throwIfStopped(a);
      final token = CancelToken();
      a.tokens.add(token);
      try {
        final start = range.start + a.segDone[index];
        final headers = <String, String>{};
        if (ranged) headers['Range'] = 'bytes=$start-${range.end}';
        final res = await _dio.get<ResponseBody>(
          a.streamUrl,
          options: Options(
            responseType: ResponseType.stream,
            headers: headers,
            // Per-segment timeouts; the whole task has no artificial limit.
            sendTimeout: const Duration(seconds: 30),
            receiveTimeout: const Duration(seconds: 30),
          ),
          cancelToken: token,
        );
        if (ranged && (res.statusCode ?? 200) != 206) {
          throw _NoRangeSupport();
        }
        final part = File('${a.partsDir.path}/part_$index.tmp');
        final raf = await part.open(mode: FileMode.writeOnlyAppend);
        var finished = false;
        try {
          // Clamp any stale tail left by a previous crashed session.
          if (await part.length() > a.segDone[index]) {
            await raf.truncate(a.segDone[index]);
          }
          await for (final chunk in res.data!.stream) {
            _throwIfStopped(a);
            raf.writeFromSync(chunk);
            a.segDone[index] += chunk.length;
            _onChunk(a, chunk.length);
          }
          finished = true;
        } finally {
          await raf.close();
          if (!finished) {
            // Bailed out early (pause/cancel/error): release the
            // connection. After a full read the stream is done, and
            // drain() would throw, so only do this when unfinished.
            try {
              await res.data?.stream.drain<void>();
            } catch (_) {}
          }
        }
        return;
      } on _NoRangeSupport {
        rethrow;
      } on _PauseRequested {
        rethrow;
      } on _CancelRequested {
        rethrow;
      } on DioException catch (e) {
        if (e.type == DioExceptionType.cancel || _stopped(a)) {
          _throwIfStopped(a);
        }
        if (RetryPolicy.shouldRetry(attempt)) {
          await _interruptibleSleep(_backoffDelay(attempt), a);
          continue;
        }
        rethrow;
      } finally {
        a.tokens.remove(token);
      }
    }
  }

  Future<File> _merge(_ActiveTask a) async {
    final out = File('${a.partsDir.path}/merged.tmp');
    if (await out.exists()) await out.delete();
    final sink = out.openWrite();
    try {
      for (var i = 0; i < a.ranges.length; i++) {
        final part = File('${a.partsDir.path}/part_$i.tmp');
        await sink.addStream(part.openRead());
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
    return out;
  }

  Future<String?> _makeThumbnail(_ActiveTask a, File merged) async {
    try {
      final outPath =
          '${_workDir.path}/thumbs/${a.task.id}.jpg';
      await Directory('${_workDir.path}/thumbs').create(recursive: true);
      switch (a.format) {
        case SaveFormat.video:
          return await _thumbnailer.videoThumbnail(merged.path, outPath);
        case SaveFormat.audio:
          return await _fetchThumbFile(a.thumbSource, outPath);
        case SaveFormat.cover:
          // The cover image itself is the thumbnail; placed below.
          await merged.copy(outPath);
          return outPath;
      }
    } catch (_) {
      return null;
    }
  }

  /// Downloads an http(s) thumbnail, or passes through asset:// references.
  Future<String?> _fetchThumbFile(String source, String outPath) async {
    if (source.startsWith('asset://')) return source;
    if (!source.startsWith('http')) return null;
    final res = await _dio.get<List<int>>(
      source,
      options: Options(responseType: ResponseType.bytes),
    );
    final bytes = res.data;
    if (bytes == null || bytes.isEmpty) return null;
    await File(outPath).writeAsBytes(bytes);
    return outPath;
  }

  // -------------------------------------------------------------- helpers

  void _throwIfStopped(_ActiveTask a) {
    if (a.cancelRequested) throw _CancelRequested();
    if (a.pauseRequested) throw _PauseRequested();
  }

  bool _stopped(_ActiveTask a) => a.cancelRequested || a.pauseRequested;

  Future<void> _interruptibleSleep(Duration d, _ActiveTask a) async {
    final end = DateTime.now().add(d);
    while (DateTime.now().isBefore(end)) {
      _throwIfStopped(a);
      final remaining = end.difference(DateTime.now());
      await _sleep(remaining < const Duration(milliseconds: 200)
          ? remaining
          : const Duration(milliseconds: 200),);
    }
  }

  void _onChunk(_ActiveTask a, int n) {
    a.bytesDone += n;
    final now = DateTime.now();
    a.samples.add(_Sample(now, a.bytesDone));
    final cutoff = now.subtract(const Duration(milliseconds: 2500));
    while (a.samples.length > 2 && a.samples.first.time.isBefore(cutoff)) {
      a.samples.removeAt(0);
    }
    if (now.difference(a.lastEmit) >= const Duration(milliseconds: 250)) {
      a.lastEmit = now;
      _emitProgress(a);
      if (a.showProgressNotification) {
        unawaited(_foreground.update(
            a.task.id, a.task.title, _fraction(a), _statusText(a),),);
      }
    }
    if (now.difference(a.lastPersist) >= const Duration(seconds: 2)) {
      a.lastPersist = now;
      unawaited(_persistProgress(a));
    }
  }

  double? _speed(_ActiveTask a) {
    if (a.samples.length < 2) return null;
    final first = a.samples.first;
    final last = a.samples.last;
    final dt = last.time.difference(first.time).inMicroseconds / 1e6;
    if (dt < 0.4) return null;
    final bps = (last.bytes - first.bytes) / dt;
    return bps > 0 ? bps : null;
  }

  double _fraction(_ActiveTask a) {
    final total = a.totalBytes;
    if (total == null || total <= 0) return 0;
    return min(1.0, a.bytesDone / total);
  }

  String _statusText(_ActiveTask a) {
    final total = a.totalBytes;
    final done = ZipFormat.bytes(a.bytesDone);
    final totalStr = ZipFormat.bytes(total);
    final speed = ZipFormat.speed(_speed(a));
    return '$done of $totalStr · $speed';
  }

  TaskProgress _progressOf(_ActiveTask a) => TaskProgress(
        id: a.task.id,
        title: a.task.title,
        status: a.task.status,
        bytesDone: a.bytesDone,
        totalBytes: a.totalBytes,
        speedBps: _speed(a),
        error: a.task.error,
        elapsedMs: a.stopwatch.elapsedMilliseconds,
      );

  void _emitProgress(_ActiveTask a) {
    _controllers[a.task.id]?.add(_progressOf(a));
    _emitChanged();
  }

  void _emitChanged() {
    if (!_disposed && !_changed.isClosed) _changed.add(null);
  }

  Future<void> _persistProgress(_ActiveTask a) async {
    final t = await _store.getTask(a.task.id);
    if (t == null) return;
    await _store.updateTask(t.copyWith(
      bytesDone: a.bytesDone,
      totalBytes: a.totalBytes,
      segmentsJson: _segmentsJson(a),
      updatedAt: _now(),
    ),);
  }

  String _segmentsJson(_ActiveTask a) => jsonEncode({
        'ranges': [for (final r in a.ranges) r.toJson()],
        'done': a.segDone,
      });

  void _restoreProgress(_ActiveTask a) {
    final raw = a.task.segmentsJson;
    if (raw == null) return;
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      final ranges = (m['ranges'] as List)
          .map((e) => ByteRange.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      final done =
          (m['done'] as List).map((e) => (e as num).toInt()).toList();
      if (ranges.length == a.ranges.length && done.length == a.segDone.length) {
        var match = true;
        for (var i = 0; i < ranges.length; i++) {
          if (ranges[i].start != a.ranges[i].start ||
              ranges[i].end != a.ranges[i].end) {
            match = false;
            break;
          }
        }
        if (match) {
          a.segDone = done;
          a.bytesDone = done.fold(0, (p, e) => p + e);
        }
      }
    } catch (_) {
      // Corrupt progress: start fresh.
    }
  }

  Future<void> _clearParts(_ActiveTask a) async {
    try {
      if (await a.partsDir.exists()) {
        await a.partsDir.delete(recursive: true);
      }
    } catch (_) {}
  }

  String _friendlyError(Object e) {
    if (e is DioException) {
      switch (e.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
          return 'Connection timed out. Check your connection and retry.';
        case DioExceptionType.connectionError:
          return "Couldn't reach the server. Check your connection and retry.";
        case DioExceptionType.badResponse:
          final code = e.response?.statusCode;
          if (code == 403 || code == 401) {
            return 'The server refused access (only public videos are supported).';
          }
          if (code == 404) return 'The video was not found (it may be deleted).';
          return 'Server error ($code). Retry in a bit.';
        default:
          return 'Download failed. Retry in a bit.';
      }
    }
    return 'Download failed: $e';
  }

  int _now() => DateTime.now().millisecondsSinceEpoch;
}
