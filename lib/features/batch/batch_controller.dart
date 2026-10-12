import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/engine/download_engine.dart';
import '../../core/engine/file_naming.dart';
import '../../core/models/media.dart';
import '../../core/resolver/link_resolver.dart';
import '../../core/storage/settings.dart';
import '../../core/utils/batch_parser.dart';
import '../../core/utils/pool.dart';
import '../../providers/bootstrap.dart';

enum BatchLinkStatus {
  pending,
  resolving,
  ready,
  duplicate,
  notSupported,
  failed,
}

class BatchLinkState {
  const BatchLinkState({
    required this.link,
    required this.status,
    this.media,
    this.sizeBytes,
    this.qualityLabel,
    this.message,
  });

  final BatchLink link;
  final BatchLinkStatus status;
  final ResolvedMedia? media;
  final int? sizeBytes;
  final String? qualityLabel;
  final String? message;

  BatchLinkState copyWith({
    BatchLinkStatus? status,
    ResolvedMedia? media,
    int? sizeBytes,
    String? qualityLabel,
    String? message,
  }) =>
      BatchLinkState(
        link: link,
        status: status ?? this.status,
        media: media ?? this.media,
        sizeBytes: sizeBytes ?? this.sizeBytes,
        qualityLabel: qualityLabel ?? this.qualityLabel,
        message: message ?? this.message,
      );
}

class BatchState {
  const BatchState({
    required this.text,
    required this.links,
    required this.skipDuplicates,
    required this.enqueuing,
  });

  final String text;
  final List<BatchLinkState> links;
  final bool skipDuplicates;
  final bool enqueuing;

  int get readyCount =>
      links.where((l) => l.status == BatchLinkStatus.ready).length;

  int get totalBytes => links
      .where((l) => l.status == BatchLinkStatus.ready)
      .fold(0, (sum, l) => sum + (l.sizeBytes ?? 0));

  bool get resolving =>
      links.any((l) => l.status == BatchLinkStatus.resolving);
}

final batchControllerProvider =
    NotifierProvider<BatchController, BatchState>(BatchController.new);

class BatchController extends Notifier<BatchState> {
  Timer? _debounce;
  int _resolveGen = 0;

  @override
  BatchState build() {
    ref.onDispose(() => _debounce?.cancel());
    return const BatchState(
      text: '',
      links: [],
      skipDuplicates: true,
      enqueuing: false,
    );
  }

  void setText(String text) {
    final parsed = BatchParser.parse(text);
    // Preserve already-resolved states for links that are still present.
    final prev = {for (final l in state.links) l.link.normalized: l};
    final links = [
      for (final link in parsed)
        prev[link.normalized] ??
            BatchLinkState(link: link, status: BatchLinkStatus.pending),
    ];
    state = BatchState(
      text: text,
      links: links,
      skipDuplicates: state.skipDuplicates,
      enqueuing: state.enqueuing,
    );
    _scheduleResolve();
  }

  void setSkipDuplicates(bool value) {
    state = BatchState(
      text: state.text,
      links: state.links,
      skipDuplicates: value,
      enqueuing: state.enqueuing,
    );
    // Re-evaluate duplicates immediately.
    _scheduleResolve();
  }

  void clear() {
    _debounce?.cancel();
    _resolveGen++;
    state = BatchState(
      text: '',
      links: const [],
      skipDuplicates: state.skipDuplicates,
      enqueuing: false,
    );
  }

  void _scheduleResolve() {
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 500),
      () => _resolveAll(),
    );
  }

  Future<void> _resolveAll() async {
    final gen = ++_resolveGen;
    // Links marked duplicate while skipping is on need re-check when the
    // switch flips off: treat them as pending again.
    final toResolve = <BatchLinkState>[];
    for (final l in state.links) {
      if (l.status == BatchLinkStatus.pending) {
        toResolve.add(l);
      } else if (l.status == BatchLinkStatus.duplicate &&
          !state.skipDuplicates) {
        toResolve.add(l.copyWith(status: BatchLinkStatus.pending));
      }
    }
    if (toResolve.isEmpty || gen != _resolveGen) return;

    _updateAll(toResolve
        .map((l) => l.copyWith(status: BatchLinkStatus.resolving))
        .toList(),);

    final pool = Pool(4); // resolve max 4 links at a time
    await Future.wait([
      for (final linkState in toResolve)
        pool.run(() => _resolveOne(linkState, gen)),
    ]);
  }

  void _updateAll(List<BatchLinkState> updated) {
    final byNorm = {for (final l in updated) l.link.normalized: l};
    state = BatchState(
      text: state.text,
      links: [
        for (final l in state.links) byNorm[l.link.normalized] ?? l,
      ],
      skipDuplicates: state.skipDuplicates,
      enqueuing: state.enqueuing,
    );
  }

  void _updateOne(BatchLinkState updated) => _updateAll([updated]);

  Future<void> _resolveOne(BatchLinkState linkState, int gen) async {
    if (gen != _resolveGen) return;
    final normalized = linkState.link.normalized;
    try {
      final engine = await ref.read(engineProvider.future);
      if (state.skipDuplicates && await engine.isDuplicate(normalized)) {
        if (gen != _resolveGen) return;
        _updateOne(linkState.copyWith(
          status: BatchLinkStatus.duplicate,
          message: 'Duplicate · skipped',
        ),);
        return;
      }
      final cache = ref.read(resolverCacheProvider);
      var media = cache.get(normalized);
      media ??= await ref.read(resolverProvider).resolve(normalized);
      cache.put(normalized, media);
      if (gen != _resolveGen) return;

      final settings = ref.read(settingsRepoProvider).value?.current ??
          AppSettings.defaults;
      final stream = media.pickStream(
        format: SaveFormat.video,
        qualityLabel: settings.defaultQuality,
        watermarkFree: false,
      );
      _updateOne(linkState.copyWith(
        status: BatchLinkStatus.ready,
        media: media,
        sizeBytes: stream?.sizeBytes,
        qualityLabel: stream?.label ?? settings.defaultQuality,
      ),);
    } on ResolveException catch (e) {
      if (gen != _resolveGen) return;
      _updateOne(linkState.copyWith(
        status: e.notSupported
            ? BatchLinkStatus.notSupported
            : BatchLinkStatus.failed,
        message: e.notSupported ? 'Link not supported' : e.message,
      ),);
    } catch (_) {
      if (gen != _resolveGen) return;
      _updateOne(linkState.copyWith(
        status: BatchLinkStatus.failed,
        message: 'Failed to read link',
      ),);
    }
  }

  /// Queues every ready link. Returns the number queued.
  Future<int> downloadAll() async {
    final ready = state.links
        .where((l) => l.status == BatchLinkStatus.ready && l.media != null)
        .toList();
    if (ready.isEmpty || state.enqueuing) return 0;
    state = BatchState(
      text: state.text,
      links: state.links,
      skipDuplicates: state.skipDuplicates,
      enqueuing: true,
    );
    var queued = 0;
    try {
      final engine = await ref.read(engineProvider.future);
      final settings =
          ref.read(settingsRepoProvider).value?.current ??
              AppSettings.defaults;
      for (final linkState in ready) {
        final media = linkState.media!;
        if (await engine.isDuplicate(media.sourceUrl)) continue;
        final stream = media.pickStream(
          format: SaveFormat.video,
          qualityLabel: linkState.qualityLabel ?? settings.defaultQuality,
          watermarkFree: false,
        );
        if (stream == null) continue;
        final fileName = FileNameTemplate.render(
          settings.fileNameTemplate,
          author: media.author,
          title: media.title,
          date: DateTime.now(),
          quality: stream.label,
        );
        await engine.enqueue(
          EnqueueRequest(
            originalUrl: linkState.link.raw,
            normalizedUrl: media.sourceUrl,
            title: media.title,
            author: media.author,
            thumbSource: media.thumbnailUrl,
            format: SaveFormat.video,
            qualityLabel: stream.label,
            stream: stream,
            fileName: fileName,
            wifiOnly: settings.wifiOnly,
            keepHistory: settings.keepHistory,
            notifyOnDone: true,
            vibrateOnDone: settings.vibrateOnSaved,
            showProgressNotification: settings.progressNotification,
            subfolder: settings.saveSubfolder,
            duration: media.duration,
          ),
        );
        queued++;
      }
    } finally {
      if (ref.mounted) {
        state = BatchState(
          text: state.text,
          links: state.links,
          skipDuplicates: state.skipDuplicates,
          enqueuing: false,
        );
      }
    }
    return queued;
  }
}
