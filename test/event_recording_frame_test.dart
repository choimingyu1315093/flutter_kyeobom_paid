import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:flutter_home_camera/event_recording_controller.dart';

void main() {
  test('downsamples an encoded frame to bounded luminance cells', () {
    final frame = img.Image(width: 160, height: 120);
    img.fill(frame, color: img.ColorRgb8(100, 100, 100));
    final bytes = Uint8List.fromList(img.encodePng(frame));
    final luma = eventLumaFromFrame(bytes);
    expect(luma, isNotNull);
    expect(luma, hasLength(16 * 12));
    expect(luma!.every((v) => v >= 99 && v <= 101), isTrue);
  });

  test('unreadable video frame is ignored without changing camera state', () {
    expect(eventLumaFromFrame(Uint8List.fromList([0, 1, 2, 3])),
        isNull);
  });
}
