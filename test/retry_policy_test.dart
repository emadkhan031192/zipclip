import 'package:flutter_test/flutter_test.dart';
import 'package:zipclip/core/engine/retry_policy.dart';

void main() {
  group('RetryPolicy', () {
    test('backs off exponentially: 2s, 4s, 8s', () {
      expect(RetryPolicy.delayForAttempt(1), const Duration(seconds: 2));
      expect(RetryPolicy.delayForAttempt(2), const Duration(seconds: 4));
      expect(RetryPolicy.delayForAttempt(3), const Duration(seconds: 8));
    });

    test('retries at most 3 attempts', () {
      expect(RetryPolicy.maxAttempts, 3);
      expect(RetryPolicy.shouldRetry(1), isTrue);
      expect(RetryPolicy.shouldRetry(2), isTrue);
      expect(RetryPolicy.shouldRetry(3), isFalse);
    });
  });
}
