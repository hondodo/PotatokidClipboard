import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:potatokid_screen/core/di/injection.dart';
import 'package:potatokid_screen/features/iptv/application/bloc/iptv_bloc.dart';
import 'package:potatokid_screen/features/iptv/application/bloc/iptv_event.dart';
import 'package:potatokid_screen/features/iptv/application/bloc/iptv_state.dart';
import 'package:potatokid_screen/features/iptv/presentation/components/live_player_widget.dart';

/// 首页（电视）：「首页」Tab 主体为全屏 IPTV 直播。
/// 进入即自动加载远程 m3u 列表并自动播放首个频道，底部频道条焦点即切台。
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<IptvBloc>(
      create: (_) => Injection.get<IptvBloc>()..add(const LoadIptv()),
      child: const _IptvHomeView(),
    );
  }
}

class _IptvHomeView extends StatelessWidget {
  const _IptvHomeView();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<IptvBloc, IptvState>(
      builder: (context, state) {
        if (state.isLoading) {
          return const Center(
            child: CircularProgressIndicator(color: Colors.white),
          );
        }
        if (state.errorMessage != null) {
          return _ErrorView(
            message: state.errorMessage!,
            onRetry: () => context.read<IptvBloc>().add(const LoadIptv()),
          );
        }
        if (state.channels.isEmpty) {
          return Center(child: Text('common_empty'.tr()));
        }
        return LivePlayerWidget(channels: state.channels);
      },
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
          FilledButton(
            onPressed: onRetry,
            child: Text('common_retry'.tr()),
          ),
        ],
      ),
    );
  }
}