import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:potatokid_screen/features/app/application/bloc/app_bloc.dart';
import 'package:potatokid_screen/features/app/application/bloc/app_state.dart';
import 'package:potatokid_screen/features/iptv/domain/models/iptv_channel.dart';
import 'package:potatokid_screen/features/iptv/presentation/components/channel_bar.dart';

/// 全屏直播播放组件：持有 [Player]/[VideoController]，进入即自动播放首个频道，
/// 底部叠加横向频道条（焦点移到即切台）。销毁时释放播放器资源。
class LivePlayerWidget extends StatefulWidget {
  const LivePlayerWidget({super.key, required this.channels});

  /// 已解析的频道列表（非空）
  final List<IptvChannel> channels;

  @override
  State<LivePlayerWidget> createState() => _LivePlayerWidgetState();
}

class _LivePlayerWidgetState extends State<LivePlayerWidget> {
  Player? _player;
  VideoController? _controller;
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    // MediaKit.ensureInitialized() 已在 main() 中调用。
    final Player player = Player();
    _player = player;
    _controller = VideoController(player);
    _openChannel(0);
  }

  Future<void> _openChannel(int index) async {
    if (index < 0 || index >= widget.channels.length) return;
    await _player?.open(Media(widget.channels[index].url));
  }

  void _onChange(int index) {
    if (index == _selectedIndex) return;
    setState(() => _selectedIndex = index);
    _openChannel(index);
  }

  @override
  void dispose() {
    _player?.dispose();
    _player = null;
    _controller = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final VideoController? controller = _controller;
    if (controller == null || widget.channels.isEmpty) {
      return const ColoredBox(color: Colors.black);
    }
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        ColoredBox(
          color: Colors.black,
          // 全屏渲染视频，隐藏 media_kit 自带控件（用自定义频道条交互）。
          child: Video(
            controller: controller,
            controls: NoVideoControls,
          ),
        ),
        // 频道条作为悬浮层，跟随导航条显隐一起收起，不常驻（全屏观看）。
        Align(
          alignment: Alignment.bottomCenter,
          child: BlocBuilder<AppBloc, AppState>(
            buildWhen: (previous, current) =>
                previous.isChromeVisible != current.isChromeVisible,
            builder: (context, state) {
              return ClipRect(
                child: AnimatedAlign(
                  alignment: Alignment.bottomCenter,
                  heightFactor: state.isChromeVisible ? 1 : 0,
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeInOut,
                  child: ChannelBar(
                    channels: widget.channels,
                    selectedIndex: _selectedIndex,
                    onChanged: _onChange,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}