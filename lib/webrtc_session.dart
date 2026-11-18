import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'remote_control.dart';
import 'homecam_cost_policy.dart';
import 'homecam_video_quality.dart';
import 'homecam_recovery_policy.dart';

/// One on-demand, video-only WebRTC session.
///
/// Firebase transfers SDP/ICE messages only. Video is sent by WebRTC.
/// This prototype uses STUN but does not yet configure TURN, so connections
/// between some mobile/corporate networks may fail.
class HomeCamWebRtcSession {
  HomeCamWebRtcSession({
    required this.onStatus,
    this.onRemoteEnded,
    this.onConnectionLost,
    this.onConnectionEstablished,
  });

  final void Function(String status) onStatus;
  final void Function()? onRemoteEnded;
  final void Function()? onConnectionLost;
  final void Function()? onConnectionEstablished;

  static const Map<String, dynamic> _iceConfig =
      HomeCamCostPolicy.directIceConfig;

  RTCPeerConnection? _peer;
  MediaStream? _cameraStream;
  RTCVideoRenderer? _remoteRenderer;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sessionSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _candidatesSub;
  final List<RTCIceCandidate> _candidateQueue = [];
  RTCDataChannel? _heartbeatChannel;
  Timer? _viewerHeartbeat;
  Timer? _stationWatchdog;
  DateTime? _lastHeartbeatReceived;
  int? _lastLegacyHeartbeatVersion;
  DateTime? _viewerStartedAt;
  DateTime? _lastDirectAck;
  DateTime? _lastFirestoreFallback;
  bool _directHeartbeatConfirmed = false;

  String? _sessionId;
  bool _viewer = false;
  bool _remoteDescriptionSet = false;
  bool _answerInProgress = false;
  bool _closing = false;
  bool _reducedVideo = false;
  bool _viewerTransportConnected = false;
  Timer? _lostConnectionTimer;
  Timer? _initialConnectionTimer;
  Timer? _qualityStatsTimer;

  Future<void> _logActualVideoQuality() async {
    if (!kDebugMode || _closing || _peer == null) return;
    try {
      final reports = await _peer!.getStats();
      for (final report in reports) {
        if (report.type != (_viewer ? 'inbound-rtp' : 'outbound-rtp')) {
          continue;
        }
        final values = report.values;
        if (values['kind'] != 'video' && values['mediaType'] != 'video') {
          continue;
        }
        final width = values['frameWidth'];
        final height = values['frameHeight'];
        final fps = values['framesPerSecond'];
        if (width != null && height != null) {
          debugPrint('[kyeobom/video] actual ${_viewer ? "viewer" : "station"} '
              '${width}x${height} fps=$fps');
        }
      }
    } catch (error) {
      debugPrint('[kyeobom/video] stats unavailable: $error');
    }
  }

  void _startQualityStatsLogging() {
    if (!kDebugMode || _qualityStatsTimer != null) return;
    _qualityStatsTimer = Timer.periodic(
      const Duration(seconds: 20),
      (_) => unawaited(_logActualVideoQuality()),
    );
  }

  void _watchConnectionState(String state) {
    if (_closing || !_viewer) return;
    final status = state.toLowerCase();
    final failed = status.endsWith('failed') ||
        status.endsWith('disconnected');
    final connected = status.endsWith('connected') &&
        !status.endsWith('disconnected');
    if (connected) {
      _viewerTransportConnected = true;
      _startQualityStatsLogging();
      _lostConnectionTimer?.cancel();
      _lostConnectionTimer = null;
      _initialConnectionTimer?.cancel();
      _initialConnectionTimer = null;
      onConnectionEstablished?.call();
    } else if (failed && _viewerTransportConnected &&
        _lostConnectionTimer == null) {
      // Mobile networks can briefly disconnect while switching Wi-Fi/LTE.
      final id = _sessionId;
      _lostConnectionTimer = Timer(
        HomeCamRecoveryPolicy.disconnectedGrace,
        () {
          _lostConnectionTimer = null;
          if (!_closing && _viewer && _sessionId == id) {
            onConnectionLost?.call();
          }
        },
      );
    }
  }

  RTCVideoRenderer? get renderer => _remoteRenderer;
  bool get isRunning => _sessionId != null;
  String? get sessionId => _sessionId;
  bool get isVideoReduced => _reducedVideo;

  DocumentReference<Map<String, dynamic>> _session(String id) =>
      RemoteControl.instance.session(id);

  Future<void> _newPeer() async {
    _peer = await createPeerConnection(_iceConfig);
    _peer!.onIceConnectionState = (state) {
      if (!_closing) onStatus('ICE 연결: ${state.toString().split('.').last}');
      _watchConnectionState(state.toString());
    };
    _peer!.onConnectionState = (state) {
      if (!_closing) onStatus('WebRTC: ${state.toString().split('.').last}');
      _watchConnectionState(state.toString());
    };
    _peer!.onDataChannel = (channel) {
      final id = _sessionId;
      if (id != null) _receiveStationHeartbeat(channel, id);
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

  /// The viewer sends small session-scoped heartbeats directly over the
  /// existing WebRTC peer. No per-second or per-minute Firestore writes.
  Future<void> _sendViewerHeartbeat() async {
    final id = _sessionId;
    final channel = _heartbeatChannel;
    if (_closing || !_viewer || id == null ||
        channel == null ||
        channel.state != RTCDataChannelState.RTCDataChannelOpen) {
      return;
    }
    try {
      await channel.send(RTCDataChannelMessage(HomeCamCostPolicy.heartbeat(id)));
    } catch (error) {
      if (!_closing && _sessionId == id) {
        onStatus('직접 연결 유지 신호 오류: $error');
      }
    }
  }

  /// Legacy versions do not acknowledge the new DataChannel heartbeat.
  /// Write Firestore ONLY after the direct channel has failed to confirm
  /// liveness, with a longer interval than the original 10-second writes.
  Future<void> _maybeSendFirestoreFallback(String id) async {
    if (_closing || !_viewer || _sessionId != id) return;
    final started = _viewerStartedAt;
    if (started == null) return;
    final now = DateTime.now();
    if (!HomeCamCostPolicy.shouldWriteFallback(
      now: now,
      startedAt: started,
      lastDirectAcknowledgement: _lastDirectAck,
      lastFallbackWrite: _lastFirestoreFallback,
    )) {
      return;
    }
    // Reserve the slot first so concurrent timer calls never duplicate writes.
    if (_lastFirestoreFallback == null && kDebugMode) {
      debugPrint('[kyeobom/cost] Firestore fallback active (legacy/no ACK)');
    }
    _lastFirestoreFallback = now;
    try {
      await _session(id).set({
        'viewerHeartbeatAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (error) {
      if (!_closing && _sessionId == id) {
        onStatus('호환성 연결 유지 신호 오류: $error');
      }
    }
  }

  void _receiveStationHeartbeat(RTCDataChannel channel, String id) {
    if (_closing || _viewer || _sessionId != id ||
        channel.label != HomeCamCostPolicy.dataChannelLabel) {
      return;
    }
    _heartbeatChannel = channel;
    channel.onMessage = (message) {
      if (_closing || _viewer || _sessionId != id || message.isBinary) return;
      if (HomeCamCostPolicy.isHeartbeatForSession(message.text, id)) {
        _lastHeartbeatReceived = DateTime.now();
        if (!_directHeartbeatConfirmed) {
          _directHeartbeatConfirmed = true;
          if (kDebugMode) {
            debugPrint('[kyeobom/cost] station P2P heartbeat received');
          }
          onStatus('직접 연결 유지 정상 · 서버 반복 쓰기 없음');
        }
        // Acknowledge receipt to let the viewer suppress legacy Firestore
        // fallback, including on reconnect after temporary packet loss.
        if (channel.state == RTCDataChannelState.RTCDataChannelOpen) {
          unawaited(channel.send(
            RTCDataChannelMessage(HomeCamCostPolicy.acknowledge(id)),
          ).catchError((Object error) {
            if (!_closing) onStatus('직접 연결 확인 응답 오류: $error');
          }));
        }
      }
    };
    // The watchdog still protects the station if this channel never opens,
    // stops receiving, or the viewer is force-killed without Firestore cleanup.
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
    _viewerStartedAt = DateTime.now();
    _lastDirectAck = null;
    _lastFirestoreFallback = null;
    _viewerTransportConnected = false;
    _lostConnectionTimer?.cancel();
    _initialConnectionTimer?.cancel();

    final doc = RemoteControl.instance.station.collection('sessions').doc();
    final id = doc.id;
    _sessionId = id;
    try {
      final renderer = RTCVideoRenderer();
      await renderer.initialize();
      _remoteRenderer = renderer;
      await _newPeer();

      _peer!.onTrack = (event) {
        if (_closing || event.streams.isEmpty) return;
        _remoteRenderer?.srcObject = event.streams.first;
        onStatus('영상 트랙 수신 완료');
      };
      await _peer!.addTransceiver(
        kind: RTCRtpMediaType.RTCRtpMediaTypeVideo,
        init: RTCRtpTransceiverInit(
          direction: TransceiverDirection.RecvOnly,
        ),
      );
      // Create BEFORE offer so SCTP/data-channel negotiation happens together
      // with the proven video peer, without additional peers or TURN servers.
      final channel = await _peer!.createDataChannel(
        HomeCamCostPolicy.dataChannelLabel,
        RTCDataChannelInit(),
      );
      _heartbeatChannel = channel;
      channel.onMessage = (message) {
        if (_closing || !_viewer || _sessionId != id || message.isBinary) {
          return;
        }
        if (HomeCamCostPolicy.isAcknowledgementForSession(message.text, id)) {
          if (_lastDirectAck == null && kDebugMode) {
            debugPrint('[kyeobom/cost] viewer direct ACK (no DB keepalive writes)');
          }
          _lastDirectAck = DateTime.now();
        }
      };
      channel.onDataChannelState = (state) {
        if (!_closing && _sessionId == id &&
            state == RTCDataChannelState.RTCDataChannelOpen) {
          unawaited(_sendViewerHeartbeat());
        }
      };

      await doc.set({
        'state': 'creating_offer',
        'createdAt': FieldValue.serverTimestamp(),
      });
      _watchCandidates(id, 'stationCandidates');
      _sessionSub = doc.snapshots().listen((snapshot) async {
        if (_closing || _sessionId != id) return;
        final data = snapshot.data();
        if (data == null) return;

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
      _viewerHeartbeat = Timer.periodic(
        HomeCamCostPolicy.heartbeatPeriod,
        (_) {
          if (!_closing && _sessionId == id) {
            unawaited(_sendViewerHeartbeat());
            unawaited(_maybeSendFirestoreFallback(id));
          }
        },
      );
      _initialConnectionTimer = Timer(
        HomeCamRecoveryPolicy.initialConnectionTimeout,
        () {
          if (!_closing && _viewer && _sessionId == id &&
              !_viewerTransportConnected) {
            onStatus('연결 시간 초과 · 자동 재연결 준비');
            onConnectionLost?.call();
          }
        },
      );
      onStatus('거치폰의 연결 응답을 기다리는 중');
    } catch (_) {
      await end();
      rethrow;
    }
  }

  /// Station only accesses the camera after finding an authenticated offer.
  Future<void> startStation(String id, {bool reducedQuality = false}) async {
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
      _directHeartbeatConfirmed = false;
      _lastLegacyHeartbeatVersion = null;
      _stationWatchdog = Timer.periodic(
        HomeCamCostPolicy.watchdogPeriod,
        (_) {
          if (_closing || _sessionId != id) return;
          final last = _lastHeartbeatReceived;
          if (last != null &&
              HomeCamCostPolicy.stationTimedOut(last, DateTime.now())) {
            _stationWatchdog?.cancel();
            onStatus('뷰어 연결 유지 신호 없음 · 카메라 종료');
            onRemoteEnded?.call();
          }
        },
      );
      _sessionSub = doc.snapshots().listen((snapshot) {
        if (_closing || _sessionId != id) return;
        final data = snapshot.data();
        // Accept the OLD app's Firestore keepalive if it has not updated yet.
        // New clients send P2P heartbeats, so this generates no extra writes.
        final legacy = data?['viewerHeartbeatAt'];
        if (legacy is Timestamp) {
          final version = legacy.toDate().millisecondsSinceEpoch;
          if (version != _lastLegacyHeartbeatVersion) {
            _lastLegacyHeartbeatVersion = version;
            if (DateTime.now().difference(legacy.toDate()) <
                HomeCamCostPolicy.stationTimeout) {
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

      var usedFallback = reducedQuality;
      if (reducedQuality) {
        // Device health takes precedence over HD while battery/heat is unsafe.
        _cameraStream = await navigator.mediaDevices.getUserMedia({
          'audio': false,
          'video': {
            'facingMode': 'environment',
            'width': {'ideal': 640},
            'height': {'ideal': 360},
            'frameRate': {'ideal': 12},
          },
        });
      } else {
        try {
          _cameraStream = await navigator.mediaDevices.getUserMedia(
            HomeCamVideoQuality.cameraConstraints(),
          );
        } catch (error) {
          if (!HomeCamVideoQuality.canFallbackFor(error)) rethrow;
          usedFallback = true;
          _cameraStream = await navigator.mediaDevices.getUserMedia(
            HomeCamVideoQuality.cameraConstraints(fallback: true),
          );
        }
      }
      _reducedVideo = reducedQuality;
      for (final track in _cameraStream!.getVideoTracks()) {
        final sender = await _peer!.addTrack(track, _cameraStream!);
        // Best effort: encoders may reject these parameters on some hardware.
        // Failure must never prevent the existing working HD video connection.
        try {
          final params = sender.parameters;
          params.degradationPreference = RTCDegradationPreference.BALANCED;
          for (final encoding in params.encodings ?? <RTCRtpEncoding>[]) {
            encoding.maxBitrate = usedFallback
                ? HomeCamVideoQuality.fallbackBitrateBps
                : HomeCamVideoQuality.preferredBitrateBps;
            encoding.maxFramerate = usedFallback
                ? HomeCamVideoQuality.fallbackFps
                : HomeCamVideoQuality.preferredFps;
          }
          await sender.setParameters(params);
        } catch (error) {
          if (kDebugMode) {
            debugPrint('[kyeobom/video] encoder preferences ignored: $error');
          }
        }
      }
      if (kDebugMode) {
        debugPrint(usedFallback
            ? '[kyeobom/video] 720p fallback requested'
            : '[kyeobom/video] 1080p preferred requested');
      }

      final answer = await _peer!.createAnswer();
      await _peer!.setLocalDescription(answer);
      await doc.update({
        'answer': {'sdp': answer.sdp, 'type': answer.type},
        'state': 'answer_ready',
      });
      _startQualityStatsLogging();
      onStatus('후면 카메라 송출 중 · 마이크 OFF');
    } catch (_) {
      await end();
      rethrow;
    }
  }

  /// Best-effort thermal/battery quality adjustment while a session is live.
  /// A device may reject new camera constraints; never tear down working video.
  Future<bool> setReducedQuality(bool reduced) async {
    final stream = _cameraStream;
    if (_viewer || _closing || stream == null) return false;
    if (_reducedVideo == reduced) return true;
    final tracks = stream.getVideoTracks();
    if (tracks.isEmpty) return false;
    try {
      for (final track in tracks) {
        await track.applyConstraints({
          'width': {'ideal': reduced ? 640 : 1280},
          'height': {'ideal': reduced ? 360 : 720},
          'frameRate': {'ideal': reduced ? 12 : 20},
        });
      }
      if (_closing || _cameraStream != stream) return false;
      _reducedVideo = reduced;
      return true;
    } catch (error) {
      // On native devices where camera capture constraints cannot be updated,
      // attempt WebRTC track adaptation without recreating the peer/camera.
      try {
        for (final track in tracks) {
          await track.adaptRes(reduced ? 640 : 1280, reduced ? 360 : 720);
        }
        if (_closing || _cameraStream != stream) return false;
        _reducedVideo = reduced;
        return true;
      } catch (_) {
        // Existing video and audio must survive an unsupported operation.
        if (kDebugMode) {
          debugPrint('[kyeobom/health] Video adaptation unsupported: $error');
        }
        return false;
      }
    }
  }

  /// Releases camera, renderer, peers and Firestore listeners.
  Future<void> end({bool notifyRemote = true}) async {
    final id = _sessionId;
    if (id == null && _peer == null && _remoteRenderer == null) return;

    _closing = true;
    _sessionId = null;
    _reducedVideo = false;
    _viewerTransportConnected = false;
    _qualityStatsTimer?.cancel();
    _qualityStatsTimer = null;
    _lostConnectionTimer?.cancel();
    _lostConnectionTimer = null;
    _initialConnectionTimer?.cancel();
    _initialConnectionTimer = null;
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
    _lastLegacyHeartbeatVersion = null;
    _viewerStartedAt = null;
    _lastDirectAck = null;
    _lastFirestoreFallback = null;
    _directHeartbeatConfirmed = false;
    final channel = _heartbeatChannel;
    _heartbeatChannel = null;
    if (channel != null) {
      channel.onMessage = null;
      channel.onDataChannelState = null;
      try {
        await channel.close();
      } catch (_) {
        // Peer shutdown below always releases the native channel.
      }
    }
    _remoteDescriptionSet = false;
    _answerInProgress = false;

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
        'state': 'ended',
        'endedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
  }
}
