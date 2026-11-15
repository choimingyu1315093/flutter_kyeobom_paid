import 'package:flutter/material.dart';

import 'kyeobom_design.dart';
import 'kyeobom_viewer_ads.dart';

/// Figma screen 3: nearly black waiting surface; camera and mic are
/// physically OFF in standby. Native wakelock/lifecycle remain in main.dart.
class KyeobomStationView extends StatelessWidget {
  const KyeobomStationView({
    super.key,
    required this.status, required this.streaming,
    required this.microphoneOn, required this.microphoneBusy,
    required this.leaving, required this.onLeave,
    required this.onToggleMicrophone,
    this.microphoneMessage,
    this.autoMicrophoneEnabled = false,
    this.autoMicrophoneBusy = false,
    this.onAutoMicrophoneChanged,
  });

  final String status;
  final bool streaming, microphoneOn, microphoneBusy, leaving;
  final String? microphoneMessage;
  final VoidCallback onLeave, onToggleMicrophone;
  final bool autoMicrophoneEnabled, autoMicrophoneBusy;
  final ValueChanged<bool>? onAutoMicrophoneChanged;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: KyeobomPalette.night,
    body: SafeArea(child: Padding(
      padding: const EdgeInsets.fromLTRB(22, 14, 22, 18),
      child: Column(children: [
        Row(children: [
          const Text('켜봄', style: TextStyle(
            color: Colors.white38, fontSize: 12, fontWeight: FontWeight.w700)),
          const Spacer(),
          Text(streaming ? 'LIVE' : 'STANDBY',
            style: const TextStyle(
              color: Colors.white30, fontSize: 10, letterSpacing: 1.2)),
        ]),
        Expanded(child: Center(child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 9, height: 9,
              decoration: BoxDecoration(
                color: streaming ? KyeobomPalette.green : const Color(0xFF3A9D83),
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(
                  color: KyeobomPalette.green.withValues(alpha: .35),
                  blurRadius: 16, spreadRadius: 3,
                )],
              ),
            ),
            const SizedBox(height: 18),
            Text(streaming ? '실시간 연결 중' : '홈캠 대기 중',
              style: const TextStyle(color: Colors.white70,
                fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(streaming
                ? '현재 다른 스마트폰에서 보고 있어요.'
                : '필요할 때만 카메라가 켜집니다.',
              style: const TextStyle(color: Colors.white30, fontSize: 12)),
            const SizedBox(height: 14),
            Text(
              streaming
                  ? '카메라 ON · 마이크 ${microphoneOn ? "ON" : "OFF"} · 녹화 OFF'
                  : '카메라 OFF · 마이크 OFF · 녹화 OFF',
              style: const TextStyle(color: Colors.white24, fontSize: 11),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(status, textAlign: TextAlign.center,
                maxLines: 3, overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white24, fontSize: 11)),
            ),
            if (streaming) ...[
              const SizedBox(height: 18),
              OutlinedButton.icon(
                onPressed: microphoneBusy ? null : onToggleMicrophone,
                icon: Icon(microphoneOn ? Icons.mic : Icons.mic_off, size: 18),
                label: Text(microphoneBusy ? '마이크 전환 중'
                    : microphoneOn ? '거치폰 마이크 끄기' : '거치폰 마이크 켜기'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white70,
                  side: const BorderSide(color: Colors.white24),
                  minimumSize: const Size(180, 44),
                ),
              ),
            ],
          ],
        ))),
        if (!streaming)
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF0E1319),
              border: Border.all(color: const Color(0xFF1E2832)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Material(
              type: MaterialType.transparency,
              child: SwitchListTile.adaptive(
                title: const Text('실시간 보기 시 거치폰 마이크 자동 켜기',
                style: TextStyle(color: Colors.white60, fontSize: 12)),
              subtitle: const Text('주변 소리만 전송 · 대기 중에는 OFF',
                style: TextStyle(color: Colors.white30, fontSize: 10)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
              activeTrackColor: KyeobomPalette.blue,
              value: autoMicrophoneEnabled,
                onChanged: leaving || autoMicrophoneBusy
                    ? null : onAutoMicrophoneChanged,
              ),
            ),
          ),
        if (microphoneMessage != null) ...[
          const SizedBox(height: 7),
          Text(microphoneMessage!,
            maxLines: 2, textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white38, fontSize: 11)),
        ],
        TextButton(
          onPressed: leaving ? null : onLeave,
          style: TextButton.styleFrom(foregroundColor: Colors.white38),
          child: const Text('대기 종료', style: TextStyle(fontSize: 12)),
        ),
      ]),
    )),
  );
}

/// Figma screen 4 (dashboard), and screen 5 (landscape real-time video).
/// Video is supplied by the existing WebRTC layer; this widget never opens a
/// camera or microphone and only renders current connection status/actions.
class KyeobomViewerView extends StatelessWidget {
  const KyeobomViewerView({
    super.key, required this.video, required this.status,
    required this.watching, required this.busy, required this.leaving,
    required this.landscape, required this.remoteAudioOn,
    required this.onBack, required this.onStart, required this.onStop,
    this.remoteAudioMessage,
  });

  final Widget video;
  final String status;
  final bool watching, busy, leaving, landscape, remoteAudioOn;
  final String? remoteAudioMessage;
  final VoidCallback onBack, onStart, onStop;

  @override
  Widget build(BuildContext context) =>
      landscape ? _landscape(context) : _dashboard(context);

  Widget _dashboard(BuildContext context) => Scaffold(
    // Prefer a permanently visible ad on taller phones. On compact devices,
    // keep the primary live-video button reachable and move the ad into scroll.
    bottomNavigationBar: (MediaQuery.sizeOf(context).height >= 740 &&
            !watching && !busy && !leaving)
        ? SafeArea(
            top: false,
            child: Center(
              heightFactor: 1,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 500),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20),
                  child: KyeobomViewerHomeAd(),
                ),
              ),
            ),
          )
        : null,
    appBar: AppBar(
      leading: IconButton(
        onPressed: busy || leaving ? null : onBack,
        icon: const Icon(Icons.chevron_left_rounded),
      ),
      title: const Text('켜봄', style: TextStyle(
        fontSize: 16, fontWeight: FontWeight.w800)),
      actions: [
        IconButton(onPressed: null,
          icon: const Icon(Icons.notifications_none_rounded, size: 21)),
        const SizedBox(width: 7),
      ],
    ),
    body: SafeArea(child: Center(child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 500),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const KyeobomEyebrow('MY HOME CAMERA'),
          const SizedBox(height: 10),
          const Text('우리 집, 궁금할 땐',
            style: TextStyle(fontSize: 27, height: 1.25,
              fontWeight: FontWeight.w800, color: KyeobomPalette.ink)),
          const SizedBox(height: 5),
          const Text('집에 있는 홈캠을 언제든 확인하세요.',
            style: TextStyle(color: KyeobomPalette.muted, fontSize: 13)),
          const SizedBox(height: 25),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: KyeobomPalette.border),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.home_outlined, color: KyeobomPalette.navy, size: 22),
                const SizedBox(width: 9),
                const Expanded(child: Text('우리 집 홈캠',
                  style: TextStyle(color: KyeobomPalette.ink,
                    fontSize: 17, fontWeight: FontWeight.w800))),
                KyeobomStatusPill(
                  label: watching ? '실시간 연결' : '연결 준비',
                  active: watching,
                ),
              ]),
              const SizedBox(height: 17),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 27),
                decoration: BoxDecoration(
                  color: KyeobomPalette.canvas,
                  border: Border.all(color: KyeobomPalette.border),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Column(children: [
                  Container(
                    width: 48, height: 48,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: const Icon(Icons.videocam_outlined,
                      size: 26, color: KyeobomPalette.navy),
                  ),
                  const SizedBox(height: 12),
                  const Text('집에 있는 홈캠을 확인해 보세요',
                    style: TextStyle(color: KyeobomPalette.ink,
                      fontWeight: FontWeight.w700, fontSize: 13)),
                  const SizedBox(height: 6),
                  const Text('필요할 때만 카메라가 켜집니다.',
                    style: TextStyle(color: KyeobomPalette.muted, fontSize: 11)),
                ]),
              ),
              const SizedBox(height: 17),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: busy || leaving
                      ? null : watching ? onStop : onStart,
                  icon: Icon(watching ? Icons.stop_circle_outlined
                      : Icons.play_arrow_rounded, size: 20),
                  label: Text(busy ? '연결 중...'
                      : watching ? '실시간 보기 종료' : '실시간 보기'),
                ),
              ),
              const SizedBox(height: 10),
              Center(child: Text(remoteAudioMessage ?? status,
                textAlign: TextAlign.center,
                maxLines: 2, overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: KyeobomPalette.muted,
                  fontSize: 11))),
            ]),
          ),
          if (MediaQuery.sizeOf(context).height < 740 &&
              !watching && !busy && !leaving)
            const KyeobomViewerHomeAd(),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: KyeobomPalette.border),
            ),
            child: const Row(children: [
              Icon(Icons.shield_outlined, color: Color(0xFFD85555), size: 20),
              SizedBox(width: 10),
              Expanded(child: Text(
                '홈캠 대기 중에는 카메라와 마이크가 꺼져 있어요. '
                '실시간 보기를 시작할 때만 연결됩니다.',
                style: TextStyle(color: KyeobomPalette.muted,
                  fontSize: 11, height: 1.5),
              )),
            ]),
          ),
          const SizedBox(height: 15),
          const Center(child: Text('실시간 보기를 시작하면 가로 화면으로 전환됩니다.',
            style: TextStyle(color: KyeobomPalette.muted, fontSize: 11))),
        ]),
      ),
    ))),
  );

  Widget _landscape(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    body: Stack(children: [
      Positioned.fill(child: video),
      // Figma screen 5: translucent top and bottom controls over the live feed.
      Positioned(
        left: 0, right: 0, top: 0,
        child: Container(
          height: 56,
          color: const Color(0xBB0B1424),
        ),
      ),
      Positioned.fill(child: SafeArea(child: Stack(children: [
        Positioned(
          left: 8, top: 3,
          child: IconButton(
            onPressed: busy || leaving ? null : onBack,
            tooltip: '뒤로',
            icon: const Icon(Icons.chevron_left_rounded, color: Colors.white),
          ),
        ),
        const Positioned(
          left: 65, top: 14,
          child: Text('우리 집 홈캠',
            style: TextStyle(color: Colors.white,
              fontWeight: FontWeight.w700, fontSize: 13)),
        ),
        Positioned(
          top: 10, right: 155,
          child: KyeobomStatusPill(
            label: watching ? '실시간' : '연결 중',
            active: watching, dark: true,
          ),
        ),
        Positioned(
          right: 10, top: 7,
          child: SizedBox(
            height: 38,
            child: FilledButton.icon(
              onPressed: busy || !watching ? null : onStop,
              icon: const Icon(Icons.stop_circle_outlined, size: 17),
              label: const Text('연결 종료',
                style: TextStyle(fontSize: 12)),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFBE3A4C),
                minimumSize: const Size(115, 38),
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
            ),
          ),
        ),
        Positioned(
          left: 12, top: 64,
          child: Text(remoteAudioMessage ?? status,
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white70, fontSize: 11,
              shadows: [Shadow(color: Colors.black, blurRadius: 6)],
            )),
        ),
        Positioned(
          left: 12, bottom: 12,
          child: Row(children: [
            const KyeobomStatusPill(
              label: '카메라 ON', active: true, dark: true,
            ),
            const SizedBox(width: 7),
            KyeobomStatusPill(
              label: remoteAudioOn ? '거치폰 마이크 ON' : '마이크 OFF',
              active: remoteAudioOn, dark: true,
            ),
          ]),
        ),
      ]))),
    ]),
  );
}
