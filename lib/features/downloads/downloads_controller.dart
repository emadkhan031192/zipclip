import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/engine/download_store.dart';
import '../../core/models/media.dart';
import '../../providers/bootstrap.dart';
import '../../providers/tasks.dart';

/// Tasks that are not finished yet (downloading / queued / paused / waiting).
final activeTasksProvider = FutureProvider<List<StoredTask>>((ref) async {
  final db = await ref.watch(appDbProvider.future);
  ref.watch(engineTickProvider);
  final tasks = await db.listTasks();
  const live = {
    TaskStatus.downloading,
    TaskStatus.queued,
    TaskStatus.paused,
    TaskStatus.waitingForWifi,
    TaskStatus.failed,
  };
  return tasks.where((t) => live.contains(t.status)).toList();
});

/// Saved files, filtered by the current tab.
final savedItemsProvider =
    FutureProvider.family<List<SavedItem>, SaveFormat>((ref, format) async {
  final db = await ref.watch(appDbProvider.future);
  ref.watch(engineTickProvider);
  return db.listHistory(format: format);
});

/// Saved count for the "Saved (N)" header.
final savedCountProvider =
    FutureProvider.family<int, SaveFormat>((ref, format) async {
  final items = await ref.watch(savedItemsProvider(format).future);
  return items.length;
});

/// Free space, refreshed whenever downloads change.
final freeSpaceLiveProvider = FutureProvider<int?>((ref) async {
  ref.watch(engineTickProvider);
  final native = ref.watch(nativeProvider);
  return native.getFreeSpaceBytes();
});
