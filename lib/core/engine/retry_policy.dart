/// Automatic retry with exponential backoff: 3 tries total.
abstract final class RetryPolicy {
  static const int maxAttempts = 3;
  static const Duration baseDelay = Duration(seconds: 2);

  /// 2s after attempt 1, 4s after attempt 2, 8s after attempt 3, ...
  static Duration delayForAttempt(int attempt) =>
      baseDelay * (1 << (attempt - 1));

  static bool shouldRetry(int attempt) => attempt < maxAttempts;
}
