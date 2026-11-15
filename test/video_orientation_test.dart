import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_home_camera/video_orientation.dart';

void main() {
  test('landscape-left rotates station video clockwise for landscape viewing', () {
    expect(videoQuarterTurns(
      viewerLandscape: true,
      landscapeRight: false,
    ), 1);
  });

  test('180-degree phone turn reverses video correction for landscape-right', () {
    expect(videoQuarterTurns(
      viewerLandscape: true,
      landscapeRight: true,
    ), 3);
  });

  test('portrait viewer never rotates the stream', () {
    expect(videoQuarterTurns(
      viewerLandscape: false,
      landscapeRight: true,
    ), 0);
  });
}
