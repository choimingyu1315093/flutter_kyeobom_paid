import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const HomeCameraApp());
}

class HomeCameraApp extends StatelessWidget {
  const HomeCameraApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Home Camera P0',
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark(useMaterial3: true),
        home: const RoleSelectionScreen(),
      );
}

class RoleSelectionScreen extends StatelessWidget {
  const RoleSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Home Camera · P0')),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Text('이 기기의 역할을 선택하세요',
                    style: TextStyle(fontSize: 22)),
                const SizedBox(height: 24),
                FilledButton.icon(
                  icon: const Icon(Icons.videocam_off),
                  label: const Text('거치폰 · 카메라 대기'),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                        builder: (_) => const StationScreen()),
                  ),
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
  String _status = '대기 화면 준비 중';
  bool _active = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startWaiting();
  }

  Future<void> _startWaiting() async {
    try {
      await _screen.invokeMethod<void>('enableWaitingMode');
      if (!mounted) return;
      setState(() {
        _active = true;
        _status = '연결 대기 중';
      });
    } on PlatformException catch (error) {
      if (!mounted) return;
      setState(() => _status = '화면 유지 설정 실패: ${error.message}');
    } on MissingPluginException {
      if (!mounted) return;
      setState(() => _status = '네이티브 화면 유지 기능을 설치해야 합니다');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    setState(() {
      _status = state == AppLifecycleState.resumed
          ? (_active ? '연결 대기 중' : '화면 유지 미설정')
          : '앱 비활성화 · 원격 연결 보장 안 됨';
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _screen.invokeMethod<void>('disableWaitingMode');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
        child: Scaffold(
          backgroundColor: Colors.black,
          body: SafeArea(
            child: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.videocam_off_outlined,
                    size: 36, color: Colors.white30),
                const SizedBox(height: 16),
                Text(_status,
                    style: const TextStyle(color: Colors.white54)),
                const SizedBox(height: 12),
                const Text('카메라 OFF · 마이크 OFF · 녹화 OFF',
                    style: TextStyle(color: Colors.white30, fontSize: 12)),
                const SizedBox(height: 28),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('대기 종료'),
                ),
              ]),
            ),
          ),
        ),
      );
}

class ViewerScreen extends StatelessWidget {
  const ViewerScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('뷰어 · P0')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              '뷰어 화면 준비 완료\n\n원격 기기 연결 및 WebRTC 영상은 P1~P3에서 구현합니다.\n현재 버전에서는 카메라를 켜지 않습니다.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
}
