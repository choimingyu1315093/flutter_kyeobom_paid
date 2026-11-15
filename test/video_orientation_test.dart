import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_home_camera/video_orientation.dart';

void main() {
  test('portrait WebRTC frame rotates automatically for landscape viewer', () {
    expect(videoQuarterTurns(
      viewerLandscape: true,
      videoWidth: 720,
      videoHeight: 1280,
    ), 1);
  });

  test('landscape WebRTC frame is not rotated twice', () {
    expect(videoQuarterTurns(
      viewerLandscape: true,
      videoWidth: 1280,
      videoHeight: 720,
    ), 0);
  });

  test('portrait viewer does not rotate incoming video', () {
    expect(videoQuarterTurns(
      viewerLandscape: false,
      videoWidth: 720,
      videoHeight: 1280,
    ), 0);
  });

  test('unknown video dimensions do not trigger an early rotation', () {
    expect(videoQuarterTurns(
      viewerLandscape: true,
      videoWidth: 0,
      videoHeight: 0,
    ), 0);
  });

  test('square video does not rotate', () {
    expect(videoQuarterTurns(
      viewerLandscape: true,
      videoWidth: 1080,
      videoHeight: 1080,
    ), 0);
  });
}
