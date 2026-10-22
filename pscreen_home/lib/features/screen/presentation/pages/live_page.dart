import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:pscreen_home/features/screen/presentation/components/live_player_view.dart';
import 'package:pscreen_screen/features/iptv/application/bloc/iptv_bloc.dart';
import 'package:pscreen_screen/features/iptv/application/bloc/iptv_event.dart';
import 'package:pscreen_screen/features/iptv/application/bloc/iptv_state.dart';
import 'package:pscreen_screen/features/iptv/application/live_channel_controller.dart';
import 'package:pscreen_screen/features/iptv/domain/models/iptv_channel.dart';

/// 直播页：上方播放器 + 下方频道列表（触屏点选切台）。
class LivePage extends StatelessWidget {
  const LivePage({super.key, this.enablePlayer = true});

  /// 是否实例化真实播放器（测试环境置 false）。
  final bool enablePlayer;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('直播'),
        actions: <Widget>[
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () =>
                context.read<IptvBloc>().add(const LoadIptv(isRefresh: true)),
          ),
        ],
      ),
      body: BlocConsumer<IptvBloc, IptvState>(
        listener: (BuildContext context, IptvState state) {
          // 共享包的频道控制器按「频道总数」判断 select/next 是否有效，
          // 这里同步一次，触屏点选才能立即切台。
          // 放在 listener（状态变化时）而不是 build：build 阶段的副作用会
          // 在重建中触发 notifyListeners，导致不必要的重绘。
          LiveChannelController.instance.setCount(state.channels.length);
        },
        builder: (BuildContext context, IptvState state) {
          if (state.isLoading && state.channels.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state.errorMessage != null && state.channels.isEmpty) {
            return Center(
              child: Text(
                state.errorMessage!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            );
          }
          final List<IptvChannel> channels = state.channels;
          return Column(
            children: <Widget>[
              if (enablePlayer && channels.isNotEmpty)
                LivePlayerView(channels: channels)
              else
                const AspectRatio(
                  aspectRatio: 16 / 9,
                  child: ColoredBox(
                    color: Colors.black,
                    child: Center(
                      child: Text('播放器', style: TextStyle(color: Colors.white38)),
                    ),
                  ),
                ),
              Expanded(
                child: ListenableBuilder(
                  listenable: LiveChannelController.instance,
                  builder: (BuildContext context, Widget? child) {
                    final int current = LiveChannelController.instance.index;
                    return ListView.builder(
                      itemCount: channels.length,
                      itemBuilder: (BuildContext context, int index) {
                        final IptvChannel channel = channels[index];
                        return ListTile(
                          title: Text(channel.name),
                          subtitle: channel.group == null || channel.group!.isEmpty
                              ? null
                              : Text(channel.group!),
                          selected: index == current,
                          onTap: () => LiveChannelController.instance.select(index),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
