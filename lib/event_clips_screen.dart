import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import 'event_clip_store.dart';

class EventClipsScreen extends StatefulWidget {
  const EventClipsScreen({super.key});

  @override
  State<EventClipsScreen> createState() => _EventClipsScreenState();
}

class _EventClipsScreenState extends State<EventClipsScreen> {
  final EventClipStore _store = EventClipStore();
  late Future<List<EventClip>> _clips;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() => _clips = _store.list();

  Future<void> _delete(EventClip clip) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('이벤트 영상 삭제'),
        content: const Text('이 거치폰에 저장된 영상을 영구 삭제할까요?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
              child: const Text('취소')),
          FilledButton(onPressed: () => Navigator.pop(context, true),
              child: const Text('삭제')),
        ],
      ),
    );
    if (yes != true) return;
    try {
      await _store.delete(clip);
      if (mounted) setState(_reload);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('영상 삭제 실패: $error'),
        ));
      }
    }
  }

  String _date(DateTime date) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${date.year}-${two(date.month)}-${two(date.day)} '
        '${two(date.hour)}:${two(date.minute)}';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('이벤트 자동 녹화 기록')),
    body: FutureBuilder<List<EventClip>>(
      future: _clips,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('녹화 목록을 불러오지 못했어요: ${snapshot.error}'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final clips = snapshot.data!;
        if (clips.isEmpty) {
          return const Center(child: Padding(
            padding: EdgeInsets.all(26),
            child: Text(
              '저장된 이벤트 영상이 없어요.\n'
              '거치폰에서 자동 녹화를 켜고, 실시간 영상 시청 중 움직임이 감지되면 '
              '20초짜리 영상이 이 스마트폰에 저장돼요.',
              textAlign: TextAlign.center,
            ),
          ));
        }
        return ListView.builder(
          itemCount: clips.length,
          itemBuilder: (context, i) {
            final clip = clips[i];
            final mb = (clip.bytes / 1024 / 1024).toStringAsFixed(1);
            return ListTile(
              leading: const Icon(Icons.video_library_outlined),
              title: Text(_date(clip.createdAt)),
              subtitle: Text('움직임 감지 · $mb MB · 거치폰 내부 저장'),
              onTap: () => Navigator.push(context,
                MaterialPageRoute<void>(
                    builder: (_) => EventClipPlayer(file: clip.file))),
              trailing: IconButton(
                tooltip: '영상 삭제',
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _delete(clip),
              ),
            );
          },
        );
      },
    ),
  );
}

class EventClipPlayer extends StatefulWidget {
  const EventClipPlayer({super.key, required this.file});
  final File file;

  @override
  State<EventClipPlayer> createState() => _EventClipPlayerState();
}

class _EventClipPlayerState extends State<EventClipPlayer> {
  late final VideoPlayerController _player;
  late final Future<void> _ready;

  @override
  void initState() {
    super.initState();
    _player = VideoPlayerController.file(widget.file);
    _ready = _player.initialize().then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(title: const Text('이벤트 영상')),
    body: FutureBuilder<void>(
      future: _ready,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('영상 재생 실패: ${snapshot.error}',
            style: const TextStyle(color: Colors.white)));
        }
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        return Center(child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AspectRatio(
              aspectRatio: _player.value.aspectRatio > 0
                  ? _player.value.aspectRatio : 16 / 9,
              child: VideoPlayer(_player),
            ),
            const SizedBox(height: 20),
            IconButton.filled(
              tooltip: _player.value.isPlaying ? '일시정지' : '재생',
              onPressed: () async {
                if (_player.value.isPlaying) {
                  await _player.pause();
                } else {
                  await _player.play();
                }
                if (mounted) setState(() {});
              },
              icon: Icon(_player.value.isPlaying
                  ? Icons.pause_rounded : Icons.play_arrow_rounded),
            ),
          ],
        ));
      },
    ),
  );
}
