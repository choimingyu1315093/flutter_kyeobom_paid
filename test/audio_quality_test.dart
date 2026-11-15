import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_home_camera/audio_quality.dart';

void main() {
  test('Opus tuning raises bitrate cap, enables FEC, disables DTX', () {
    const original = 'v=0\r\n'
        'm=audio 9 UDP/TLS/RTP/SAVPF 111 0\r\n'
        'a=rtpmap:111 opus/48000/2\r\n'
        'a=fmtp:111 minptime=10;useinbandfec=0\r\n'
        'a=rtpmap:0 PCMU/8000\r\n';
    final tuned = tuneMonitoringOpus(original);
    expect(tuned, contains('maxaveragebitrate=48000'));
    expect(tuned, contains('useinbandfec=1'));
    expect(tuned, contains('usedtx=0'));
    expect(tuned, contains('minptime=10'));
    expect(tuned, isNot(contains('useinbandfec=0')));
    expect(tuned, contains('a=rtpmap:0 PCMU/8000'));
    expect(tuned, contains('\r\n'));
  });

  test('adds fmtp line only when Opus payload exists', () {
    const original = 'v=0\n'
        'm=audio 9 UDP/TLS/RTP/SAVPF 109\n'
        'a=rtpmap:109 opus/48000/2\n';
    final tuned = tuneMonitoringOpus(original);
    expect(tuned, contains('a=fmtp:109 '));
    expect(tuneMonitoringOpus(tuned), tuned);
  });

  test('leaves unsupported codec SDP untouched', () {
    const original = 'v=0\n'
        'm=audio 9 UDP/TLS/RTP/SAVPF 0\n'
        'a=rtpmap:0 PCMU/8000\n';
    expect(tuneMonitoringOpus(original), original);
    expect(tuneMonitoringOpus(null), '');
  });

  test('room audio never requests camera and disables call processing', () {
    final c = stationRoomAudioConstraints();
    expect(c['video'], false);
    final audio = c['audio'] as Map<String, dynamic>;
    final optional = audio['optional'] as List<dynamic>;
    expect(optional, contains({'googEchoCancellation': 'false'}));
    expect(optional, contains({'googAutoGainControl': 'false'}));
    expect(optional, contains({'googNoiseSuppression': 'false'}));
  });
}
