import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'event_motion_policy.dart';

class EventClip {
  const EventClip({
    required this.file,
    required this.createdAt,
    required this.bytes,
  });
  final File file;
  final DateTime createdAt;
  final int bytes;
}

/// Private, station-local clips. Nothing is uploaded to Firebase or Photos.
/// A pending recording lives outside the visible clips directory until its
/// MediaRecorder.stop() completes successfully.
class EventClipStore {
  Future<Directory> _root() async {
    final app = await getApplicationSupportDirectory();
    return Directory('${app.path}/kyeobom_event_clips');
  }

  Future<Directory> _readyDir() async {
    final root = await _root();
    final dir = Directory('${root.path}/ready');
    await dir.create(recursive: true);
    return dir;
  }

  Future<File> createPending() async {
    final root = await _root();
    final dir = Directory('${root.path}/pending');
    await dir.create(recursive: true);
    final stamp = DateTime.now().toUtc().millisecondsSinceEpoch;
    return File('${dir.path}/motion_$stamp.mp4');
  }

  Future<EventClip?> finalize(File pending) async {
    if (!await pending.exists()) return null;
    final size = await pending.length();
    if (size <= 1024) {
      await pending.delete();
      return null;
    }
    final dir = await _readyDir();
    final moved = await pending.rename('${dir.path}/${_basename(pending.path)}');
    await prune();
    final info = await moved.stat();
    return EventClip(file: moved, createdAt: _timestamp(moved.path),
        bytes: info.size);
  }

  Future<List<EventClip>> list() async {
    await prune();
    return _readClips();
  }

  Future<void> delete(EventClip clip) async {
    if (!await clip.file.exists()) return;
    // Do not accept an arbitrary file supplied from outside the clips folder.
    final root = await _readyDir();
    if (clip.file.parent.path != root.path) return;
    await clip.file.delete();
  }

  Future<void> prune() async {
    // A previous native recorder crash can leave a partial, unpublished clip.
    // Active recordings are at most 20 seconds, so only clear 1h-old remnants.
    final root = await _root();
    final pending = Directory('${root.path}/pending');
    if (await pending.exists()) {
      final entries = await pending.list(followLinks: false).toList();
      for (final entry in entries) {
        if (entry is! File || !_validName(_basename(entry.path))) continue;
        final age = DateTime.now().difference(await entry.lastModified());
        if (age > const Duration(hours: 1)) await entry.delete();
      }
    }
    final clips = await _readClips();
    final now = DateTime.now();
    var bytes = 0;
    var retained = 0;
    for (final clip in clips) {
      final old = now.difference(clip.createdAt) >
          EventRecordingPolicy.maxClipAge;
      if (old || retained >= EventRecordingPolicy.maxClips ||
          bytes + clip.bytes > EventRecordingPolicy.maxStoredBytes) {
        if (await clip.file.exists()) await clip.file.delete();
        continue;
      }
      bytes += clip.bytes;
      retained++;
    }
  }

  Future<List<EventClip>> _readClips() async {
    final dir = await _readyDir();
    final entries = await dir.list(followLinks: false).toList();
    final clips = <EventClip>[];
    for (final entry in entries) {
      if (entry is! File || !_validName(_basename(entry.path))) continue;
      final size = await entry.length();
      clips.add(EventClip(file: entry, createdAt: _timestamp(entry.path),
          bytes: size));
    }
    clips.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return clips;
  }

  static String _basename(String path) => path.split(Platform.pathSeparator).last;
  static bool _validName(String name) =>
      RegExp(r'^motion_[0-9]{13}\.mp4$').hasMatch(name);
  static DateTime _timestamp(String path) {
    final filename = _basename(path);
    if (!_validName(filename)) return DateTime.fromMillisecondsSinceEpoch(0);
    final ms = int.parse(filename.substring(7, 20));
    return DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toLocal();
  }
}
