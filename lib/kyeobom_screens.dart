import 'package:flutter/material.dart';

import 'kyeobom_design.dart';

/// Presentation layer only. Camera, networking, mic and orientation remain
/// managed by the existing StationScreen and ViewerScreen state classes.
class KyeobomStationView extends StatelessWidget {
  const KyeobomStationView({
    super.key,
    required this.status,
    required this.streaming,
    required this.microphoneOn,
    required this.microphoneBusy,
    required this.leaving,
    required this.onLeave,
    required this.onToggleMicrophone,
    this.microphoneMessage,
  });

  final String status;
  final bool streaming;
  final bool microphoneOn;
  final bool microphoneBusy;
  final bool leaving;
  final String? microphoneMessage;
  final VoidCallback onLeave;
  final VoidCallback onToggleMicrophone;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KyeobomPalette.night,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 22),
          child: Column(
            children: [
              const Row(
                children: [
                  Icon(Icons.home_rounded, color: Colors.white54, size: 20),
                  SizedBox(width: 8),
                  Text(
                    '켜봄',
                    style: TextStyle(
                      color: Colors.white60,
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                  Spacer(),
                  Text(
                    'HOME CAMERA',
                    style: TextStyle(
                      color: Colors.white38,
                      fontSize: 10,
                      letterSpacing: 1.3,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 86,
                        height: 86,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: streaming
                              ? const Color(0xFF14352F)
                              : const Color(0xFF171C1B),
                        ),
                        child: Icon(
                          streaming
                              ? Icons.videocam_rounded
                              : Icons.videocam_off_rounded,
                          size: 37,
                          color: streaming
                              ? const Color(0xFF72D8BC)
                              : Colors.white38,
                        ),
                      ),
                      const SizedBox(height: 28),
                      Text(
                        streaming ? '영상 송출 중' : (status.contains('오류') || status.contains('실패') ? '연결 확인 필요' : '연결 대기 중'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 24,
                          letterSpacing: -0.6,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        streaming
                            ? '다른 스마트폰에서 실시간으로 보고 있어요.'
                            : '필요할 때만 카메라가 켜집니다.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 14,
                          height: 1.55,
                        ),
                      ),
                      const SizedBox(height: 22),
                      KyeobomStatusPill(
                        label: streaming ? '카메라 사용 중' : '카메라 꺼짐',
                        active: streaming,
                        dark: true,
                      ),
                      const SizedBox(height: 22),
                      Text(
                        streaming
                            ? '후면 카메라 ON · 마이크 ${microphoneOn ? "ON" : "OFF"} · 녹화 OFF'
                            : '카메라 OFF · 마이크 OFF · 녹화 OFF',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Text(
                          status,
                          textAlign: TextAlign.center,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 12,
                            height: 1.4,
                          ),
                        ),
                      ),
                      if (streaming) ...[
                        const SizedBox(height: 20),
                        OutlinedButton.icon(
                          onPressed: microphoneBusy ? null : onToggleMicrophone,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Color(0xFF3A4743)),
                            minimumSize: const Size(190, 48),
                          ),
                          icon: Icon(
                            microphoneOn ? Icons.mic_rounded : Icons.mic_off_rounded,
                            size: 20,
                          ),
                          label: Text(
                            microphoneBusy
                                ? '마이크 전환 중'
                                : microphoneOn ? '마이크 끄기' : '마이크 켜기',
                          ),
                        ),
                        if (microphoneMessage != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            microphoneMessage!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white60,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
              ),
              TextButton(
                onPressed: leaving ? null : onLeave,
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white60,
                  minimumSize: const Size.fromHeight(48),
                ),
                child: const Text('대기 종료'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class KyeobomViewerView extends StatelessWidget {
  const KyeobomViewerView({
    super.key,
    required this.video,
    required this.status,
    required this.watching,
    required this.busy,
    required this.leaving,
    required this.landscape,
    required this.remoteAudioOn,
    required this.onBack,
    required this.onStart,
    required this.onStop,
    this.remoteAudioMessage,
  });

  final Widget video;
  final String status;
  final bool watching;
  final bool busy;
  final bool leaving;
  final bool landscape;
  final bool remoteAudioOn;
  final String? remoteAudioMessage;
  final VoidCallback onBack;
  final VoidCallback onStart;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    if (landscape) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Stack(
            children: [
              Positioned.fill(child: video),
              Positioned(
                top: 8,
                left: 12,
                child: IconButton.filledTonal(
                  tooltip: '뒤로',
                  onPressed: busy || leaving ? null : onBack,
                  icon: const Icon(Icons.arrow_back_rounded),
                  style: IconButton.styleFrom(
                    backgroundColor: const Color(0xDD182724),
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
              Positioned(
                top: 10,
                left: 68,
                right: 16,
                child: Text(
                  remoteAudioMessage ?? status,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ),
              if (remoteAudioOn)
                const Positioned(
                  top: 43,
                  right: 16,
                  child: KyeobomStatusPill(
                    label: '거치폰 마이크 ON',
                    active: true,
                    dark: true,
                  ),
                ),
              Positioned(
                bottom: 16,
                left: 16,
                child: FilledButton.icon(
                  onPressed: busy || !watching ? null : onStop,
                  icon: const Icon(Icons.stop_circle_outlined, size: 20),
                  label: const Text('실시간 보기 종료'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xE52B3B39),
                    foregroundColor: Colors.white,
                    minimumSize: const Size(174, 48),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: busy || leaving ? null : onBack,
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: const Text(
          '켜봄',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 19,
            color: KyeobomPalette.ink,
          ),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 16, 22, 22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const KyeobomEyebrow('MY HOME CAMERA'),
              const SizedBox(height: 12),
              const Text(
                '우리 집, 궁금할 때',
                style: TextStyle(
                  color: KyeobomPalette.ink,
                  fontSize: 27,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.8,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '켜봄으로 간편하게 확인하세요.',
                style: TextStyle(color: KyeobomPalette.muted, fontSize: 14),
              ),
              const SizedBox(height: 24),
              Expanded(
                child: Container(
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Stack(
                    children: [
                      Positioned.fill(child: video),
                      const Positioned(
                        left: 16,
                        top: 15,
                        child: Text(
                          '우리 집 홈캠',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Positioned(
                        right: 14,
                        top: 12,
                        child: KyeobomStatusPill(
                          label: watching ? '실시간' : '보기 전',
                          active: watching,
                          dark: true,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                remoteAudioMessage ?? status,
                textAlign: TextAlign.left,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: KyeobomPalette.muted,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: watching
                    ? OutlinedButton.icon(
                        onPressed: busy ? null : onStop,
                        icon: const Icon(Icons.stop_circle_outlined),
                        label: const Text('실시간 보기 종료'),
                      )
                    : FilledButton.icon(
                        onPressed: busy || leaving ? null : onStart,
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: Text(busy ? '연결 중...' : '실시간 보기'),
                      ),
              ),
              const SizedBox(height: 14),
              const Text(
                '연결 후 가로 화면으로 전환 · 두 손가락 확대/축소',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: KyeobomPalette.muted,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
