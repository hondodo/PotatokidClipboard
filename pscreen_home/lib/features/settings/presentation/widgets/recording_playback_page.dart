import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// 录制回放页（home 端）：独立 Player，与直播播放器隔离。
class RecordingPlaybackPage extends StatefulWidget {
  const RecordingPlaybackPage({super.key, required this.uri, required this.title});

  final String uri;
  final String title;

  @override
  State<RecordingPlaybackPage> createState() => _RecordingPlaybackPageState();
}

class _RecordingPlaybackPageState extends State<RecordingPlaybackPage> {
  late final Player _player;
  late final VideoController _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _player = Player();
    _controller = VideoController(_player);
    _player.open(Media(widget.uri)).catchError((Object e) {
      if (mounted) setState(() => _error = e.toString());
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: Text(widget.title), backgroundColor: Colors.black),
      body: Center(
        child: _error != null
            ? Text('无法播放：$_error', style: const TextStyle(color: Colors.white70))
            : Video(controller: _controller, controls: MaterialVideoControls),
      ),
    );
  }
}
