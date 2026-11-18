/// Conservative bounded recovery for viewer-side WebRTC transport failures.
abstract final class HomeCamRecoveryPolicy {
  static const initialConnectionTimeout = Duration(seconds: 30);
  static const disconnectedGrace = Duration(seconds: 8);
  static const maxRetries = 3;

  static Duration? retryDelay(int attemptedRetries) {
    return switch (attemptedRetries) {
      0 => const Duration(seconds: 2),
      1 => const Duration(seconds: 5),
      2 => const Duration(seconds: 10),
      _ => null,
    };
  }

  static bool shouldRetry({
    required bool userStopped,
    required bool leaving,
    required bool inBackground,
    required int attemptedRetries,
  }) =>
      !userStopped &&
      !leaving &&
      !inBackground &&
      attemptedRetries < maxRetries;
}
