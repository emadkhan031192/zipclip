import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zipclip/core/engine/download_engine.dart';
import 'package:zipclip/core/engine/download_store.dart';
import 'package:zipclip/core/models/media.dart';

// ------------------------------------------------------------------- fakes

class _FakePlacer implements FinishedFilePlacer {
  _FakePlacer(this.dir);
  final Directory dir;

  @override
  Future<String> place({
    required File file,
    required String displayName,
    required MediaCollection collection,
    required String subfolder,
  }) async {
    final out = File('${dir.path}/$displayName');
    await file.copy(out.path);
    return out.uri.toString();
  }
}

class _FakeForeground implements ForegroundControl {
  final calls = <String>[];
  @override
  Future<void> start(String id, String title) async =>
      calls.add('start $id');
  @override
  Future<void> update(
          String id, String title, double progress, String statusText,) async {}
  @override
  Future<void> stop(String id) async => calls.add('stop $id');
  @override
  Future<void> notifySaved(String title, {required bool vibrate}) async =>
      calls.add('saved');
}

class _FakeThumbnailer implements Thumbnailer {
  @override
  Future<String?> videoThumbnail(String videoPath, String outPath) async =>
      null;
}

class _FakeNetwork implements NetworkChecker {
  _FakeNetwork(this.wifi);
  final bool wifi;
  @override
  Future<bool> get isWifi async => wifi;
}

// ------------------------------------------------------------- test server

/// Local HTTP server with real Range support, optional failure injection
/// and drip-feed throttling.
class _RangeServer {
  _RangeServer._(this.server, this.bytes);

  final HttpServer server;
  final Uint8List bytes;

  String get url => 'http://127.0.0.1:${server.port}/video.mp4';

  static Future<_RangeServer> start(
    Uint8List bytes, {
    int failGets = 0,
    Duration? drip,
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var getFailures = 0;
    server.listen((HttpRequest req) async {
      try {
        if (req.method == 'HEAD') {
          req.response.headers.set('accept-ranges', 'bytes');
          req.response.headers.set('content-length', '${bytes.length}');
          await req.response.close();
          return;
        }
        if (req.method == 'GET' && getFailures < failGets) {
          getFailures++;
          req.response.statusCode = HttpStatus.internalServerError;
          await req.response.close();
          return;
        }
        final rangeHeader = req.headers.value('range');
        var start = 0;
        var end = bytes.length - 1;
        if (rangeHeader != null) {
          final m = RegExp(r'bytes=(\d+)-(\d*)').firstMatch(rangeHeader);
          if (m != null) {
            start = int.parse(m.group(1)!);
            final endStr = m.group(2)!;
            end = endStr.isEmpty ? bytes.length - 1 : int.parse(endStr);
            req.response.statusCode = HttpStatus.partialContent;
            req.response.headers
                .set('content-range', 'bytes $start-$end/${bytes.length}');
          }
        }
        req.response.headers.set('accept-ranges', 'bytes');
        req.response.headers.set('content-length', '${end - start + 1}');
        const chunk = 65536;
        for (var i = start; i <= end; i += chunk) {
          final j = min(i + chunk, end + 1);
          req.response.add(bytes.sublist(i, j));
          if (drip != null) await Future.delayed(drip);
        }
        await req.response.close();
      } catch (_) {
        // Client went away (pause/cancel): ignore.
        try {
          await req.response.close();
        } catch (_) {}
      }
    });
    return _RangeServer._(server, bytes);
  }

  Future<void> stop() => server.close(force: true);
}

// ----------------------------------------------------------------- helpers

DownloadEngine _makeEngine({
  required DownloadStore store,
  required Directory workDir,
  required Directory outDir,
  int maxParallel = 2,
  bool wifi = true,
}) =>
    DownloadEngine(
      store: store,
      dio: Dio(),
      workDir: workDir,
      placer: _FakePlacer(outDir),
      foreground: _FakeForeground(),
      thumbnailer: _FakeThumbnailer(),
      network: _FakeNetwork(wifi),
      maxParallel: () => maxParallel,
      backoffDelay: (_) => const Duration(milliseconds: 10),
    );

EnqueueRequest _request(
  String url, {
  int? sizeBytes,
  bool keepHistory = true,
  bool wifiOnly = false,
  String fileName = 'test_clip',
}) =>
    EnqueueRequest(
      originalUrl: url,
      normalizedUrl: url,
      title: 'Test clip',
      author: '@tester',
      thumbSource: 'asset://sample_thumb',
      format: SaveFormat.video,
      qualityLabel: '720p',
      stream: MediaStream(
        id: 't',
        label: '720p',
        url: url,
        container: 'mp4',
        hasVideo: true,
        hasAudio: true,
        watermarkFree: true,
        sizeBytes: sizeBytes,
      ),
      fileName: fileName,
      wifiOnly: wifiOnly,
      keepHistory: keepHistory,
      notifyOnDone: true,
      vibrateOnDone: false,
      showProgressNotification: true,
      subfolder: 'ZipClip',
      duration: const Duration(seconds: 10),
    );

/// Race-free terminal-state waiter (polls the store).
Future<StoredTask> _awaitStatus(
  DownloadEngine engine,
  String id,
  TaskStatus status, {
  Duration timeout = const Duration(seconds: 60),
}) async {
  final sw = Stopwatch()..start();
  while (sw.elapsed < timeout) {
    final t = await engine.getTask(id);
    if (t?.status == status) return t!;
    await Future.delayed(const Duration(milliseconds: 100));
  }
  throw TimeoutException('task $id did not reach $status in $timeout');
}

Uint8List _bytes(int size) =>
    Uint8List.fromList(List.generate(size, (i) => i % 251));

// ------------------------------------------------------------------- tests

void main() {
  group('DownloadEngine', () {
    late Directory workDir;
    late Directory outDir;

    setUp(() async {
      workDir = await Directory.systemTemp.createTemp('zc_work');
      outDir = await Directory.systemTemp.createTemp('zc_out');
    });

    tearDown(() async {
      if (await workDir.exists()) await workDir.delete(recursive: true);
      if (await outDir.exists()) await outDir.delete(recursive: true);
    });

    test('downloads a large file in parallel segments, byte-identical',
        () async {
      final bytes = _bytes(8 * 1024 * 1024); // -> 4 segments
      final server = await _RangeServer.start(bytes);
      final engine = _makeEngine(
        store: MemoryDownloadStore(),
        workDir: workDir,
        outDir: outDir,
      );
      addTearDown(() async {
        await engine.dispose();
        await server.stop();
      });

      final id =
          await engine.enqueue(_request(server.url, sizeBytes: bytes.length));
      final task = await _awaitStatus(engine, id, TaskStatus.completed);

      expect(task.bytesDone, bytes.length);
      expect(task.totalBytes, bytes.length);
      expect(task.elapsedMs, greaterThan(0)); // real measured time
      expect(task.fileUri, isNotNull);
      final saved = await File.fromUri(Uri.parse(task.fileUri!)).readAsBytes();
      expect(saved, bytes); // merge produced the exact original
      // Duplicate detection now knows this URL.
      expect(await engine.isDuplicate(server.url), isTrue);
    });

    test('pause and resume continue from persisted segment progress',
        () async {
      final bytes = _bytes(4 * 1024 * 1024);
      final server = await _RangeServer.start(
        bytes,
        drip: const Duration(milliseconds: 20),
      );
      final store = MemoryDownloadStore();
      final engine = _makeEngine(
        store: store,
        workDir: workDir,
        outDir: outDir,
      );
      addTearDown(() async {
        await engine.dispose();
        await server.stop();
      });

      final id =
          await engine.enqueue(_request(server.url, sizeBytes: bytes.length));

      // Wait until some bytes have landed, then pause mid-flight.
      final sw = Stopwatch()..start();
      StoredTask? snap;
      while (sw.elapsed < const Duration(seconds: 15)) {
        snap = await engine.getTask(id);
        if (snap != null && snap.bytesDone > 0) break;
        await Future.delayed(const Duration(milliseconds: 50));
      }
      expect(snap!.bytesDone, greaterThan(0));

      await engine.pause(id);
      final paused = await _awaitStatus(engine, id, TaskStatus.paused);
      expect(paused.bytesDone, lessThan(bytes.length));
      expect(paused.segmentsJson, isNotNull); // progress persisted

      await engine.resume(id);
      final done = await _awaitStatus(engine, id, TaskStatus.completed);
      final saved = await File.fromUri(Uri.parse(done.fileUri!)).readAsBytes();
      expect(saved, bytes);
    });

    test('cancel removes the task and cleans up partial files', () async {
      final bytes = _bytes(8 * 1024 * 1024);
      final server = await _RangeServer.start(
        bytes,
        drip: const Duration(milliseconds: 30),
      );
      final engine = _makeEngine(
        store: MemoryDownloadStore(),
        workDir: workDir,
        outDir: outDir,
      );
      addTearDown(() async {
        await engine.dispose();
        await server.stop();
      });

      final id =
          await engine.enqueue(_request(server.url, sizeBytes: bytes.length));
      final sw = Stopwatch()..start();
      while (sw.elapsed < const Duration(seconds: 15)) {
        final t = await engine.getTask(id);
        if (t != null && t.bytesDone > 0) break;
        await Future.delayed(const Duration(milliseconds: 50));
      }

      await engine.cancel(id);
      final sw2 = Stopwatch()..start();
      while (sw2.elapsed < const Duration(seconds: 10)) {
        if (await engine.getTask(id) == null) break;
        await Future.delayed(const Duration(milliseconds: 50));
      }
      expect(await engine.getTask(id), isNull);
      expect(
        await Directory('${workDir.path}/parts/$id').exists(),
        isFalse,
      );
    });

    test('retries failed segments with backoff, then succeeds', () async {
      final bytes = _bytes(8 * 1024 * 1024);
      // First 4 segment GETs fail with 500; every segment then succeeds on
      // its second attempt.
      final server = await _RangeServer.start(bytes, failGets: 4);
      final engine = _makeEngine(
        store: MemoryDownloadStore(),
        workDir: workDir,
        outDir: outDir,
      );
      addTearDown(() async {
        await engine.dispose();
        await server.stop();
      });

      final id =
          await engine.enqueue(_request(server.url, sizeBytes: bytes.length));
      final done = await _awaitStatus(engine, id, TaskStatus.completed);
      final saved = await File.fromUri(Uri.parse(done.fileUri!)).readAsBytes();
      expect(saved, bytes);
    });

    test('permanent failure marks the task failed with a message', () async {
      final bytes = _bytes(1024 * 1024);
      final server = await _RangeServer.start(bytes, failGets: 1000000);
      final engine = _makeEngine(
        store: MemoryDownloadStore(),
        workDir: workDir,
        outDir: outDir,
      );
      addTearDown(() async {
        await engine.dispose();
        await server.stop();
      });

      final id =
          await engine.enqueue(_request(server.url, sizeBytes: bytes.length));
      final failed = await _awaitStatus(engine, id, TaskStatus.failed);
      expect(failed.error, isNotNull);
      expect(failed.error, isNotEmpty);
      // Retry re-queues the failed task.
      await engine.retry(id);
      final requeued = await engine.getTask(id);
      expect(requeued?.status, TaskStatus.queued);
    });

    test('emits monotonic progress', () async {
      final bytes = _bytes(4 * 1024 * 1024);
      final server = await _RangeServer.start(bytes);
      final engine = _makeEngine(
        store: MemoryDownloadStore(),
        workDir: workDir,
        outDir: outDir,
      );
      addTearDown(() async {
        await engine.dispose();
        await server.stop();
      });

      final id =
          await engine.enqueue(_request(server.url, sizeBytes: bytes.length));
      final seen = <int>[];
      final sub = engine.watch(id).listen((p) => seen.add(p.bytesDone));
      await _awaitStatus(engine, id, TaskStatus.completed);
      await sub.cancel();

      expect(seen, isNotEmpty);
      for (var i = 1; i < seen.length; i++) {
        expect(seen[i], greaterThanOrEqualTo(seen[i - 1]));
      }
    });

    test('respects max parallel downloads', () async {
      final bytes = _bytes(2 * 1024 * 1024);
      final server = await _RangeServer.start(
        bytes,
        drip: const Duration(milliseconds: 40),
      );
      final engine = _makeEngine(
        store: MemoryDownloadStore(),
        workDir: workDir,
        outDir: outDir,
        maxParallel: 1,
      );
      addTearDown(() async {
        await engine.dispose();
        await server.stop();
      });

      final id1 = await engine.enqueue(
          _request(server.url, sizeBytes: bytes.length, fileName: 'clip_a'),);
      final id2 = await engine.enqueue(
          _request(server.url, sizeBytes: bytes.length, fileName: 'clip_b'),);

      // Sample the number of simultaneously downloading tasks.
      var maxSeen = 0;
      final sw = Stopwatch()..start();
      while (sw.elapsed < const Duration(seconds: 3)) {
        var downloading = 0;
        for (final id in [id1, id2]) {
          final t = await engine.getTask(id);
          if (t?.status == TaskStatus.downloading) downloading++;
        }
        maxSeen = max(maxSeen, downloading);
        await Future.delayed(const Duration(milliseconds: 50));
      }
      expect(maxSeen, lessThanOrEqualTo(1));

      await _awaitStatus(engine, id1, TaskStatus.completed);
      await _awaitStatus(engine, id2, TaskStatus.completed);
    });

    test('wifi-only holds tasks until on wifi', () async {
      final bytes = _bytes(512 * 1024);
      final server = await _RangeServer.start(bytes);
      final engine = _makeEngine(
        store: MemoryDownloadStore(),
        workDir: workDir,
        outDir: outDir,
        wifi: false,
      );
      addTearDown(() async {
        await engine.dispose();
        await server.stop();
      });

      final id = await engine.enqueue(
        _request(server.url, sizeBytes: bytes.length, wifiOnly: true),
      );
      await Future.delayed(const Duration(milliseconds: 500));
      final held = await engine.getTask(id);
      expect(held?.status, TaskStatus.waitingForWifi);
    });
  });
}
