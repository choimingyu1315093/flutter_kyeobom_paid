import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'remote_control.dart';

/// A separate, audio-only WebRTC peer connection.
///
/// This deliberately leaves the previously verified video SDP/peer connection
/// untouched. Audio is created ONLY after the person at the station presses
/// the microphone ON button. No idle microphone capture or recording.
const _audioIceConfig = <String, dynamic>{
  'iceServers': [
    {'urls': 'stun:stun.l.google.com:19302'},
  ],
  'sdpSemantics': 'unified-plan',
};

RTCIceCandidate _decodeCandidate(Map<String, dynamic> json) =>
    RTCIceCandidate(
      json['candidate'] as String?,
      json['sdpMid'] as String?,
      (json['sdpMLineIndex'] as num?)?.toInt(),
    );

List<Map<String, dynamic>> _candidateMaps(Object? value) {
  if (value is! List) return const [];
  return value.whereType<Map>().map((e) =>
      Map<String, dynamic>.from(e)).toList();
}

class StationMicrophone {
  StationMicrophone({required this.onState});

  final void Function(bool capturing, String? message) onState;

  DocumentReference<Map<String, dynamic>>? _doc;
  RTCPeerConnection? _peer;
  MediaStream? _stream;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _watch;
  Future<void>? _startFuture;
  String? _epoch;
  bool _stopping = false;
  bool _settingAnswer = false;
  bool _remoteReady = false;
  int _candidateCount = 0;
  final List<RTCIceCandidate> _pendingCandidates = [];

  bool get isOn => _stream != null;

  Future<void> enable(String sessionId) async {
    if (_startFuture != null) {
      await _startFuture;
      return;
    }
    if (isOn) return;
    _stopping = false;
    final task = _start(sessionId);
    _startFuture = task;
    try {
      await task;
    } finally {
      _startFuture = null;
    }
  }

  Future<void> _start(String sessionId) async {
    final doc = RemoteControl.instance.session(sessionId);
    final epoch = DateTime.now().microsecondsSinceEpoch.toString();
    _doc = doc;
    _epoch = epoch;
    _candidateCount = 0;
    _remoteReady = false;
    _settingAnswer = false;
    _pendingCandidates.clear();

    try {
      final snapshot = await doc.get();
      final data = snapshot.data();
      if (data == null || data['state'] == 'ended') {
        throw StateError('영상 연결이 종료되어 마이크를 켤 수 없습니다');
      }

      // Clear stale audio offers/candidates from an earlier mic session.
      await doc.set({
        'audioEpoch': epoch,
        'audioState': 'preparing',
        'audioEnabled': false,
        'audioOffer': FieldValue.delete(),
        'audioAnswer': FieldValue.delete(),
        'audioStationCandidates': <Map<String, dynamic>>[],
        'audioViewerCandidates': <Map<String, dynamic>>[],
      }, SetOptions(merge: true));

      // A permission prompt may suspend the foreground app temporarily.
      // The user must approve microphone use on the station itself.
      final stream = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': false,
      });
      _stream = stream;
      if (_stopping) return;

      final peer = await createPeerConnection(_audioIceConfig);
      _peer = peer;
      peer.onIceCandidate = (candidate) {
        if (_stopping || _epoch != epoch || candidate.candidate == null) return;
        unawaited(doc.update({
          'audioStationCandidates': FieldValue.arrayUnion([candidate.toMap()]),
        }).catchError((Object error) {
          if (!_stopping) onState(true, '마이크 ICE 전송 오류: $error');
        }));
      };
      peer.onIceConnectionState = (state) {
        if (!_stopping && _epoch == epoch) {
          onState(isOn, '마이크 연결: ${state.toString().split('.').last}');
        }
      };
      await peer.addTrack(stream.getAudioTracks().first, stream);

      _watch = doc.snapshots().listen((snapshot) {
        if (_stopping || _epoch != epoch) return;
        final info = snapshot.data();
        if (info == null || info['audioEpoch'] != epoch) return;
        if (info['state'] == 'ended') {
          unawaited(disable());
          return;
        }
        final answer = info['audioAnswer'];
        if (answer is Map && !_remoteReady && !_settingAnswer) {
          _settingAnswer = true;
          unawaited(_acceptAnswer(Map<String, dynamic>.from(answer), epoch));
        }
        _acceptCandidates(info['audioViewerCandidates'], epoch);
      }, onError: (Object error) {
        if (!_stopping) onState(isOn, '마이크 시그널링 오류: $error');
      });

      final offer = await peer.createOffer();
      await peer.setLocalDescription(offer);
      if (_stopping) return;
      await doc.update({
        'audioOffer': {'type': offer.type, 'sdp': offer.sdp},
        'audioEnabled': true,
        'audioState': 'offered',
      });
      onState(true, '마이크 ON · 뷰어폰 오디오 연결 중');
    } catch (error) {
      await _closeLocal();
      try {
        await doc.set({
          'audioState': 'off',
          'audioEnabled': false,
        }, SetOptions(merge: true));
      } catch (_) {}
      onState(false, '마이크 시작 실패: $error');
      rethrow;
    }
  }

  Future<void> _acceptAnswer(Map<String, dynamic> answer, String epoch) async {
    try {
      final peer = _peer;
      if (_stopping || _epoch != epoch || peer == null) return;
      await peer.setRemoteDescription(
        RTCSessionDescription(answer['sdp'] as String?, answer['type'] as String?),
      );
      _remoteReady = true;
      final waiting = List<RTCIceCandidate>.of(_pendingCandidates);
      _pendingCandidates.clear();
      for (final candidate in waiting) {
        await _addCandidate(candidate);
      }
      onState(true, '거치폰 마이크 ON · 음성 전송 중');
    } catch (error) {
      if (!_stopping) onState(isOn, '마이크 응답 적용 오류: $error');
    } finally {
      _settingAnswer = false;
    }
  }

  void _acceptCandidates(Object? candidates, String epoch) {
    final maps = _candidateMaps(candidates);
    for (var i = _candidateCount; i < maps.length; i++) {
      if (_stopping || _epoch != epoch) return;
      final candidate = _decodeCandidate(maps[i]);
      if (_remoteReady) {
        unawaited(_addCandidate(candidate));
      } else {
        _pendingCandidates.add(candidate);
      }
    }
    _candidateCount = maps.length;
  }

  Future<void> _addCandidate(RTCIceCandidate candidate) async {
    try {
      await _peer?.addCandidate(candidate);
    } catch (error) {
      if (!_stopping) onState(isOn, '마이크 ICE 적용 오류: $error');
    }
  }

  /// Always releases the physical microphone before writing Firestore state.
  Future<void> disable() async {
    _stopping = true;
    final pending = _startFuture;
    if (pending != null) {
      try {
        await pending;
      } catch (_) {}
    }
    final doc = _doc;
    await _closeLocal();
    if (doc != null) {
      try {
        await doc.set({
          'audioEnabled': false,
          'audioState': 'off',
          'audioOffer': FieldValue.delete(),
          'audioAnswer': FieldValue.delete(),
        }, SetOptions(merge: true));
      } catch (error) {
        onState(false, '마이크는 꺼졌지만 서버 갱신 실패: $error');
        return;
      }
    }
    onState(false, null);
  }

  Future<void> _closeLocal() async {
    await _watch?.cancel();
    _watch = null;
    final stream = _stream;
    _stream = null;
    if (stream != null) {
      for (final track in stream.getTracks()) {
        await track.stop();
      }
      await stream.dispose();
    }
    final peer = _peer;
    _peer = null;
    if (peer != null) {
      await peer.close();
      await peer.dispose();
    }
    _doc = null;
    _epoch = null;
    _remoteReady = false;
    _candidateCount = 0;
    _pendingCandidates.clear();
  }
}

class ViewerAudio {
  ViewerAudio({required this.onState});

  final void Function(bool receiving, String? message) onState;

  DocumentReference<Map<String, dynamic>>? _doc;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _watch;
  RTCPeerConnection? _peer;
  RTCVideoRenderer? _playback;
  String? _epoch;
  bool _closed = true;
  bool _remoteReady = false;
  int _candidateCount = 0;
  final List<RTCIceCandidate> _pendingCandidates = [];
  Future<void> _processing = Future<void>.value();

  Future<void> attach(String videoSessionId) async {
    await detach();
    _closed = false;
    _doc = RemoteControl.instance.session(videoSessionId);
    _watch = _doc!.snapshots().listen((snapshot) {
      final data = snapshot.data();
      _processing = _processing.then((_) => _handle(data)).catchError(
        (Object error) {
          if (!_closed) onState(false, '오디오 연결 오류: $error');
        },
      );
    }, onError: (Object error) {
      if (!_closed) onState(false, '오디오 상태 수신 오류: $error');
    });
  }

  Future<void> _handle(Map<String, dynamic>? data) async {
    if (_closed) return;
    if (data == null || data['state'] == 'ended' ||
        data['audioEnabled'] != true ||
        data['audioState'] == 'off') {
      if (_peer != null) await _closePeer();
      onState(false, null);
      return;
    }
    final epoch = data['audioEpoch'] as String?;
    final offer = data['audioOffer'];
    if (epoch == null || offer is! Map) return;

    if (_epoch != epoch) {
      await _closePeer();
      if (_closed) return;
      await _answerOffer(epoch, Map<String, dynamic>.from(offer));
    }
    if (_closed || _epoch != epoch) return;
    await _addStationCandidates(data['audioStationCandidates']);
  }

  Future<void> _answerOffer(String epoch, Map<String, dynamic> offer) async {
    _epoch = epoch;
    _candidateCount = 0;
    _remoteReady = false;
    _pendingCandidates.clear();

    try {
      final playback = RTCVideoRenderer();
      await playback.initialize();
      playback.muted = false;
      _playback = playback;
      final peer = await createPeerConnection(_audioIceConfig);
      _peer = peer;

      peer.onTrack = (event) {
        if (_closed || _epoch != epoch || event.track.kind != 'audio') return;
        if (event.streams.isNotEmpty) {
          _playback?.srcObject = event.streams.first;
        }
        unawaited(Helper.setSpeakerphoneOn(true).catchError((Object _) {}));
        onState(true, '거치폰 소리 수신 중');
      };
      peer.onIceCandidate = (candidate) {
        if (_closed || _epoch != epoch || candidate.candidate == null) return;
        unawaited(_doc!.update({
          'audioViewerCandidates': FieldValue.arrayUnion([candidate.toMap()]),
        }).catchError((Object error) {
          if (!_closed) onState(false, '오디오 ICE 전송 오류: $error');
        }));
      };
      peer.onIceConnectionState = (state) {
        if (!_closed && _epoch == epoch) {
          onState(true, '오디오 연결: ${state.toString().split('.').last}');
        }
      };

      await peer.setRemoteDescription(
        RTCSessionDescription(offer['sdp'] as String?, offer['type'] as String?),
      );
      _remoteReady = true;
      final answer = await peer.createAnswer();
      await peer.setLocalDescription(answer);
      if (_closed || _epoch != epoch) return;
      await _doc!.update({
        'audioAnswer': {'type': answer.type, 'sdp': answer.sdp},
        'audioState': 'answer_ready',
      });
      onState(true, '거치폰 마이크 연결 중');
    } catch (error) {
      onState(false, '오디오 연결 실패: $error');
      await _closePeer();
    }
  }

  Future<void> _addStationCandidates(Object? candidates) async {
    final maps = _candidateMaps(candidates);
    for (var i = _candidateCount; i < maps.length; i++) {
      final candidate = _decodeCandidate(maps[i]);
      if (_remoteReady) {
        try {
          await _peer?.addCandidate(candidate);
        } catch (error) {
          if (!_closed) onState(false, '오디오 ICE 후보 오류: $error');
        }
      } else {
        _pendingCandidates.add(candidate);
      }
    }
    _candidateCount = maps.length;
    if (_remoteReady && _pendingCandidates.isNotEmpty) {
      final queue = List<RTCIceCandidate>.of(_pendingCandidates);
      _pendingCandidates.clear();
      for (final candidate in queue) {
        try {
          await _peer?.addCandidate(candidate);
        } catch (error) {
          if (!_closed) onState(false, '오디오 ICE 후보 오류: $error');
        }
      }
    }
  }

  Future<void> _closePeer() async {
    final peer = _peer;
    _peer = null;
    if (peer != null) {
      await peer.close();
      await peer.dispose();
    }
    final playback = _playback;
    _playback = null;
    if (playback != null) {
      playback.srcObject = null;
      await playback.dispose();
    }
    _epoch = null;
    _remoteReady = false;
    _candidateCount = 0;
    _pendingCandidates.clear();
  }

  Future<void> detach() async {
    _closed = true;
    await _watch?.cancel();
    _watch = null;
    await _processing.catchError((Object _) {});
    await _closePeer();
    _doc = null;
    onState(false, null);
  }
}
