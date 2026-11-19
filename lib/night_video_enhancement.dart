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
  bool get attached => _trackId != null;

  Future<bool> attach(String? trackId) async {
    // MediaStreamTrack.id is nullable in the WebRTC interface.
    // Missing identifiers must never interrupt the original video path.
    if (!_enabled || trackId == null || trackId.trim().isEmpty) return false;
    if (_trackId == trackId) return true;
    if (!await detach()) return false;
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

  Future<bool> detach() async {
    final id = _trackId;
    if (id == null) return true;
    try {
      await _channel.invokeMethod<void>('detachNightVideo', {'trackId': id});
      if (_trackId == id) _trackId = null;
      return true;
    } catch (error) {
      if (kDebugMode) debugPrint('[kyeobom/night] detach unavailable: $error');
      return false;
    }
  }

}
