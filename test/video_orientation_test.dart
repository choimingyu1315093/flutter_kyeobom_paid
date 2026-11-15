import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_home_camera/video_orientation.dart';

void main() {
  test('landscape viewer rotates the actual incoming pixels clockwise', () {
    expect(videoQuarterTurns(viewerLandscape: true), 1);
  });

  test('portrait viewer leaves the incoming pixels unchanged', () {
    expect(videoQuarterTurns(viewerLandscape: false), 0);
  });
}
