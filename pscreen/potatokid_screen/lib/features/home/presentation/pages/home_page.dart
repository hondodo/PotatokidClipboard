import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:potatokid_screen/features/iptv/application/bloc/iptv_bloc.dart';
import 'package:potatokid_screen/features/iptv/application/bloc/iptv_event.dart';
import 'package:potatokid_screen/features/iptv/application/bloc/iptv_state.dart';
import 'package:potatokid_screen/features/iptv/presentation/components/live_player_widget.dart';
import 'package:potatokid_screen/features/weather/presentation/widgets/weather_panel.dart';

/// 首页（电视）：「首页」Tab 主体为全屏 IPTV 直播。
/// 频道列表由全局 [IptvBloc] 提供（main 中已用缓存优先加载并自动播放首个频道），
/// 「我的」页可通过同一状态机触发「刷新频道」后台更新。
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<IptvBloc, IptvState>(
      builder: (context, state) {
        // 已有频道：始终铺满播放器；后台刷新时叠加一个轻量提示。
        if (state.channels.isNotEmpty) {
          return Stack(
            fit: StackFit.expand,
            children: <Widget>[
              LivePlayerWidget(channels: state.channels),
              if (state.isRefreshing) const _RefreshingBadge(),
              // // 天气小组件：右上角悬浮，无数据时自动隐藏。
              // const Positioned(
              //   top: 12,
              //   right: 12,
              //   child: SafeArea(child: WeatherPanel()),
              // ),
            ],
          );
        }
        // 暂无频道：加载中 / 出错 / 空。
        if (state.isLoading || state.isRefreshing) {
          return const Center(child: CircularProgressIndicator(color: Colors.white));
        }
        if (state.errorMessage != null) {
          return _ErrorView(
            message: state.errorMessage!,
            onRetry: () => context.read<IptvBloc>().add(const LoadIptv(isRefresh: true)),
          );
        }
        return Center(child: Text('common_empty'.tr()));
      },
    );
  }
}

/// 后台刷新频道时的轻量角标（不影响播放）。
class _RefreshingBadge extends StatelessWidget {
  const _RefreshingBadge();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Align(
        alignment: Alignment.topRight,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              ),
              const SizedBox(width: 8),
              Text('settings_refreshing'.tr(), style: const TextStyle(color: Colors.white, fontSize: 14)),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(message, style: const TextStyle(color: Colors.white)),
          const SizedBox(height: 12),
          FilledButton(onPressed: onRetry, child: Text('common_retry'.tr())),
        ],
      ),
    );
  }
}
