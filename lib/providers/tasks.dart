import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/engine/download_engine.dart';
import 'bootstrap.dart';

/// Re-emits whenever the engine's task list changes (enqueue, status flip,
/// progress tick). List screens watch this to refresh.
final engineTickProvider = StreamProvider<void>((ref) async* {
  final engine = await ref.watch(engineProvider.future);
  yield null;
  yield* engine.changed;
});

/// Fine-grained progress for one task, starting with the latest snapshot.
final taskProgressProvider =
    StreamProvider.family<TaskProgress, String>((ref, id) async* {
  final engine = await ref.watch(engineProvider.future);
  final snap = await engine.snapshot(id);
  if (snap != null) yield snap;
  yield* engine.watch(id);
});
