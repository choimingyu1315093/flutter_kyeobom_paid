import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/services.dart';

import 'baby_sound_policy.dart';
import 'baby_cry_classifier.dart';
import 'baby_cry_policy.dart';

/// Local-only sound-change monitoring. P0 receives dBFS only. Optional
/// P1 QA receives bounded waveform windows into the local interpreter.
/// Neither path saves audio files, sends audio over the network or logs audio.
class BabySoundMonitor {
  BabySoundMonitor({
    required this.onStatus,
    required this.onDetection,
    this.enableCryQa = false,
    this.onCryStatus,
  });

  static const MethodChannel _native = MethodChannel('home_camera/screen');
  static const pollInterval = Duration(milliseconds: 500);

  final void Function(String) onStatus;
  final void Function(int count) onDetection;
  final BabySoundDetector _detector = BabySoundDetector();
  final bool enableCryQa;
  final void Function(String)? onCryStatus;
  final BabyCryPolicy _cryPolicy = BabyCryPolicy();
  BabyCryClassifier? _cryClassifier;
  Future<void>? _cryPending;
  bool _cryActive = false;
  bool _disposed = false;
  int _revision = 0;
  int _cryEvents = 0;

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

  Future<void> start() {
    final revision = _revision;
    return _enqueue(() async {
    if (!_enabled || _running || _disposed || revision != _revision) return;
    _cryActive = false;
    _cryPolicy.resetWindow();
    if (enableCryQa) {
      try {
        final classifier = _cryClassifier ??= BabyCryClassifier();
        await classifier.initialize();
        if (_disposed || revision != _revision || !_enabled) return;
        _cryActive = true;
        onCryStatus?.call('울음 판별 QA 준비 완료');
      } catch (_) {
        if (!_disposed && revision == _revision && _enabled) {
          onCryStatus?.call('울음 모델 로드 실패 · 일반 소리 감지만 동작');
        }
      }
    }
    if (!_enabled || _disposed || revision != _revision) {
      _cryActive = false;
      return;
    }
    await _native.invokeMethod<void>(
        'startBabySoundMonitoring', _cryActive ? {'cryQa': true} : null);
    // A disable request may have arrived during permission/native setup.
    if (!_enabled || _disposed || revision != _revision) {
      _cryActive = false;
      await _native.invokeMethod<void>('stopBabySoundMonitoring');
      return;
    }
    _running = true;
    _detector.reset();
    _poll = Timer.periodic(pollInterval, (_) => unawaited(_sample()));
    onStatus('베이비 모드 · 주변 소리 변화 감지 중 (녹음·전송 없음)');
    });
  }

  Future<void> stop() {
    ++_revision;
    _cryActive = false;
    _cryPolicy.resetWindow();
    if (enableCryQa && !_disposed) {
      onCryStatus?.call('울음 판별 QA 일시정지 · $_cryEvents회');
    }
    return _enqueue(() async {
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
  }

  Future<void> dispose() async {
    _disposed = true;
    try { await stop(); } finally {
      await _cryPending;
      await _cryClassifier?.close();
    }
  }

  Future<void> _sample() async {
    if (!_running || _sampling || _disposed || !_enabled) return;
    final revision = _revision;
    _sampling = true;
    try {
      final db = await _native.invokeMethod<double>('readBabySoundLevel');
      if (!_running || _disposed || !_enabled ||
          revision != _revision || db == null) return;
      if (_detector.observe(db, DateTime.now())) {
        _events++;
        onDetection(_events);
        onStatus('소리 변화 감지 · 현재 대기 화면에서 확인 가능');
      }
      if (_cryActive && _cryPending == null) {
        final task = _sampleCry(_revision);
        _cryPending = task;
        unawaited(task.whenComplete(() { _cryPending = null; }));
      }
    } catch (error) {
      if (_running && !_disposed && revision == _revision) {
        onStatus('소리 감지 오류 · 베이비 모드를 껐다 켜주세요: $error');
        unawaited(stop().catchError((Object _) {}));
      }
    } finally {
      _sampling = false;
    }
  }

  Future<void> _sampleCry(int revision) async {
    try {
      final window = await _native.invokeMapMethod<String, dynamic>('readBabyCryWindow');
      if (!_running || !_cryActive || revision != _revision || window == null) return;
      final pcm = window['pcm'];
      final rate = window['rate'];
      if (pcm is! Float32List || rate is! int) {
        _cryPolicy.resetWindow();
        return;
      }
      final frame = babyCryResample(pcm, rate);
      if (frame == null) {
        _cryPolicy.resetWindow();
        return;
      }
      final score = await _cryClassifier!.score(frame);
      if (!_running || !_cryActive || revision != _revision) return;
      if (_cryPolicy.observe(score, DateTime.now())) _cryEvents++;
      onCryStatus?.call('아기 울음 후보 $_cryEvents회 · 모델 점수 ${score.toStringAsFixed(2)}');
    } catch (_) {
      if (revision == _revision && _cryActive) {
        _cryActive = false;
        _cryPolicy.resetWindow();
        // Stop collecting waveform windows while keeping P0 dB monitoring.
        try { await _native.invokeMethod<void>('disableBabyCryCapture'); } catch (_) {}
        if (revision == _revision) {
          onCryStatus?.call('울음 추론 오류 · 일반 소리 감지만 동작');
        }
      }
    }
  }

  Future<void> _enqueue(Future<void> Function() action) {
    final work = _operations.then((_) => action());
    _operations = work.catchError((Object _) {});
    return work;
  }
}
