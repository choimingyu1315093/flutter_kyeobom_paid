import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_home_camera/homecam_video_quality.dart';
import 'package:flutter_home_camera/homecam_recovery_policy.dart';

void main() {
  test('free mode prefers full HD and falls back to HD', () {
    final hd = HomeCamVideoQuality.cameraConstraints(fallback: true);
    final fullHd = HomeCamVideoQuality.cameraConstraints();
    expect((fullHd['video'] as Map)['width'], {'ideal': 1920});
    expect((fullHd['video'] as Map)['height'], {'ideal': 1080});
    expect((hd['video'] as Map)['width'], {'ideal': 1280});
    expect((hd['video'] as Map)['frameRate'], {'ideal': 20});
    expect(HomeCamVideoQuality.preferredBitrateBps, greaterThan(
        HomeCamVideoQuality.fallbackBitrateBps));
  });

  test('never retry a denied camera permission', () {
    expect(HomeCamVideoQuality.canFallbackFor(Exception('NotAllowedError')),
        isFalse);
    expect(HomeCamVideoQuality.canFallbackFor(Exception('Permission denied')),
        isFalse);
    expect(HomeCamVideoQuality.canFallbackFor(Exception('Overconstrained')),
        isTrue);
  });

  test('recovery is finite and user cancellation is final', () {
    expect(HomeCamRecoveryPolicy.retryDelay(0), const Duration(seconds: 2));
    expect(HomeCamRecoveryPolicy.retryDelay(1), const Duration(seconds: 5));
    expect(HomeCamRecoveryPolicy.retryDelay(2), const Duration(seconds: 10));
    expect(HomeCamRecoveryPolicy.retryDelay(3), isNull);
    expect(HomeCamRecoveryPolicy.shouldRetry(
        userStopped: false, leaving: false, inBackground: false,
        attemptedRetries: 2), isTrue);
    expect(HomeCamRecoveryPolicy.shouldRetry(
        userStopped: true, leaving: false, inBackground: false,
        attemptedRetries: 0), isFalse);
    expect(HomeCamRecoveryPolicy.shouldRetry(
        userStopped: false, leaving: true, inBackground: false,
        attemptedRetries: 0), isFalse);
    expect(HomeCamRecoveryPolicy.shouldRetry(
        userStopped: false, leaving: false, inBackground: true,
        attemptedRetries: 0), isFalse);
  });
}
