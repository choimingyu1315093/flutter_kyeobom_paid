import 'dart:async';

import 'package:flutter/services.dart';

import 'baby_sound_policy.dart';

/// Local-only baby sound-change monitoring. The native layer reads the mic's
/// energy (dBFS), never raw audio, and never stores or transmits audio.
class BabySoundMonitor {
  BabySoundMonitor({
    required this.onStatus,
    required this.onDetection,
  });

  static const MethodChannel _native = MethodChannel('home_camera/screen');
  static const pollInterval = Duration(milliseconds: 500);

  final void Function(String) onStatus;
  final void Function(int count) onDetection;
  final BabySoundDetector _detector = BabySoundDetector();

  Future<void> _operations = Future<void>.value();
  Timer? _poll;
  bool _enabled = false;
  bool _running = false;
  bool _sampling = false;
  int _events = 0;

  bool get enabled => _enabled;
  bool get running => _running;
  int get eventCount => _events;

  void setEnabled(bool enabled) {
    _enabled = enabled;
  }

  Future<void> start() => _enqueue(() async {
    if (!_enabled || _running) return;
    await _native.invokeMethod<void>('startBabySoundMonitoring');
    // A disable request may have arrived during permission/native setup.
    if (!_enabled) {
      await _native.invokeMethod<void>('stopBabySoundMonitoring');
      return;
    }
    _running = true;
    _detector.reset();
    _poll = Timer.periodic(pollInterval, (_) => unawaited(_sample()));
    onStatus('베이비 모드 · 주변 소리 변화 감지 중 (녹음·전송 없음)');
  });

  Future<void> stop() => _enqueue(() async {
    _poll?.cancel();
    _poll = null;
    if (!_running) return;
    _running = false;
    try {
      await _native.invokeMethod<void>('stopBabySoundMonitoring');
    } finally {
      _detector.reset();
    }
  });

  Future<void> _sample() async {
    if (!_running || _sampling) return;
    _sampling = true;
    try {
      final db = await _native.invokeMethod<double>('readBabySoundLevel');
      if (!_running || db == null) return;
      if (_detector.observe(db, DateTime.now())) {
        _events++;
        onDetection(_events);
        onStatus('소리 변화 감지 · 현재 대기 화면에서 확인 가능');
      }
    } catch (error) {
      if (_running) {
        onStatus('소리 감지 오류 · 베이비 모드를 껐다 켜주세요: $error');
        unawaited(stop());
      }
    } finally {
      _sampling = false;
    }
  }

  Future<void> _enqueue(Future<void> Function() action) {
    final work = _operations.then((_) => action());
    _operations = work.catchError((Object _) {});
    return work;
  }
}
