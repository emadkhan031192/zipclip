import 'dart:async';

/// Tiny async semaphore: runs at most [max] tasks concurrently.
class Pool {
  Pool(this.max) : assert(max >= 1);

  final int max;
  int _running = 0;
  final _waiters = <Completer<void>>[];

  int get running => _running;

  Future<T> run<T>(Future<T> Function() task) async {
    while (_running >= max) {
      final waiter = Completer<void>();
      _waiters.add(waiter);
      await waiter.future;
    }
    _running++;
    try {
      return await task();
    } finally {
      _running--;
      if (_waiters.isNotEmpty) {
        _waiters.removeAt(0).complete();
      }
    }
  }
}
