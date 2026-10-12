import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/engine/download_engine.dart';
import '../../core/engine/download_store.dart';
import '../../core/engine/file_naming.dart';
import '../../core/models/media.dart';
import '../../core/resolver/link_normalizer.dart';
import '../../core/resolver/link_resolver.dart';
import '../../core/storage/settings.dart';
import '../../providers/bootstrap.dart';
import '../../providers/tasks.dart';

class HomeState {
  const HomeState({
    required this.linkText,
    required this.resolving,
    required this.media,
    required this.resolveError,
    required this.format,
    required this.quality,
    required this.removeWatermark,
    required this.activeTaskId,
    required this.startingDownload,
    required this.doneUri,
    required this.doneTitle,
    required this.doneElapsedMs,
    required this.clipboardLink,
    required this.duplicateOf,
  });

  factory HomeState.initial() => const HomeState(
        linkText: '',
        resolving: false,
        media: null,
        resolveError: null,
        format: SaveFormat.video,
        quality: '1080p',
        removeWatermark: true,
        activeTaskId: null,
        startingDownload: false,
        doneUri: null,
        doneTitle: null,
        doneElapsedMs: null,
        clipboardLink: null,
        duplicateOf: null,
      );

  final String linkText;
  final bool resolving;
  final ResolvedMedia? media;
  final String? resolveError;
  final SaveFormat format;
  final String quality;
  final bool removeWatermark;
  final String? activeTaskId;
  final bool startingDownload;
  final String? doneUri;
  final String? doneTitle;
  final int? doneElapsedMs;
  final String? clipboardLink;
  final SavedItem? duplicateOf;

  bool get isDownloading => activeTaskId != null;
  bool get isDone => doneUri != null;

  HomeState copyWith({
    String? linkText,
    bool? resolving,
    ResolvedMedia? media,
    bool clearMedia = false,
    String? resolveError,
    bool clearError = false,
    SaveFormat? format,
    String? quality,
    bool? removeWatermark,
    String? activeTaskId,
    bool clearTask = false,
    bool? startingDownload,
    String? doneUri,
    String? doneTitle,
    int? doneElapsedMs,
    bool clearDone = false,
    String? clipboardLink,
    bool clearClipboard = false,
    SavedItem? duplicateOf,
    bool clearDuplicate = false,
  }) =>
      HomeState(
        linkText: linkText ?? this.linkText,
        resolving: resolving ?? this.resolving,
        media: clearMedia ? null : (media ?? this.media),
        resolveError: clearError ? null : (resolveError ?? this.resolveError),
        format: format ?? this.format,
        quality: quality ?? this.quality,
        removeWatermark: removeWatermark ?? this.removeWatermark,
        activeTaskId: clearTask ? null : (activeTaskId ?? this.activeTaskId),
        startingDownload: startingDownload ?? this.startingDownload,
        doneUri: clearDone ? null : (doneUri ?? this.doneUri),
        doneTitle: clearDone ? null : (doneTitle ?? this.doneTitle),
        doneElapsedMs:
            clearDone ? null : (doneElapsedMs ?? this.doneElapsedMs),
        clipboardLink:
            clearClipboard ? null : (clipboardLink ?? this.clipboardLink),
        duplicateOf:
            clearDuplicate ? null : (duplicateOf ?? this.duplicateOf),
      );
}

final homeControllerProvider =
    NotifierProvider<HomeController, HomeState>(HomeController.new);

/// Last two saved items for the Home "Recent" section.
final recentItemsProvider = FutureProvider<List<SavedItem>>((ref) async {
  final db = await ref.watch(appDbProvider.future);
  ref.watch(engineTickProvider);
  return db.listHistory(limit: 2);
});

class HomeController extends Notifier<HomeState> {
  Timer? _debounce;
  StreamSubscription<TaskProgress>? _taskSub;
  bool _customized = false;
  bool _autoDownloadArmed = false;

  @override
  HomeState build() {
    ref.onDispose(() {
      _debounce?.cancel();
      _taskSub?.cancel();
    });
    // Apply the user's saved defaults until they touch the choices.
    ref.listen(settingsRepoProvider, (_, next) {
      next.whenData((repo) {
        if (!_customized && ref.mounted) {
          final s = repo.current;
          state = state.copyWith(
            format: s.defaultFormat,
            quality: s.defaultQuality,
            removeWatermark: s.removeWatermarkDefault,
          );
        }
      });
    });
    return HomeState.initial();
  }

  // ------------------------------------------------------------ link input

  void setLink(String text) {
    _autoDownloadArmed = false;
    state = state.copyWith(
      linkText: text,
      clearDone: true,
      clearDuplicate: true,
      clearError: true,
    );
    _scheduleResolve();
  }

  void clearLink() {
    _debounce?.cancel();
    state = state.copyWith(
      linkText: '',
      clearMedia: true,
      clearError: true,
      clearDuplicate: true,
      resolving: false,
    );
  }

  Future<void> pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.isNotEmpty) setLink(text);
  }

  /// "Download" on the clipboard card: fetch the copied link right away.
  void downloadClipboardLink() {
    final link = state.clipboardLink;
    if (link == null) return;
    _autoDownloadArmed = true;
    state = state.copyWith(linkText: link, clearClipboard: true);
    _scheduleResolve();
  }

  /// A link shared into the app from another app.
  void consumeSharedLink(String url) {
    _autoDownloadArmed =
        ref.read(settingsRepoProvider).value?.current
                .startSavingRightAway ??
            true;
    state = state.copyWith(
      linkText: url,
      clearDone: true,
      clearDuplicate: true,
      clearError: true,
    );
    _scheduleResolve();
  }

  Future<void> refreshClipboard() async {
    final settings =
        ref.read(settingsRepoProvider).value?.current;
    if (settings != null && !settings.detectClipboardLinks) {
      if (state.clipboardLink != null) {
        state = state.copyWith(clearClipboard: true);
      }
      return;
    }
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text?.trim() ?? '';
      if (LinkNormalizer.looksLikeLink(text) &&
          text != state.linkText.trim()) {
        if (state.clipboardLink != text) {
          state = state.copyWith(clipboardLink: text);
        }
      } else if (state.clipboardLink != null) {
        state = state.copyWith(clearClipboard: true);
      }
    } catch (_) {
      // Clipboard unavailable; stay quiet.
    }
  }

  void _scheduleResolve() {
    _debounce?.cancel();
    final text = state.linkText.trim();
    if (!LinkNormalizer.looksLikeLink(text)) {
      state = state.copyWith(
        clearMedia: true,
        clearError: true,
        resolving: false,
      );
      return;
    }
    state = state.copyWith(resolving: true, clearError: true);
    _debounce = Timer(
      const Duration(milliseconds: 450),
      () => _resolve(text),
    );
  }

  Future<void> _resolve(String text) async {
    final normalized = LinkNormalizer.normalize(text);
    if (normalized == null || !ref.mounted) return;
    // Ignore stale results if the user typed something else meanwhile.
    final current = LinkNormalizer.normalize(state.linkText.trim());
    try {
      final cache = ref.read(resolverCacheProvider);
      var media = cache.get(normalized);
      media ??= await ref.read(resolverProvider).resolve(normalized);
      cache.put(normalized, media);
      if (!ref.mounted ||
          LinkNormalizer.normalize(state.linkText.trim()) != normalized) {
        return;
      }
      state = state.copyWith(
        resolving: false,
        media: media,
        clearError: true,
        clearDuplicate: true,
      );
      if (_autoDownloadArmed) {
        _autoDownloadArmed = false;
        await startDownload();
      }
    } on ResolveException catch (e) {
      if (!ref.mounted || current != normalized) return;
      _autoDownloadArmed = false;
      state = state.copyWith(
        resolving: false,
        clearMedia: true,
        resolveError: e.message,
      );
    } catch (_) {
      if (!ref.mounted || current != normalized) return;
      _autoDownloadArmed = false;
      state = state.copyWith(
        resolving: false,
        clearMedia: true,
        resolveError:
            'Could not read that link. Check your connection and try again.',
      );
    }
  }

  // -------------------------------------------------------------- choices

  void setFormat(SaveFormat format) {
    _customized = true;
    state = state.copyWith(format: format, clearDuplicate: true);
  }

  void setQuality(String quality) {
    _customized = true;
    state = state.copyWith(quality: quality, clearDuplicate: true);
  }

  void toggleWatermark(bool value) {
    _customized = true;
    state = state.copyWith(removeWatermark: value, clearDuplicate: true);
  }

  /// The stream matching the current choices (null for Cover / unknown).
  MediaStream? get pickedStream {
    final media = state.media;
    if (media == null) return null;
    if (state.format == SaveFormat.cover) return null;
    return media.pickStream(
      format: state.format,
      qualityLabel: state.quality,
      watermarkFree:
          state.removeWatermark && media.offersWatermarkFree,
    );
  }

  // -------------------------------------------------------------- download

  Future<void> startDownload() async {
    final media = state.media;
    if (media == null || state.startingDownload || state.isDownloading) {
      return;
    }
    state = state.copyWith(
      startingDownload: true,
      clearDuplicate: true,
      clearError: true,
    );
    try {
      final MediaStream stream;
      if (state.format == SaveFormat.cover) {
        stream = MediaStream(
          id: 'cover',
          label: 'Cover',
          url: media.thumbnailUrl,
          container: 'jpg',
          hasVideo: false,
          hasAudio: false,
          watermarkFree: true,
        );
      } else {
        final picked = pickedStream;
        if (picked == null) {
          state = state.copyWith(
            startingDownload: false,
            resolveError: 'No stream available for these choices.',
          );
          return;
        }
        stream = picked;
      }

      final engine = await ref.read(engineProvider.future);
      if (await engine.isDuplicate(media.sourceUrl)) {
        final db = await ref.read(appDbProvider.future);
        final existing = await db.findByUrl(media.sourceUrl);
        state = state.copyWith(
          startingDownload: false,
          duplicateOf: existing,
        );
        return;
      }

      final settings = ref.read(settingsRepoProvider).value?.current ??
          AppSettings.defaults;
      final fileName = FileNameTemplate.render(
        settings.fileNameTemplate,
        author: media.author,
        title: media.title,
        date: DateTime.now(),
        quality: state.format == SaveFormat.audio ? 'audio' : state.quality,
      );
      final id = await engine.enqueue(
        EnqueueRequest(
          originalUrl: state.linkText.trim(),
          normalizedUrl: media.sourceUrl,
          title: media.title,
          author: media.author,
          thumbSource: media.thumbnailUrl,
          format: state.format,
          qualityLabel:
              state.format == SaveFormat.audio ? 'Audio' : state.quality,
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
      state = state.copyWith(startingDownload: false, activeTaskId: id);
      _watchTask(engine, id, media.sourceUrl);
    } catch (_) {
      if (!ref.mounted) return;
      state = state.copyWith(
        startingDownload: false,
        resolveError: 'Could not start the download. Try again.',
      );
    }
  }

  void _watchTask(
      DownloadEngine engine, String id, String normalizedUrl,) {
    _taskSub?.cancel();
    _taskSub = engine.watch(id).listen((p) async {
      if (!ref.mounted) return;
      if (p.status == TaskStatus.completed) {
        final task = await engine.getTask(id);
        state = state.copyWith(
          clearTask: true,
          doneUri: task?.fileUri,
          doneTitle: task?.title,
          doneElapsedMs: p.elapsedMs,
        );
      } else if (p.status == TaskStatus.failed) {
        state = state.copyWith(
          clearTask: true,
          resolveError: p.error ?? 'Download failed.',
        );
      } else if (p.status == TaskStatus.canceled) {
        state = state.copyWith(clearTask: true);
      }
    });
  }

  Future<void> retryDownload() => startDownload();

  /// "Next": clear for the next link.
  void next() {
    _taskSub?.cancel();
    _debounce?.cancel();
    final s = ref.read(settingsRepoProvider).value?.current;
    state = HomeState.initial().copyWith(
      format: s?.defaultFormat,
      quality: s?.defaultQuality,
      removeWatermark: s?.removeWatermarkDefault,
    );
    _customized = false;
  }

  // ------------------------------------------------------------- file ops

  String _mimeFor(SaveFormat format) => switch (format) {
        SaveFormat.video => 'video/mp4',
        SaveFormat.audio => 'audio/mpeg',
        SaveFormat.cover => 'image/jpeg',
      };

  Future<bool> openDone() async {
    final uri = state.doneUri;
    if (uri == null) return false;
    final native = ref.read(nativeProvider);
    return native.openMedia(uri, _mimeFor(state.format));
  }

  Future<void> shareDone() async {
    final uri = state.doneUri;
    if (uri == null) return;
    final native = ref.read(nativeProvider);
    await native.shareMedia(uri, _mimeFor(state.format));
  }

  Future<bool> openDuplicate() async {
    final item = state.duplicateOf;
    if (item == null) return false;
    final native = ref.read(nativeProvider);
    return native.openMedia(item.fileUri, _mimeFor(item.format));
  }
}
