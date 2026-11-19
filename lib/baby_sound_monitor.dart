import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/services.dart';

import 'baby_sound_policy.dart';
import 'baby_cry_classifier.dart';
import 'baby_cry_policy.dart';
import 'baby_cry_gain.dart';

/// Local-only sound-change monitoring. P0 receives dBFS only. Optional
/// P1 QA receives bounded waveform windows into the local interpreter.
/// Neither path saves audio files, sends audio over the network or logs audio.
class BabySoundMonitor {
  BabySoundMonitor({
    required this.onStatus,
    required this.onDetection,
    this.enableCryQa = false,
    this.onCryDetected,
  });

  static const MethodChannel _native = MethodChannel('home_camera/screen');
  static const pollInterval = Duration(milliseconds: 500);

  final void Function(String) onStatus;
  final void Function(int count) onDetection;
  final BabySoundDetector _detector = BabySoundDetector();
  final bool enableCryQa;
  final void Function()? onCryDetected;
  final BabyCryPolicy _cryPolicy = BabyCryPolicy();
  BabyCryClassifier? _cryClassifier;
  Future<void>? _cryPending;
  bool _cryActive = false;
  bool _disposed = false;
  int _revision = 0;
  int _cryEmptyPolls = 0;
  bool _inputWarning = false;

  Future<void> _operations = Future<void>.value();
  Timer? _poll;
  bool _enabled = false;
  bool _running = false;
  String? _sourceTrackId;
  bool _sampling = false;
  int _events = 0;

  bool get enabled => _enabled;
  bool get running => _running;
  bool get usingRtcAudio => _running && _sourceTrackId != null;
  int get eventCount => _events;

  void setEnabled(bool enabled) {
    _enabled = enabled;
  }

  Future<void> start({String? webRtcTrackId}) {
    final revision = _revision;
    return _enqueue(() async {
    if (!_enabled || _disposed || revision != _revision) return;
    if (_running) {
      if (_sourceTrackId == webRtcTrackId) return;
      // A WebRTC peer can close on its own. Reconcile any stale source
      // before reopening the native capture, never run two microphones.
      _cryActive = false;
      _poll?.cancel();
      _poll = null;
      _running = false;
      _sourceTrackId = null;
      await _native.invokeMethod<void>('stopBabySoundMonitoring');
      if (!_enabled || _disposed || revision != _revision) return;
    }
    _cryActive = false;
    _cryPolicy.resetWindow();
    _cryEmptyPolls = 0;
    _inputWarning = false;
    if (enableCryQa) {
      try {
        final classifier = _cryClassifier ??= BabyCryClassifier();
        await classifier.initialize();
        if (_disposed || revision != _revision || !_enabled) return;
        _cryActive = true;

      } catch (error) {
        if (!_disposed && revision == _revision && _enabled) {
          onStatus('아기 울음 감지 모델을 시작하지 못했어요.');
          rethrow;
        }
      }
    }
    if (!_enabled || _disposed || revision != _revision) {
      _cryActive = false;
      return;
    }
    if (webRtcTrackId != null) {
      await _native.invokeMethod<void>('startBabyRtcMonitoring',
          {'trackId': webRtcTrackId});
    } else {
      await _native.invokeMethod<void>(
          'startBabySoundMonitoring', _cryActive ? {'cryQa': true} : null);
    }
    // A disable request may have arrived during permission/native setup.
    if (!_enabled || _disposed || revision != _revision) {
      _cryActive = false;
      await _native.invokeMethod<void>('stopBabySoundMonitoring');
      return;
    }
    _running = true;
    _sourceTrackId = webRtcTrackId;
    _detector.reset();
    _poll = Timer.periodic(pollInterval, (_) => unawaited(_sample()));
    onStatus('아기 울음 감지 중');
    });
  }

  Future<void> stop() {
    ++_revision;
    _cryActive = false;
    _cryPolicy.resetWindow();
    return _enqueue(() async {
    _poll?.cancel();
    _poll = null;
    if (!_running) return;
    _running = false;
    _sourceTrackId = null;
    try {
      await _native.invokeMethod<void>('stopBabySoundMonitoring');
    } finally {
      _detector.reset();
      if (_enabled && !_disposed) onStatus('아기 울음 감지 준비 중');
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
      if (!_running || !_cryActive || revision != _revision) return;
      if (window == null) {
        if (++_cryEmptyPolls >= 10) {
          _cryEmptyPolls = 0;
          _inputWarning = true;
          onStatus('마이크 입력을 확인하고 있어요.');
        }
        return;
      }
      _cryEmptyPolls = 0;
      final pcm = window['pcm'];
      final rate = window['rate'];
      if (pcm is! Float32List || rate is! int) {
        _cryPolicy.resetWindow();
        _inputWarning = true;
        onStatus('마이크 입력을 확인해 주세요.');
        return;
      }
      final frame = babyCryResample(pcm, rate);
      if (frame == null) {
        _cryPolicy.resetWindow();
        _inputWarning = true;
        onStatus('마이크 입력을 확인해 주세요.');
        return;
      }
      if (_inputWarning) {
        _inputWarning = false;
        onStatus('아기 울음 감지 중');
      }
      final raw = await _cryClassifier!.classify(frame);
      if (!_running || !_cryActive || !_enabled || revision != _revision) return;
      BabyCryGainFrame? gainFrame;
      BabyCryInference? boosted;
      // Original inference always runs first. No new microphone path and no
      // second policy observation for a transformed copy of the same window.
      if (!_cryPolicy.inCooldown(DateTime.now()) &&
          _cryPolicy.evidenceFor(raw) != BabyCryEvidence.strong) {
        gainFrame = prepareBabyCryGain(frame);
        if (gainFrame != null) {
          try {
            boosted = await _cryClassifier!.classify(gainFrame.samples);
          } catch (_) {
            // A fallback failure must not discard the original prediction.
            // Use the original inference for this window.
          }
        }
      }
      if (!_running || !_cryActive || !_enabled || revision != _revision) return;
      final inference = selectBabyCryInference(
          policy: _cryPolicy, raw: raw, boosted: boosted);
      if (_cryPolicy.observeInference(inference, DateTime.now())) {
        onCryDetected?.call();
      }
    } catch (_) {
      if (revision == _revision && _cryActive) {
        _cryActive = false;
        _cryPolicy.resetWindow();
        // Stop collecting waveform windows while keeping P0 dB monitoring.
        try { await _native.invokeMethod<void>('disableBabyCryCapture'); } catch (_) {}
        if (revision == _revision) {
          onStatus('아기 울음 감지 오류 · 베이비 모드를 다시 켜 주세요.');
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
