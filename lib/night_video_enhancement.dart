import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Only the paid station can attach this pre-encoder processor. The
/// compile-time override permits same-device A/B tests with the original feed.
/// No native camera, recorder, microphone or network connection is opened.
class NightVideoEnhancement {
  NightVideoEnhancement({
    MethodChannel channel = const MethodChannel('home_camera/screen'),
    bool enabled = const bool.fromEnvironment('KYEOBOM_NIGHT_ENHANCE',
        defaultValue: true),
  }) : _channel = channel, _enabled = enabled;

  final MethodChannel _channel;
  final bool _enabled;
  String? _trackId;

  Future<bool> attach(String trackId) async {
    if (!_enabled) return false;
    if (_trackId == trackId) return true;
    await detach();
    try {
      final attached = await _channel.invokeMethod<bool>(
          'attachNightVideo', {'trackId': trackId}) == true;
      if (attached) _trackId = trackId;
      return attached;
    } catch (error) {
      if (kDebugMode) debugPrint('[kyeobom/night] attach unavailable: $error');
      return false;
    }
  }

  Future<void> detach() async {
    final id = _trackId;
    _trackId = null;
    if (id == null) return;
    try {
      await _channel.invokeMethod<void>('detachNightVideo', {'trackId': id});
    } catch (error) {
      if (kDebugMode) debugPrint('[kyeobom/night] detach unavailable: $error');
    }
  }
}
