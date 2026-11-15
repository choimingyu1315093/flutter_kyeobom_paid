import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'remote_control.dart';
import 'webrtc_session.dart';
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
          '안정적인 원격 연결을 위해 충전기를 연결하고 앱을 실행 상태로 유지해 주세요.\n\n'
          '거치폰 마이크는 기본 OFF입니다. 마이크 권한을 허용한 경우에만 뷰어에서 소리 듣기를 켤 수 있습니다.',
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
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _commands;
  Future<void> _commandQueue = Future<void>.value();

  String _status = '연결 대기 준비 중';
  String? _lastCommandId;
  bool _foreground = true;
  bool _streaming = false;
  bool _leaving = false;
  bool _microphoneActive = false;
  bool _preparingMicrophone = false;
  bool _micPermissionReady = false;

  @override
  void initState() {
    super.initState();
    _rtc = HomeCamWebRtcSession(
      onStatus: (value) {
        if (mounted) setState(() => _status = value);
      },
      onMicrophoneState: (active, error) {
        if (!mounted) return;
        setState(() {
          _microphoneActive = active;
          if (error != null) _status = '마이크 오류: $error';
        });
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

  Future<void> _connectCommands() async {
    try {
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

  Future<void> _prepareMicrophone() async {
    if (_preparingMicrophone || _leaving) return;
    setState(() => _preparingMicrophone = true);
    try {
      await HomeCamWebRtcSession.prepareMicrophonePermission();
      if (mounted) {
        setState(() {
          _micPermissionReady = true;
          _status = '마이크 권한 준비 완료 · 현재 마이크 OFF';
        });
      }
    } catch (error) {
      if (mounted) setState(() => _status = '마이크 권한 준비 실패: $error');
    } finally {
      if (mounted) setState(() => _preparingMicrophone = false);
    }
  }

  Future<void> _finishStream() async {
    if (_rtc.isRunning) await _rtc.end();
    if (mounted && !_leaving) {
      setState(() {
        _streaming = false;
        _microphoneActive = false;
        _status = '연결 대기 중';
      });
    }
  }

  Future<void> _leave() async {
    if (_leaving) return;
    setState(() => _leaving = true);
    await _commands?.cancel();
    try {
      await _rtc.end();
      await RemoteControl.instance.stopStation();
    } finally {
      if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground && !_leaving) {
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
                      ? '후면 카메라 ON · 마이크 ${_microphoneActive ? "ON" : "OFF"} · 녹화 OFF'
                      : '카메라 OFF · 마이크 OFF · 녹화 OFF',
                  style: const TextStyle(color: Colors.white30, fontSize: 12),
                ),
                const SizedBox(height: 12),
                if (!_streaming)
                  TextButton.icon(
                    onPressed: _preparingMicrophone ? null : _prepareMicrophone,
                    icon: Icon(_micPermissionReady
                        ? Icons.check_circle_outline : Icons.mic_none),
                    label: Text(_preparingMicrophone
                        ? '마이크 권한 확인 중'
                        : _micPermissionReady
                            ? '마이크 권한 준비됨 (현재 OFF)'
                            : '마이크 권한 미리 허용 (선택)'),
                  ),
                const SizedBox(height: 16),
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
  String _status = '실시간 보기를 누르면 원격 연결합니다';
  bool _busy = false;
  bool _watching = false;
  bool _leaving = false;
  bool _landscapeForced = false;
  bool _microphoneRequested = false;
  bool _microphoneActive = false;
  bool _microphoneBusy = false;
  String? _microphoneError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _rtc = HomeCamWebRtcSession(
      onStatus: (value) {
        if (mounted) setState(() => _status = value);
      },
      onMicrophoneState: (active, error) {
        if (mounted) {
          setState(() {
            _microphoneActive = active;
            _microphoneError = error;
          });
        }
      },
      onRemoteEnded: () => unawaited(_stop(notifyRemote: false)),
    );
  }

  Future<void> _setLandscapeMode() async {
    final next = !_landscapeForced;
    try {
      await SystemChrome.setPreferredOrientations(next
          ? [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]
          : []);
      if (mounted) setState(() => _landscapeForced = next);
    } catch (error) {
      if (mounted) setState(() => _status = '화면 방향 변경 오류: $error');
    }
  }

  Future<void> _restoreRotationPreference() =>
      SystemChrome.setPreferredOrientations([]);

  Future<void> _setMicrophone(bool enabled) async {
    if (!_watching || _busy || _microphoneBusy) return;
    setState(() {
      _microphoneBusy = true;
      _microphoneError = null;
    });
    try {
      await _rtc.requestMicrophone(enabled);
      if (mounted) {
        setState(() {
          _microphoneRequested = enabled;
          _status = enabled
              ? '거치폰 마이크 활성화 요청 중'
              : '거치폰 마이크 종료 요청 중';
        });
      }
    } catch (error) {
      if (mounted) setState(() => _microphoneError = '$error');
    } finally {
      if (mounted) setState(() => _microphoneBusy = false);
    }
  }

  Future<void> _start() async {
    if (_busy || _watching) return;
    setState(() {
      _busy = true;
      _status = '거치폰 연결 요청 중';
      _microphoneRequested = false;
      _microphoneActive = false;
      _microphoneError = null;
    });
    try {
      await _rtc.startViewer();
      if (mounted && !_leaving) setState(() => _watching = true);
    } catch (error) {
      if (mounted) setState(() => _status = '연결 실패: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _stop({bool notifyRemote = true}) async {
    if (_busy && !_leaving) return;
    final sessionId = _rtc.sessionId;
    setState(() {
      _busy = true;
      _watching = false;
      _microphoneRequested = false;
      _microphoneActive = false;
      _microphoneError = null;
    });
    try {
      await _rtc.end(notifyRemote: notifyRemote);
      if (notifyRemote && sessionId != null) {
        await RemoteControl.instance.requestStop(sessionId);
      }
      if (mounted && !_leaving) {
        setState(() => _status = '영상 종료 · 카메라와 마이크 정리 요청 완료');
      }
    } catch (error) {
      if (mounted) setState(() => _status = '종료 오류: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _leave() async {
    if (_leaving) return;
    setState(() => _leaving = true);
    final sessionId = _rtc.sessionId;
    try {
      await _rtc.end();
      if (sessionId != null) {
        await RemoteControl.instance.requestStop(sessionId);
      }
    } finally {
      await _restoreRotationPreference();
      if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && !_leaving && _watching) {
      unawaited(_stop());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_rtc.end());
    if (_landscapeForced) unawaited(_restoreRotationPreference());
    super.dispose();
  }

  Widget _video() {
    final renderer = _rtc.renderer;
    return Container(
      color: Colors.black,
      alignment: Alignment.center,
      child: _watching && renderer != null
          ? ViewerVideoControls(
              video: RTCVideoView(
                renderer,
                objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
              ),
            )
          : const Icon(Icons.videocam_off_outlined,
              size: 60, color: Colors.white38),
    );
  }

  Widget _actions({required bool compact}) => Wrap(
        spacing: 8,
        runSpacing: 6,
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          OutlinedButton.icon(
            onPressed: _setLandscapeMode,
            icon: Icon(_landscapeForced ? Icons.screen_rotation : Icons.screen_lock_landscape),
            label: Text(_landscapeForced ? '자동 회전' : '가로 보기'),
          ),
          if (!_watching)
            FilledButton.icon(
              onPressed: _busy ? null : _start,
              icon: const Icon(Icons.play_arrow),
              label: Text(compact ? '시작' : '실시간 보기 시작'),
            ),
          if (_watching)
            FilledButton.icon(
              onPressed: _busy ? null : _stop,
              icon: const Icon(Icons.stop),
              label: Text(compact ? '종료' : '실시간 보기 종료'),
            ),
          if (_watching)
            OutlinedButton.icon(
              onPressed: _busy || _microphoneBusy
                  ? null
                  : () => _setMicrophone(!_microphoneRequested),
              icon: Icon(_microphoneRequested ? Icons.mic : Icons.mic_off),
              label: Text(_microphoneRequested ? '마이크 끄기' : '소리 듣기'),
            ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final landscape = MediaQuery.orientationOf(context) == Orientation.landscape;
    return PopScope(
      canPop: _leaving,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) unawaited(_leave());
      },
      child: Scaffold(
        appBar: landscape ? null : AppBar(title: const Text('홈캠 실시간 보기')),
        body: SafeArea(
          child: landscape
              ? Stack(
                  children: [
                    Positioned.fill(child: _video()),
                    Positioned(
                      left: 8,
                      top: 8,
                      child: IconButton.filledTonal(
                        tooltip: '뒤로',
                        onPressed: _leave,
                        icon: const Icon(Icons.arrow_back),
                      ),
                    ),
                    Positioned(
                      left: 70,
                      right: 8,
                      top: 12,
                      child: Text(_microphoneError ?? _status,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white70)),
                    ),
                    Positioned(
                      left: 12,
                      bottom: 10,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.sizeOf(context).width * 0.64,
                        ),
                        child: _actions(compact: true),
                      ),
                    ),
                    if (_microphoneActive)
                      const Positioned(
                        right: 12,
                        top: 8,
                        child: Chip(label: Text('거치폰 마이크 ON')),
                      ),
                  ],
                )
              : Column(children: [
                  Expanded(child: _video()),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
                    child: Column(children: [
                      Text(_microphoneError ?? _status,
                          textAlign: TextAlign.center),
                      if (_watching)
                        Text(
                          _microphoneActive
                              ? '거치폰 소리 수신 중'
                              : '거치폰 마이크 OFF',
                          style: const TextStyle(color: Colors.white60),
                        ),
                      const SizedBox(height: 10),
                      _actions(compact: false),
                      const SizedBox(height: 8),
                      const Text('확대·축소: 두 손가락 · 최대 4배',
                          style: TextStyle(fontSize: 12, color: Colors.white54)),
                    ]),
                  ),
                ]),
        ),
      ),
    );
  }
}
