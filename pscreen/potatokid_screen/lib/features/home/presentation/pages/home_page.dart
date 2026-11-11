import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:potatokid_screen/shared/widgets/kid_chrome.dart';
import 'package:pscreen_screen/core/media/sleep_timer_controller.dart';
import 'package:pscreen_screen/core/parental/parental_state_controller.dart';
import 'package:pscreen_screen/features/iptv/application/bloc/iptv_bloc.dart';
import 'package:pscreen_screen/features/iptv/application/bloc/iptv_event.dart';
import 'package:pscreen_screen/features/iptv/application/bloc/iptv_state.dart';
import 'package:potatokid_screen/features/iptv/presentation/components/live_player_widget.dart';

/// 首页（电视）：「首页」Tab 主体为全屏 IPTV 直播。
/// 频道列表由全局 [IptvBloc] 提供（main 中已用缓存优先加载并自动播放首个频道），
/// 「我的」页可通过同一状态机触发「刷新频道」后台更新。
///
/// 儿童模式只换工程态角标 / 加载页 / 错误页的外观与文案（深蓝体系 + 儿童向说法），
/// 播放器、频道条、刷新与重试的触发逻辑完全不变。
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ParentalStateController.instance,
      builder: (BuildContext context, _) {
        final bool kid = kidModeOn;
        return BlocBuilder<IptvBloc, IptvState>(
          builder: (context, state) {
            // 已有频道：始终铺满播放器；后台刷新时叠加一个轻量提示。
            if (state.channels.isNotEmpty) {
              return Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  LivePlayerWidget(channels: state.channels),
                  if (state.isRefreshing) _RefreshingBadge(kid: kid),
                  if (state.usingCachedList)
                    Positioned(
                      left: 16,
                      bottom: 16,
                      child: _CachedListNotice(kid: kid),
                    ),
                  // 定时关闭倒计时：左上角按秒刷新，未开启时自动隐藏。
                  Positioned(
                    left: 16,
                    top: 16,
                    child: _SleepCountdownBadge(kid: kid),
                  ),
                  // 更新与遥控测试胶囊由播放器快捷控制层统一绘制，避免重复焦点节点。
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
              return _LoadingView(kid: kid);
            }
            if (state.errorMessage != null) {
              return _ErrorView(
                message: state.errorMessage!,
                kid: kid,
                onRetry: () => context.read<IptvBloc>().add(const LoadIptv(isRefresh: true)),
              );
            }
            return Center(
              child: Text(
                (kid ? 'kid_common_empty' : 'common_empty').tr(),
                style: kid ? const TextStyle(color: Colors.white70, fontSize: 20) : null,
              ),
            );
          },
        );
      },
    );
  }
}

/// 后台刷新频道时的轻量角标（不影响播放）。
class _RefreshingBadge extends StatelessWidget {
  const _RefreshingBadge({required this.kid});

  final bool kid;

  @override
  Widget build(BuildContext context) {
    final Widget row = Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: kid ? KidPalette.accent : Colors.white,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          (kid ? 'kid_channels_refreshing' : 'settings_refreshing').tr(),
          style: const TextStyle(color: Colors.white, fontSize: 14),
        ),
      ],
    );
    return SafeArea(
      child: Align(
        alignment: Alignment.topRight,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: kid ? _KidBadge(child: row) : row,
        ),
      ),
    );
  }
}

/// 儿童模式角标统一底板：深蓝半透明 + 白描边。
class _KidBadge extends StatelessWidget {
  const _KidBadge({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: KidPalette.capsule,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white24),
      ),
      child: child,
    );
  }
}

/// 定时关闭倒计时：首页左上角的「⏱ mm:ss」小角标。
///
/// 监听全局 [SleepTimerController]，每秒刷新剩余时间；未开启时隐藏。
/// 用局部 ListenableBuilder 刷新，避免每秒重建整个首页（播放器不会闪）。
class _SleepCountdownBadge extends StatelessWidget {
  const _SleepCountdownBadge({required this.kid});

  final bool kid;

  /// 把剩余时间格式化为 `mm:ss`（≥1 小时则为 `H:mm:ss`）。
  static String _format(Duration d) {
    final String mm = (d.inMinutes % 60).toString().padLeft(2, '0');
    final String ss = (d.inSeconds % 60).toString().padLeft(2, '0');
    if (d.inHours > 0) return '${d.inHours}:$mm:$ss';
    return '$mm:$ss';
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: SleepTimerController.instance,
      builder: (context, _) {
        final SleepTimerController timer = SleepTimerController.instance;
        if (!timer.active) return const SizedBox.shrink();
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: kid ? KidPalette.capsule : Colors.black.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(kid ? 12 : 8),
            border: kid ? Border.all(color: Colors.white24) : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                Icons.timer_outlined,
                color: kid ? KidPalette.accent : Colors.white,
                size: 18,
              ),
              const SizedBox(width: 6),
              Text(
                _format(timer.remaining),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 首次启动（无本地缓存）的加载态：进度指示 + 明确文案，避免白屏干等。
class _LoadingView extends StatelessWidget {
  const _LoadingView({required this.kid});

  final bool kid;

  @override
  Widget build(BuildContext context) {
    final Widget content = Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        CircularProgressIndicator(color: kid ? KidPalette.accent : Colors.white),
        const SizedBox(height: 16),
        Text(
          (kid ? 'kid_channels_loading' : 'channels_loading').tr(),
          style: const TextStyle(color: Colors.white, fontSize: 16),
        ),
      ],
    );
    if (!kid) return Center(child: content);
    return Center(
      child: KidSurface(
        dialog: true,
        padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 28),
        child: content,
      ),
    );
  }
}

/// 拉取失败但本地有缓存时的轻提示：不打断播放。
class _CachedListNotice extends StatelessWidget {
  const _CachedListNotice({required this.kid});

  final bool kid;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: kid
          ? const EdgeInsets.symmetric(horizontal: 12, vertical: 8)
          : const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: kid ? KidPalette.capsule : Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(kid ? 12 : 6),
        border: kid ? Border.all(color: Colors.white24) : null,
      ),
      child: Text(
        (kid ? 'kid_channels_cached_notice' : 'channels_cached_notice').tr(),
        style: TextStyle(color: Colors.white70, fontSize: kid ? 14 : 12),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({
    required this.message,
    required this.onRetry,
    required this.kid,
  });

  final String message;
  final VoidCallback onRetry;
  final bool kid;

  @override
  Widget build(BuildContext context) {
    if (!kid) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(message, style: const TextStyle(color: Colors.white)),
            const SizedBox(height: 12),
            FilledButton(autofocus: true, onPressed: onRetry, child: Text('common_retry'.tr())),
          ],
        ),
      );
    }
    // 儿童模式不展示原始错误信息，只保留同一个「重试」入口（autofocus 不变）。
    return Center(
      child: KidSurface(
        dialog: true,
        width: 620,
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.cloud_off_rounded, color: KidPalette.accent, size: 48),
            const SizedBox(height: 16),
            Text(
              'kid_channels_error'.tr(),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 20),
            ),
            const SizedBox(height: 24),
            KidActionButton(
              label: 'kid_common_retry'.tr(),
              autofocus: true,
              onPressed: onRetry,
            ),
          ],
        ),
      ),
    );
  }
}
