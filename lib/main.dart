import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'remote_control.dart';
import 'webrtc_session.dart';
import 'audio_session.dart';
import 'video_orientation.dart';
import 'viewer_video_controls.dart';
import 'viewer_video_controls.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await RemoteControl.instance.initialize();
  } catch (_) {
    // A clear setup prompt is shown below when Firebase is unavailable.
  }
  runApp(const HomeCameraApp());
}

class HomeCameraApp extends StatelessWidget {
  const HomeCameraApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'HomeCamera',
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark(useMaterial3: true),
        routes: {'/roles': (_) => const RoleSelectionScreen()},
        home: Firebase.apps.isEmpty
            ? const Scaffold(
                body: Center(
                  child: Text('Firebase 설정 필요: flutterfire configure 후 앱을 재빌드하세요'),
                ),
              )
            : FirebaseAuth.instance.currentUser == null
                ? const LoginScreen()
                : const RoleSelectionScreen(),
      );
}

class RoleSelectionScreen extends StatelessWidget {
  const RoleSelectionScreen({super.key});

  Future<void> _openStation(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('홈캠 대기 모드가 시작됩니다.'),
        content: const Text(
          '화면은 어둡게 유지되며 자동으로 잠기지 않습니다.\n\n'
          '안정적인 원격 연결을 위해 충전기를 연결하고 앱을 실행 상태로 유지해 주세요.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('대기 시작'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const StationScreen()),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('HomeCamera · 실시간 보기 P3')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('이 기기의 역할을 선택하세요',
                  style: TextStyle(fontSize: 22)),
              const SizedBox(height: 24),
              FilledButton.icon(
                icon: const Icon(Icons.videocam_off),
                label: const Text('거치폰 · 카메라 대기'),
                onPressed: () => _openStation(context),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                icon: const Icon(Icons.visibility),
                label: const Text('뷰어폰 · 실시간 보기'),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                      builder: (_) => const ViewerScreen()),
                ),
              ),
            ]),
          ),
        ),
      );
}

class StationScreen extends StatefulWidget {
  const StationScreen({super.key});

  @override
  State<StationScreen> createState() => _StationScreenState();
}

class _StationScreenState extends State<StationScreen>
    with WidgetsBindingObserver {
  static const _screen = MethodChannel('home_camera/screen');
  late final HomeCamWebRtcSession _rtc;
  late final StationMicrophone _microphone;
  late final Future<void> _micSettingsReady;
  final SharedPreferencesAsync _micPreferences = SharedPreferencesAsync();
  static const _micAutoKey = 'station_auto_microphone_when_viewing_v1';
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _commands;
  Future<void> _commandQueue = Future<void>.value();

  String _status = '연결 대기 준비 중';
  String? _lastCommandId;
  bool _foreground = true;
  bool _streaming = false;
  bool _leaving = false;
  bool _microphoneOn = false;
  bool _microphoneBusy = false;
  bool _micAutoEnabled = false;
  bool _micSettingsBusy = false;
  String? _microphoneMessage;

  @override
  void initState() {
    super.initState();
    _microphone = StationMicrophone(onState: (capturing, message) {
      if (!mounted) return;
      setState(() {
        _microphoneOn = capturing;
        _microphoneMessage = message;
      });
    });
    _micSettingsReady = _loadMicSetting();
    _rtc = HomeCamWebRtcSession(
      onStatus: (value) {
        if (mounted) setState(() => _status = value);
      },
      onRemoteEnded: () {
        _commandQueue = _commandQueue.then((_) => _finishStream()).catchError(
          (Object error) {
            if (mounted) setState(() => _status = '종료 처리 오류: $error');
          },
        );
      },
    );
    WidgetsBinding.instance.addObserver(this);
    unawaited(_enterWaiting());
    unawaited(_connectCommands());
  }

  Future<void> _enterWaiting() async {
    try {
      await _screen.invokeMethod<void>('enableWaitingMode');
      if (mounted && !_streaming) {
        setState(() => _status = '연결 대기 중');
      }
    } catch (error) {
      if (mounted) setState(() => _status = '화면 유지 오류: $error');
    }
  }

  Future<void> _loadMicSetting() async {
    try {
      final enabled = await _micPreferences.getBool(_micAutoKey) ?? false;
      if (mounted) setState(() => _micAutoEnabled = enabled);
    } catch (error) {
      if (mounted) {
        setState(() => _microphoneMessage = '마이크 설정 읽기 실패: $error');
      }
    }
  }

  /// This consent is configured on the station device while a person is there.
  /// Permission capture is stopped immediately; no idle microphone remains on.
  Future<void> _setMicAutoEnabled(bool enabled) async {
    if (_micSettingsBusy || _streaming || _leaving) return;
    setState(() => _micSettingsBusy = true);
    try {
      if (enabled) {
        await StationMicrophone.preparePermission();
      }
      await _micPreferences.setBool(_micAutoKey, enabled);
      if (mounted) {
        setState(() {
          _micAutoEnabled = enabled;
          _microphoneMessage = enabled
              ? '원격 영상 시작 시 이 거치폰 마이크가 자동으로 켜집니다'
              : '원격 마이크 자동 시작을 해제했습니다';
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => _microphoneMessage = '거치폰 마이크 권한 오류: $error');
      }
    } finally {
      if (mounted) setState(() => _micSettingsBusy = false);
    }
  }

  Future<void> _connectCommands() async {
    try {
      await _micSettingsReady;
      await RemoteControl.instance.startStation();
      if (!mounted || _leaving) return;
      _commands = RemoteControl.instance.watch().listen((snapshot) {
        final data = snapshot.data();
        if (!mounted || _leaving || data == null) return;
        final id = data['commandId'] as String? ?? '';
        if (id.isEmpty || id == _lastCommandId) return;
        _lastCommandId = id;
        _commandQueue = _commandQueue.then((_) => _handleCommand(data))
            .catchError((Object error) {
          if (mounted) setState(() => _status = '원격 요청 오류: $error');
        });
      }, onError: (Object error) {
        if (mounted) setState(() => _status = 'Firebase 연결 오류: $error');
      });
    } catch (error) {
      if (mounted) setState(() => _status = 'Firebase 연결 오류: $error');
    }
  }

  Future<void> _handleCommand(Map<String, dynamic> data) async {
    if (!mounted || _leaving) return;
    final command = data['command'] as String? ?? 'idle';
    final id = data['commandId'] as String? ?? '';
    final sessionId = data['sessionId'] as String? ?? '';

    if (command == 'stop') {
      // Ignore delayed stop commands from an older session.
      if (sessionId != _rtc.sessionId) return;
      await _finishStream();
      await RemoteControl.instance.acknowledge(id, 'camera_off');
      return;
    }
    if (command != 'start' || !_foreground) return;

    final requestedAt = data['updatedAt'];
    if (requestedAt is Timestamp &&
        DateTime.now().difference(requestedAt.toDate()) >
            const Duration(seconds: 60)) {
      await RemoteControl.instance.acknowledge(id, 'expired_request');
      return;
    }
    if (sessionId.isEmpty) return;

    try {
      if (mounted) setState(() => _status = '원격 연결 준비 중');
      if (_rtc.isRunning && _rtc.sessionId != sessionId) {
        // Always release any audio from the previous viewer first.
        await _microphone.disable();
        await _rtc.end();
      }
      await _rtc.startStation(sessionId);
      if (!mounted || _leaving || !_foreground) {
        await _rtc.end();
        return;
      }
      setState(() {
        _streaming = true;
        _status = '후면 카메라 송출 중 · 마이크 OFF';
      });
      await RemoteControl.instance.acknowledge(id, 'answer_ready');
      if (_micAutoEnabled && _streaming && _rtc.sessionId == sessionId) {
        // Station-side opt-in only; viewer has no microphone capture.
        // Audio failure is isolated and cannot tear down the video peer.
        unawaited(_toggleStationMicrophone());
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _streaming = false;
          _status = '송출 시작 실패: $error';
        });
      }
      await RemoteControl.instance.acknowledge(id, 'error: $error');
    }
  }

  Future<void> _toggleStationMicrophone() async {
    if (_microphoneBusy || _leaving || !_streaming) return;
    final sessionId = _rtc.sessionId;
    if (sessionId == null) return;
    setState(() => _microphoneBusy = true);
    try {
      if (_microphone.isOn) {
        await _microphone.disable();
      } else {
        await _microphone.enable(sessionId);
      }
    } catch (error) {
      if (mounted) setState(() => _microphoneMessage = '마이크 오류: $error');
    } finally {
      if (mounted) setState(() => _microphoneBusy = false);
    }
  }

  Future<void> _finishStream() async {
    await _microphone.disable();
    if (_rtc.isRunning) await _rtc.end();
    if (mounted && !_leaving) {
      setState(() {
        _streaming = false;
        _microphoneOn = false;
        _microphoneMessage = null;
        _status = '연결 대기 중';
      });
    }
  }

  Future<void> _leave() async {
    if (_leaving) return;
    setState(() => _leaving = true);
    await _commands?.cancel();
    try {
      await _microphone.disable();
      await _rtc.end();
      await RemoteControl.instance.stopStation();
    } finally {
      if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    // iOS microphone permission sheet may temporarily set "inactive".
    // Stop only when actually backgrounded.
    final background = state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached;
    if (background && !_leaving) {
      if (mounted) {
        setState(() => _status = '앱 비활성화 · 영상 송출 중단');
      }
      _commandQueue = _commandQueue.then((_) => _finishStream()).catchError(
        (Object error) {
          if (mounted) setState(() => _status = '종료 오류: $error');
        },
      );
    } else if (_foreground && !_streaming && mounted) {
      setState(() => _status = '연결 대기 중');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_commands?.cancel());
    unawaited(_microphone.disable());
    unawaited(_rtc.end(notifyRemote: !_leaving));
    if (!_leaving) unawaited(RemoteControl.instance.stopStation());
    unawaited(_screen.invokeMethod<void>('disableWaitingMode'));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: _leaving,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) unawaited(_leave());
        },
        child: Scaffold(
          backgroundColor: Colors.black,
          body: SafeArea(
            child: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(_streaming ? Icons.videocam : Icons.videocam_off_outlined,
                    size: 38, color: Colors.white38),
                const SizedBox(height: 14),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(_status,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white54)),
                ),
                const SizedBox(height: 12),
                Text(
                  _streaming
                      ? '후면 카메라 ON · 마이크 ${_microphoneOn ? "ON" : "OFF"} · 녹화 OFF'
                      : '카메라 OFF · 마이크 OFF · 녹화 OFF',
                  style: const TextStyle(color: Colors.white30, fontSize: 12),
                ),
                if (!_streaming) ...[
                  const SizedBox(height: 12),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: SwitchListTile.adaptive(
                      title: const Text('실시간 보기 시 거치폰 마이크 자동 켜기',
                          style: TextStyle(fontSize: 14)),
                      subtitle: const Text(
                          '거치폰 주변 소리만 전송 · 대기 중 마이크 OFF',
                          style: TextStyle(fontSize: 11)),
                      value: _micAutoEnabled,
                      onChanged: _micSettingsBusy || _leaving
                          ? null
                          : (enabled) => unawaited(_setMicAutoEnabled(enabled)),
                    ),
                  ),
                ],
                if (_streaming) ...[
                  const SizedBox(height: 14),
                  OutlinedButton.icon(
                    onPressed: _microphoneBusy ? null : _toggleStationMicrophone,
                    icon: Icon(_microphoneOn ? Icons.mic : Icons.mic_off),
                    label: Text(_microphoneBusy
                        ? '마이크 전환 중'
                        : _microphoneOn ? '거치폰 마이크 끄기' : '거치폰 마이크 켜기'),
                  ),
                  if (_microphoneMessage != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(_microphoneMessage!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white54, fontSize: 12)),
                    ),
                ],
                const SizedBox(height: 28),
                TextButton(
                  onPressed: _leaving ? null : _leave,
                  child: const Text('대기 종료'),
                ),
              ]),
            ),
          ),
        ),
      );
}

class ViewerScreen extends StatefulWidget {
  const ViewerScreen({super.key});

  @override
  State<ViewerScreen> createState() => _ViewerScreenState();
}

class _ViewerScreenState extends State<ViewerScreen>
    with WidgetsBindingObserver {
  late final HomeCamWebRtcSession _rtc;
  late final ViewerAudio _viewerAudio;
  bool _remoteAudioOn = false;
  String? _remoteAudioMessage;
  String _status = '실시간 보기를 누르면 원격 연결합니다';
  bool _busy = false;
  bool _watching = false;
  bool _leaving = false;
  bool _landscapeLocked = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _viewerAudio = ViewerAudio(onState: (receiving, message) {
      if (!mounted) return;
      if (_remoteAudioOn != receiving || _remoteAudioMessage != message) {
        setState(() {
          _remoteAudioOn = receiving;
          _remoteAudioMessage = message;
        });
      }
    });
    _rtc = HomeCamWebRtcSession(
      onStatus: (value) {
        if (mounted) setState(() => _status = value);
      },
      onRemoteEnded: () => unawaited(_stop(notifyRemote: false)),
    );
  }

  /// Enter landscape only when the user explicitly starts live viewing.
  Future<void> _enterLandscape() async {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
    ]);
    _landscapeLocked = true;
  }

  /// Return to portrait first, then release the orientation restriction.
  /// No permanent phone setting is changed.
  Future<void> _restoreOrientation() async {
    if (!_landscapeLocked) return;
    _landscapeLocked = false;
    try {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
      ]);
      await Future<void>.delayed(const Duration(milliseconds: 250));
    } finally {
      await SystemChrome.setPreferredOrientations([]);
    }
  }

  Future<void> _start() async {
    if (_busy || _watching || _leaving) return;
    setState(() {
      _busy = true;
      _status = '거치폰 연결 요청 중';
    });

    try {
      await _rtc.startViewer();
      if (!mounted || _leaving) {
        await _rtc.end();
        return;
      }
      setState(() => _watching = true);
      // Audio listens independently; it must never break the video session.
      try {
        await _viewerAudio.attach(_rtc.sessionId!);
      } catch (error) {
        if (mounted) setState(() => _remoteAudioMessage = '오디오 준비 오류: $error');
      }

      try {
        await _enterLandscape();
      } catch (error) {
        if (mounted) {
          setState(() => _status = '영상 요청 완료 · 가로모드 전환 실패: $error');
        }
      }
    } catch (error) {
      if (mounted) setState(() => _status = '영상 연결 오류: $error');
      await _restoreOrientation();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _stop({bool notifyRemote = true}) async {
    if (_busy || _leaving) return;
    final id = _rtc.sessionId;
    setState(() {
      _busy = true;
      _watching = false;
    });

    try {
      await _viewerAudio.detach();
      await _rtc.end(notifyRemote: notifyRemote);
      if (notifyRemote && id != null) {
        await RemoteControl.instance.requestStop(id);
      }
      if (mounted) {
        setState(() => _status = '영상 종료 · 거치폰 카메라 정리 요청 완료');
      }
    } catch (error) {
      if (mounted) setState(() => _status = '영상 종료 오류: $error');
    } finally {
      try {
        await _restoreOrientation();
      } catch (error) {
        if (mounted) setState(() => _status = '화면 방향 복구 오류: $error');
      }
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _leave() async {
    if (_leaving) return;
    setState(() => _leaving = true);
    final id = _rtc.sessionId;

    try {
      await _viewerAudio.detach();
      await _rtc.end();
      if (id != null) {
        await RemoteControl.instance.requestStop(id);
      }
    } catch (error) {
      if (mounted) setState(() => _status = '연결 종료 오류: $error');
    } finally {
      try {
        await _restoreOrientation();
      } finally {
        if (mounted) Navigator.of(context).pop();
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final background = state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached;
    if (background && !_leaving && _watching && !_busy) {
      unawaited(_stop());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_viewerAudio.detach());
    unawaited(_rtc.end());
    if (_landscapeLocked) unawaited(_restoreOrientation());
    super.dispose();
  }

  Widget _video() {
    final renderer = _rtc.renderer;
    return Container(
      color: Colors.black,
      alignment: Alignment.center,
      child: _watching && renderer != null
          ? AnimatedBuilder(
              animation: renderer,
              builder: (context, _) {
                final landscape = MediaQuery.orientationOf(context) ==
                    Orientation.landscape;
                final quarterTurns =
                    videoQuarterTurns(viewerLandscape: landscape);
                return ViewerVideoControls(
                  video: RotatedBox(
                    quarterTurns: quarterTurns,
                    child: RTCVideoView(
                      renderer,
                      // Cover the entire rotated viewport; contain caused
                      // the narrow upright strip with huge black side bars.
                      objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                    ),
                  ),
                );
              },
            )
          : const Icon(Icons.videocam_off_outlined,
              size: 60, color: Colors.white38),
    );
  }

  @override
  Widget build(BuildContext context) {
    final landscape = MediaQuery.orientationOf(context) ==
        Orientation.landscape;
    return PopScope(
      canPop: _leaving,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) unawaited(_leave());
      },
      child: Scaffold(
        appBar: landscape ? null : AppBar(title: const Text('홈캠 실시간 보기')),
        // Let video extend edge-to-edge in landscape; keep only controls
        // inside the device's notch/system safe areas.
        body: landscape
            ? Stack(children: [
                Positioned.fill(child: _video()),
                Positioned.fill(child: SafeArea(child: Stack(children: [
                  Positioned(
                    top: 8,
                    left: 8,
                    child: IconButton.filledTonal(
                      tooltip: '뒤로',
                      onPressed: _busy ? null : _leave,
                      icon: const Icon(Icons.arrow_back),
                    ),
                  ),
                  Positioned(
                    top: 12,
                    left: 70,
                    right: 12,
                    child: Text(_remoteAudioMessage ?? _status,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white70)),
                  ),
                  if (_remoteAudioOn)
                    const Positioned(
                      top: 50,
                      right: 12,
                      child: Chip(label: Text('거치폰 마이크 ON')),
                    ),
                  Positioned(
                    left: 12,
                    bottom: 12,
                    child: FilledButton.icon(
                      onPressed: _busy || !_watching ? null : _stop,
                      icon: const Icon(Icons.stop),
                      label: const Text('실시간 보기 종료'),
                    ),
                  ),
                ]))),
              ])
            : SafeArea(child: Column(children: [
                  Expanded(child: _video()),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    child: Column(children: [
                      Text(_status, textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: _busy || _watching ? null : _start,
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('실시간 보기 시작'),
                      ),
                      if (_watching)
                        OutlinedButton(
                          onPressed: _busy ? null : _stop,
                          child: const Text('실시간 보기 종료'),
                        ),
                      const SizedBox(height: 8),
                      const Text('가로모드 자동 전환 · 두 손가락 확대/축소',
                          style: TextStyle(color: Colors.white54, fontSize: 12)),
                      const Text('마이크 ON/OFF는 거치폰에서 조작 · 영상 연결과 분리',
                          style: TextStyle(color: Colors.white54, fontSize: 12)),
                    ]),
                  ),
                ])),
      ),
    );
  }
}
