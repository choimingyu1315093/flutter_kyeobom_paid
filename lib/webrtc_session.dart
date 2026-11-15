import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'remote_control.dart';

/// One on-demand WebRTC session. The microphone is opt-in and OFF by default.
///
/// Firebase transfers SDP/ICE messages only. Video is sent by WebRTC.
/// This prototype uses STUN but does not yet configure TURN, so connections
/// between some mobile/corporate networks may fail.
class HomeCamWebRtcSession {
  HomeCamWebRtcSession({
    required this.onStatus,
    this.onRemoteEnded,
    this.onMicrophoneState,
  });

  final void Function(String status) onStatus;
  final void Function()? onRemoteEnded;
  final void Function(bool active, String? error)? onMicrophoneState;

  static const Map<String, dynamic> _iceConfig = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
    ],
    'sdpSemantics': 'unified-plan',
  };

  RTCPeerConnection? _peer;
  MediaStream? _cameraStream;
  MediaStream? _microphoneStream;
  RTCRtpSender? _audioSender;
  RTCVideoRenderer? _remoteRenderer;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sessionSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _candidatesSub;
  final List<RTCIceCandidate> _candidateQueue = [];
  Timer? _viewerHeartbeat;
  Timer? _stationWatchdog;
  DateTime? _lastHeartbeatReceived;
  int? _lastHeartbeatVersion;

  String? _sessionId;
  bool _viewer = false;
  bool _remoteDescriptionSet = false;
  bool _answerInProgress = false;
  bool _closing = false;
  bool _audioNegotiated = false;
  bool? _desiredMicrophone;
  Future<void> _microphoneQueue = Future<void>.value();

  RTCVideoRenderer? get renderer => _remoteRenderer;
  bool get isRunning => _sessionId != null;
  String? get sessionId => _sessionId;

  DocumentReference<Map<String, dynamic>> _session(String id) =>
      RemoteControl.instance.session(id);

  /// Explicit station-side action that requests system permission, then
  /// releases capture immediately. No background microphone capture.
  static Future<void> prepareMicrophonePermission() async {
    final stream = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': false,
    });
    try {
      for (final track in stream.getTracks()) {
        await track.stop();
      }
    } finally {
      await stream.dispose();
    }
  }

  /// Viewer requests station audio. Capture starts only after station consent
  /// and remains released while micRequested is false.
  Future<void> requestMicrophone(bool enabled) async {
    final id = _sessionId;
    if (!_viewer || _closing || id == null) {
      throw StateError('실시간 연결을 먼저 시작해 주세요');
    }
    await _session(id).set({
      'micRequested': enabled,
    }, SetOptions(merge: true));
  }

  void _queueMicrophoneChange(bool enabled) {
    _microphoneQueue = _microphoneQueue.then((_) => _applyMicrophone(enabled))
        .catchError((Object error) {
      if (!_closing) onStatus('마이크 전환 오류: $error');
    });
  }

  Future<void> _applyMicrophone(bool enabled) async {
    final id = _sessionId;
    if (_closing || _viewer || id == null || !_audioNegotiated) return;
    final doc = _session(id);
    try {
      if (enabled && _microphoneStream == null) {
        final sender = _audioSender;
        if (sender == null) throw StateError('오디오 송출 채널 준비 실패');
        final stream = await navigator.mediaDevices.getUserMedia({
          'audio': {'echoCancellation': true, 'noiseSuppression': true},
          'video': false,
        });
        // A session may be stopped while the OS permission prompt is visible.
        if (_closing || _sessionId != id || _desiredMicrophone != true) {
          for (final track in stream.getTracks()) {
            await track.stop();
          }
          await stream.dispose();
          return;
        }
        try {
          await sender.replaceTrack(stream.getAudioTracks().first);
          _microphoneStream = stream;
        } catch (_) {
          for (final track in stream.getTracks()) {
            await track.stop();
          }
          await stream.dispose();
          rethrow;
        }
      } else if (!enabled) {
        await _audioSender?.replaceTrack(null);
        final stream = _microphoneStream;
        _microphoneStream = null;
        if (stream != null) {
          for (final track in stream.getTracks()) {
            await track.stop();
          }
          await stream.dispose();
        }
      }
      if (_closing || _sessionId != id) return;
      await doc.set({
        'micActive': enabled,
        'micError': FieldValue.delete(),
      }, SetOptions(merge: true));
      onMicrophoneState?.call(enabled, null);
    } catch (error) {
      if (_closing || _sessionId != id) return;
      await doc.set({
        'micActive': false,
        'micError': '거치폰 마이크 권한 또는 오디오 채널 오류: $error',
      }, SetOptions(merge: true));
      onMicrophoneState?.call(false, '$error');
    }
  }

  Future<void> _newPeer() async {
    _peer = await createPeerConnection(_iceConfig);
    _peer!.onIceConnectionState = (state) {
      if (!_closing) onStatus('ICE 연결: ' + state.toString().split('.').last);
    };
    _peer!.onConnectionState = (state) {
      if (!_closing) onStatus('WebRTC: ' + state.toString().split('.').last);
    };
    _peer!.onIceCandidate = (candidate) {
      final id = _sessionId;
      if (_closing || id == null || candidate.candidate == null) return;
      final collection = _viewer ? 'viewerCandidates' : 'stationCandidates';
      unawaited(_session(id).collection(collection).add(candidate.toMap())
          .then((_) {})
          .catchError((Object error) {
        if (!_closing) onStatus('ICE 저장 오류: $error');
      }));
    };
  }

  void _watchCandidates(String id, String remoteCollection) {
    _candidatesSub = _session(id).collection(remoteCollection)
        .snapshots().listen((snapshot) {
      for (final change in snapshot.docChanges) {
        if (change.type != DocumentChangeType.added) continue;
        final data = change.doc.data();
        if (data == null) continue;
        final candidate = RTCIceCandidate(
          data['candidate'] as String?,
          data['sdpMid'] as String?,
          (data['sdpMLineIndex'] as num?)?.toInt(),
        );
        if (!_remoteDescriptionSet) {
          _candidateQueue.add(candidate);
        } else {
          unawaited(_addCandidate(candidate));
        }
      }
    }, onError: (Object error) {
      if (!_closing) onStatus('ICE 수신 오류: $error');
    });
  }

  Future<void> _addCandidate(RTCIceCandidate candidate) async {
    try {
      await _peer?.addCandidate(candidate);
    } catch (error) {
      if (!_closing) onStatus('ICE 후보 적용 오류: $error');
    }
  }

  Future<void> _readyForRemoteIce() async {
    _remoteDescriptionSet = true;
    final waiting = List<RTCIceCandidate>.of(_candidateQueue);
    _candidateQueue.clear();
    for (final candidate in waiting) {
      await _addCandidate(candidate);
    }
  }

  /// Viewer creates a receive-only offer before notifying the station.
  Future<void> startViewer() async {
    await end(notifyRemote: false);
    _closing = false;
    _viewer = true;

    final doc = RemoteControl.instance.station.collection('sessions').doc();
    final id = doc.id;
    _sessionId = id;
    try {
      final renderer = RTCVideoRenderer();
      await renderer.initialize();
      _remoteRenderer = renderer;
      await _newPeer();

      _peer!.onTrack = (event) {
        if (_closing) return;
        if (event.track.kind == 'video' && event.streams.isNotEmpty) {
          _remoteRenderer?.srcObject = event.streams.first;
          onStatus('영상 트랙 수신 완료');
        }
      };
      _remoteRenderer?.muted = false;
      await _peer!.addTransceiver(
        kind: RTCRtpMediaType.RTCRtpMediaTypeVideo,
        init: RTCRtpTransceiverInit(
          direction: TransceiverDirection.RecvOnly,
        ),
      );
      await _peer!.addTransceiver(
        kind: RTCRtpMediaType.RTCRtpMediaTypeAudio,
        init: RTCRtpTransceiverInit(
          direction: TransceiverDirection.RecvOnly,
        ),
      );

      await doc.set({
        'state': 'creating_offer',
        'createdAt': FieldValue.serverTimestamp(),
        'viewerHeartbeatAt': FieldValue.serverTimestamp(),
        'micRequested': false,
        'micActive': false,
      });
      _watchCandidates(id, 'stationCandidates');
      _sessionSub = doc.snapshots().listen((snapshot) async {
        if (_closing || _sessionId != id) return;
        final data = snapshot.data();
        if (data == null) return;

        onMicrophoneState?.call(data['micActive'] == true,
            data['micError'] as String?);
        if (data['state'] == 'ended') {
          onStatus('거치폰에서 연결을 종료했습니다');
          onRemoteEnded?.call();
          return;
        }

        final answer = data['answer'];
        if (answer is! Map || _answerInProgress || _remoteDescriptionSet) {
          return;
        }
        _answerInProgress = true;
        try {
          await _peer!.setRemoteDescription(
            RTCSessionDescription(
              answer['sdp'] as String?,
              answer['type'] as String?,
            ),
          );
          await _readyForRemoteIce();
          onStatus('응답 수신 · 영상 연결 중');
        } catch (error) {
          onStatus('WebRTC 응답 오류: $error');
        } finally {
          _answerInProgress = false;
        }
      }, onError: (Object error) {
        if (!_closing) onStatus('시그널링 수신 오류: $error');
      });

      final offer = await _peer!.createOffer();
      await _peer!.setLocalDescription(offer);
      await doc.update({
        'offer': {'sdp': offer.sdp, 'type': offer.type},
        'state': 'offered',
      });
      await RemoteControl.instance.requestStart(id);
      _viewerHeartbeat = Timer.periodic(const Duration(seconds: 10), (_) {
        if (_closing || _sessionId != id) return;
        unawaited(doc.set({
          'viewerHeartbeatAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true)).catchError((Object error) {
          if (!_closing) onStatus('연결 유지 신호 오류: $error');
        }));
      });
      onStatus('거치폰의 연결 응답을 기다리는 중');
    } catch (_) {
      await end();
      rethrow;
    }
  }

  /// Station only accesses the camera after finding an authenticated offer.
  Future<void> startStation(String id) async {
    await end(notifyRemote: false);
    _closing = false;
    _viewer = false;
    _sessionId = id;

    try {
      final doc = _session(id);
      final data = (await doc.get()).data();
      final offer = data?['offer'];
      if (offer is! Map || data?['state'] == 'ended') {
        throw StateError('유효한 영상 연결 요청이 없습니다');
      }
      final createdAt = data?['createdAt'];
      if (createdAt is Timestamp &&
          DateTime.now().difference(createdAt.toDate()) >
              const Duration(seconds: 60)) {
        throw StateError('만료된 연결 요청입니다');
      }

      await _newPeer();
      _watchCandidates(id, 'viewerCandidates');
      _lastHeartbeatReceived = DateTime.now();
      _stationWatchdog = Timer.periodic(const Duration(seconds: 10), (_) {
        if (_closing || _sessionId != id) return;
        final last = _lastHeartbeatReceived;
        if (last != null && DateTime.now().difference(last) >
            const Duration(seconds: 45)) {
          _stationWatchdog?.cancel();
          onStatus('뷰어 연결이 끊어져 카메라를 종료합니다');
          onRemoteEnded?.call();
        }
      });
      _sessionSub = doc.snapshots().listen((snapshot) {
        if (_closing || _sessionId != id) return;
        final data = snapshot.data();
        if (data != null) {
          final desired = data['micRequested'] == true;
          if (_desiredMicrophone != desired) {
            _desiredMicrophone = desired;
            if (_audioNegotiated) _queueMicrophoneChange(desired);
          }
        }
        final heartbeat = data?['viewerHeartbeatAt'];
        if (heartbeat is Timestamp) {
          final time = heartbeat.toDate().millisecondsSinceEpoch;
          if (_lastHeartbeatVersion != time) {
            _lastHeartbeatVersion = time;
            if (DateTime.now().difference(heartbeat.toDate()) <
                const Duration(seconds: 45)) {
              _lastHeartbeatReceived = DateTime.now();
            }
          }
        }
        if (data?['state'] == 'ended') onRemoteEnded?.call();
      }, onError: (Object error) {
        if (!_closing) onStatus('시그널링 수신 오류: $error');
      });

      await _peer!.setRemoteDescription(
        RTCSessionDescription(
          offer['sdp'] as String?,
          offer['type'] as String?,
        ),
      );
      await _readyForRemoteIce();

      // The offer includes a receive-only audio m-line. Mark the matching
      // answer-side transceiver send-only even though no mic track exists yet.
      // A later replaceTrack can start/stop capture without renegotiation.
      final transceivers = await _peer!.getTransceivers();
      for (final transceiver in transceivers) {
        if (transceiver.receiver.track?.kind == 'audio') {
          await transceiver.setDirection(TransceiverDirection.SendOnly);
          _audioSender = transceiver.sender;
          break;
        }
      }

      _cameraStream = await navigator.mediaDevices.getUserMedia({
        'audio': false,
        'video': {
          'facingMode': 'environment',
          'width': {'ideal': 1280},
          'height': {'ideal': 720},
          'frameRate': {'ideal': 20},
        },
      });
      for (final track in _cameraStream!.getVideoTracks()) {
        await _peer!.addTrack(track, _cameraStream!);
      }
      // Associate future audio with the same video stream on the remote side.
      await _audioSender?.setStreams([_cameraStream!]);

      final answer = await _peer!.createAnswer();
      await _peer!.setLocalDescription(answer);
      await doc.update({
        'answer': {'sdp': answer.sdp, 'type': answer.type},
        'state': 'answer_ready',
      });
      _audioNegotiated = true;
      if (_desiredMicrophone == true) _queueMicrophoneChange(true);
      onStatus('후면 카메라 송출 중 · 마이크 OFF');
    } catch (_) {
      await end();
      rethrow;
    }
  }

  /// Releases camera, renderer, peers and Firestore listeners.
  Future<void> end({bool notifyRemote = true}) async {
    final id = _sessionId;
    if (id == null && _peer == null && _remoteRenderer == null) return;

    _closing = true;
    _sessionId = null;
    await _sessionSub?.cancel();
    _sessionSub = null;
    await _candidatesSub?.cancel();
    _candidatesSub = null;
    _candidateQueue.clear();
    _viewerHeartbeat?.cancel();
    _viewerHeartbeat = null;
    _stationWatchdog?.cancel();
    _stationWatchdog = null;
    _lastHeartbeatReceived = null;
    _lastHeartbeatVersion = null;
    _remoteDescriptionSet = false;
    _answerInProgress = false;
    _audioNegotiated = false;
    _desiredMicrophone = null;

    // Shut down the audio sender before disposal, regardless of signaling.
    try {
      await _audioSender?.replaceTrack(null);
    } catch (_) {}
    _audioSender = null;
    final microphone = _microphoneStream;
    _microphoneStream = null;
    if (microphone != null) {
      for (final track in microphone.getTracks()) {
        await track.stop();
      }
      await microphone.dispose();
    }

    final stream = _cameraStream;
    _cameraStream = null;
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

    final renderer = _remoteRenderer;
    _remoteRenderer = null;
    if (renderer != null) {
      renderer.srcObject = null;
      await renderer.dispose();
    }

    if (notifyRemote && id != null) {
      await _session(id).set({
        'micRequested': false,
        'micActive': false,
        'state': 'ended',
        'endedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
  }
}
