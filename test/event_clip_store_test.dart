import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_home_camera/event_clip_store.dart';
import 'package:flutter_home_camera/event_motion_policy.dart';

void main() {
  late Directory sandbox;
  late EventClipStore store;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('kyeobom_clip_qa_');
    store = EventClipStore(rootOverride: sandbox);
  });

  tearDown(() async {
    if (await sandbox.exists()) await sandbox.delete(recursive: true);
  });

  test('publishes a completed MP4 only into private ready storage', () async {
    final pending = await store.createPending();
    await pending.writeAsBytes(List<int>.filled(2048, 9));
    final published = await store.finalize(pending);
    expect(published, isNotNull);
    expect(published!.bytes, 2048);
    expect(await pending.exists(), false);
    expect(await published.file.exists(), true);
    expect(await store.list(), hasLength(1));
    await store.delete(published);
    expect(await store.list(), isEmpty);
  });

  test('rejects a recorder output file outside private pending directory',
      () async {
    final external = File('${sandbox.path}/not_pending.mp4');
    await external.writeAsBytes(List<int>.filled(2048, 9));
    expect(await store.finalize(external), isNull);
    expect(await external.exists(), isTrue);
  });

  test('does not expose empty or incomplete recording', () async {
    final pending = await store.createPending();
    await pending.writeAsBytes([1, 2, 3]);
    expect(await store.finalize(pending), isNull);
    expect(await store.list(), isEmpty);
  });

  test('retains newest 50 clips and removes older clips', () async {
    final dir = Directory('${sandbox.path}/ready');
    await dir.create(recursive: true);
    final now = DateTime.now().millisecondsSinceEpoch;
    for (var i = 0; i < 53; i++) {
      final file = File('${dir.path}/motion_${now - i * 1000}.mp4');
      await file.writeAsBytes(List<int>.filled(2048, 1));
    }
    final clips = await store.list();
    expect(clips, hasLength(EventRecordingPolicy.maxClips));
    expect(clips.first.createdAt.millisecondsSinceEpoch, now);
    expect(clips.last.createdAt.millisecondsSinceEpoch, now - 49 * 1000);
  });

  test('discarding a 31-day-old finalized clip returns null without throwing',
      () async {
    final old = DateTime.now().subtract(const Duration(days: 31))
        .millisecondsSinceEpoch;
    final pendingDir = Directory('${sandbox.path}/pending');
    await pendingDir.create(recursive: true);
    final pending = File('${pendingDir.path}/motion_$old.mp4');
    await pending.writeAsBytes(List<int>.filled(2048, 1));
    expect(await store.finalize(pending), isNull);
    expect(await store.list(), isEmpty);
  });

  test('old crash leftovers are pruned after one hour', () async {
    final pending = await store.createPending();
    await pending.writeAsBytes(List<int>.filled(2048, 1));
    await pending.setLastModified(
        DateTime.now().subtract(const Duration(hours: 2)));
    await store.prune();
    expect(await pending.exists(), false);
  });
}
