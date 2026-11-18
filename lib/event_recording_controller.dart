import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:image/image.dart' as img;

import 'event_clip_store.dart';
import 'event_motion_policy.dart';

/// Motion detection uses sparse samples from the ALREADY OPEN WebRTC track.
/// It never starts a second camera, touches audio, or runs in station standby.
List<int>? eventLumaFromFrame(Uint8List encodedFrame) {
  final frame = img.decodeImage(encodedFrame);
  if (frame == null) return null;
  const columns = 16;
  const rows = 12;
  final luma = <int>[];
  for (var y = 0; y < rows; y++) {
    final py = ((y + 0.5) * frame.height / rows).floor()
        .clamp(0, frame.height - 1).toInt();
    for (var x = 0; x < columns; x++) {
      final px = ((x + 0.5) * frame.width / columns).floor()
          .clamp(0, frame.width - 1).toInt();
      final pixel = frame.getPixel(px, py);
      luma.add((0.2126 * pixel.r + 0.7152 * pixel.g +
          0.0722 * pixel.b).round().clamp(0, 255).toInt());
    }
  }
  return luma;
}

/// Recording failures are isolated from WebRTC; never terminate a live call.
/// Each clip is finalized before peer-camera teardown.
class EventRecordingController {
  EventRecordingController({
    required this.onStatus,
    required this.onRecordingChanged,
    EventClipStore? store,
  }) : store = store ?? EventClipStore();

  final EventClipStore store;
  final void Function(String status) onStatus;
  final void Function(bool recording) onRecordingChanged;
  final MotionEventDetector _motion = MotionEventDetector();
  MediaStreamTrack? _track;
  MediaRecorder? _recorder;
  File? _pending;
  Timer? _scanTimer;
  Timer? _stopTimer;
  Future<void>? _starting;
  Future<void>? _stopping;
  int _generation = 0;
  bool _scanning = false;
  bool _recording = false;
  bool _enabled = false;

  bool get isRecording => _recording;
  bool get enabled => _enabled;

  void setEnabled(bool value) {
    _enabled = value;
    if (!value) unawaited(stop());
  }

  Future<void> start(MediaStreamTrack? track) async {
    if (!_enabled || track == null || _track?.id == track.id &&
        _scanTimer != null) return;
    await stop();
    if (!_enabled || track == null) return;
    _track = track;
    final generation = ++_generation;
    _motion.reset();
    _scanTimer = Timer.periodic(EventRecordingPolicy.sampleEvery, (_) {
      unawaited(_sample(generation));
    });
    onStatus('움직임 자동 감지 시작 · 영상 시청 중에만 동작');
  }

  Future<void> _sample(int generation) async {
    if (!_enabled || _scanning || _recording ||
        generation != _generation || _track == null) return;
    _scanning = true;
    try {
      final frame = await _track!.captureFrame();
      final luma = await compute(eventLumaFromFrame,
          frame.asUint8List());
      if (generation == _generation && luma != null &&
          _motion.observe(luma, DateTime.now())) {
        final started = _beginClip(generation);
        _starting = started;
        await started;
      }
    } catch (error) {
      if (generation == _generation) {
        onStatus('움직임 감지 오류 · 영상 시청은 계속됩니다: $error');
        _scanTimer?.cancel();
        _scanTimer = null;
      }
    } finally {
      _scanning = false;
      _starting = null;
    }
  }

  Future<void> _beginClip(int generation) async {
    if (!_enabled || _recording || generation != _generation) return;
    final videoTrack = _track;
    if (videoTrack == null) return;
    File? pending;
    MediaRecorder? recorder;
    try {
      await store.prune();
      pending = await store.createPending();
      recorder = MediaRecorder();
      await recorder.start(pending.path, videoTrack: videoTrack);
      if (!_enabled || generation != _generation) {
        await recorder.stop();
        if (await pending.exists()) await pending.delete();
        return;
      }
      _recorder = recorder;
      _pending = pending;
      _recording = true;
      onRecordingChanged(true);
      onStatus('움직임 감지 · 20초 이벤트 영상 녹화 중');
      _stopTimer = Timer(EventRecordingPolicy.clipDuration, () {
        unawaited(_finishClip());
      });
    } catch (error) {
      onStatus('이벤트 녹화 실패 · 실시간 영상은 유지됩니다: $error');
      try {
        await recorder?.stop();
      } catch (_) {}
      if (pending != null && await pending.exists()) {
        await pending.delete();
      }
    }
  }

  Future<void> _finishClip() async {
    if (_stopping != null) return _stopping;
    final recorder = _recorder;
    final pending = _pending;
    if (recorder == null || pending == null) return;
    _recorder = null;
    _pending = null;
    _stopTimer?.cancel();
    _stopTimer = null;
    final future = () async {
      try {
        await recorder.stop();
        final clip = await store.finalize(pending);
        if (clip == null) {
          onStatus('영상 길이 또는 파일 상태를 확인할 수 없어 저장하지 않았어요');
        } else {
          onStatus('이벤트 영상 저장 완료 · 거치폰 내부에만 저장');
        }
      } catch (error) {
        onStatus('이벤트 영상 저장 실패: $error');
        try {
          if (await pending.exists()) await pending.delete();
        } catch (_) {}
      } finally {
        _recording = false;
        onRecordingChanged(false);
      }
    }();
    _stopping = future;
    await future;
    _stopping = null;
  }

  Future<void> stop() async {
    ++_generation;
    _scanTimer?.cancel();
    _scanTimer = null;
    _stopTimer?.cancel();
    _stopTimer = null;
    _track = null;
    _motion.reset();
    await _starting;
    await _finishClip();
    await _stopping;
  }
}
