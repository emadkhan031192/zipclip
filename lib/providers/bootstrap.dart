import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../core/engine/download_engine.dart';
import '../core/native/zipclip_native.dart';
import '../core/resolver/link_resolver.dart';
import '../core/resolver/mock_resolver.dart';
import '../core/resolver/resolver_cache.dart';
import '../core/storage/app_database.dart';
import '../core/storage/settings.dart';

/// ---------------------------------------------------------------------------
/// App-wide providers. Everything async loads *after* the first frame so
/// cold start stays under a second: the shell renders instantly, data fills
/// in progressively.
/// ---------------------------------------------------------------------------

final nativeProvider = Provider<ZipClipNative>((ref) => ZipClipNative());

final settingsRepoProvider = FutureProvider<SettingsRepository>((ref) async {
  final repo = await SettingsRepository.load();
  ref.onDispose(repo.dispose);
  return repo;
});

final settingsProvider = StreamProvider<AppSettings>((ref) async* {
  final repo = await ref.watch(settingsRepoProvider.future);
  yield repo.current;
  yield* repo.stream;
});

/// The one clean seam for link -> media extraction. Today this is the
/// [MockResolver]; plug a real resolver in here (see README.md).
final resolverProvider = Provider<LinkResolver>((ref) => MockResolver());

final resolverCacheProvider = Provider<ResolverCache>((ref) => ResolverCache());

final appDbProvider = FutureProvider<AppDatabase>((ref) async {
  final dir = await getApplicationDocumentsDirectory();
  final db = await AppDatabase.open('${dir.path}/zipclip.db');
  ref.onDispose(() => db.close());
  return db;
});

final workDirProvider = FutureProvider<Directory>((ref) async {
  final dir = await getApplicationSupportDirectory();
  await Directory('${dir.path}/thumbs').create(recursive: true);
  return dir;
});

final engineProvider = FutureProvider<DownloadEngine>((ref) async {
  final db = await ref.watch(appDbProvider.future);
  final workDir = await ref.watch(workDirProvider.future);
  final native = ref.watch(nativeProvider);
  final settings = await ref.watch(settingsRepoProvider.future);

  final engine = DownloadEngine(
    store: db,
    dio: Dio(),
    workDir: workDir,
    placer: NativeFilePlacer(),
    foreground: NativeForegroundControl(native),
    thumbnailer: NativeThumbnailer(native),
    network: NativeNetworkChecker(native),
    maxParallel: () => settings.current.maxParallel,
  );
  engine.bindWifiOnly(() async => settings.current.wifiOnly);
  await engine.restore();

  native.onSharedLink = (url) {
    ref.read(incomingLinkProvider.notifier).push(url);
  };
  native.onNotificationAction = (id, action) async {
    switch (action) {
      case 'pause':
        await engine.pause(id);
      case 'resume':
        await engine.resume(id);
      case 'cancel':
        await engine.cancel(id);
    }
  };
  await native.init();

  ref.onDispose(() => engine.dispose());
  return engine;
});

/// Links arriving from the Android share sheet (or the quick-save bubble).
class IncomingLinks extends Notifier<List<String>> {
  @override
  List<String> build() => [];

  void push(String url) => state = [...state, url];

  /// Takes the oldest unconsumed link, or null.
  String? take() {
    if (state.isEmpty) return null;
    final url = state.first;
    state = state.sublist(1);
    return url;
  }
}

final incomingLinkProvider =
    NotifierProvider<IncomingLinks, List<String>>(IncomingLinks.new);

/// Free bytes on primary shared storage (Downloads header chip).
final freeSpaceProvider = FutureProvider<int?>((ref) async {
  final native = ref.watch(nativeProvider);
  return native.getFreeSpaceBytes();
});
