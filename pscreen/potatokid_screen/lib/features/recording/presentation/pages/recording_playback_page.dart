import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// 录制回放页：用 media_kit 播放一个本地 / SAF 录制文件。
///
/// 与直播播放器完全隔离（独立 Player），不影响直播遥控链路。
class RecordingPlaybackPage extends StatefulWidget {
  const RecordingPlaybackPage({super.key, required this.uri, required this.title});

  /// internal 为绝对路径；SAF 为 content:// URI（media_kit 直接支持）。
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
      appBar: AppBar(
        title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        backgroundColor: Colors.black,
      ),
      body: Center(
        child: _error != null
            ? Text(
                'recording_play_failed'.tr(args: <String>[_error!]),
                style: const TextStyle(color: Colors.white70),
              )
            : Video(controller: _controller, controls: MaterialVideoControls),
      ),
    );
  }
}
