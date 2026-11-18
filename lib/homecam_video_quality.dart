/// Free video capture preferences. These are ideals, never guarantees:
/// camera/encoder/network/temperature determine the real output quality.
abstract final class HomeCamVideoQuality {
  static const preferredWidth = 1920;
  static const preferredHeight = 1080;
  static const preferredFps = 24;
  static const fallbackWidth = 1280;
  static const fallbackHeight = 720;
  static const fallbackFps = 20;

  static const preferredBitrateBps = 3000000;
  static const fallbackBitrateBps = 1800000;

  static Map<String, dynamic> cameraConstraints({bool fallback = false}) => {
        'audio': false,
        'video': {
          'facingMode': 'environment',
          'width': {'ideal': fallback ? fallbackWidth : preferredWidth},
          'height': {'ideal': fallback ? fallbackHeight : preferredHeight},
          'frameRate': {'ideal': fallback ? fallbackFps : preferredFps},
        },
      };

  /// Do not retry denied camera permissions as if they were weak hardware.
  static bool canFallbackFor(Object error) {
    final message = error.toString().toLowerCase();
    return !message.contains('permission') &&
        !message.contains('notallowed') &&
        !message.contains('denied') &&
        !message.contains('security');
  }
}
