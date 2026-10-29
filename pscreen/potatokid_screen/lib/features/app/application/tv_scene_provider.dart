import 'package:flutter/foundation.dart';
import 'package:potatokid_screen/features/app/application/app_tab_controller.dart';
import 'package:pscreen_screen/features/iptv/application/channel_info_provider.dart';
import 'package:pscreen_screen/features/iptv/application/live_channel_controller.dart';
import 'package:pscreen_screen/features/msg/application/current_scene_provider.dart';

/// 电视端场景描述。
///
/// 还原重构前的上报语义：**只有停在首页（正在看直播）时报频道名**，
/// 其余 Tab（时间页 / 屏保 / 设置）报当前页名。
///
/// 注意：`MainApp` 用 `StatefulShellRoute.indexedStack`，离开首页时首页分支
/// 仍然挂载、`ChannelInfoProvider.instance.channels` 不会清空——所以必须先判
/// `branchIndex == 0`，否则会把「当前频道是设置」误报成「当前频道是CCTV-1」。
class TvSceneProvider extends CurrentSceneProvider {
  const TvSceneProvider();

  /// Tab 或频道变化都会触发场景推送（结构合并为一个 Listenable）。
  static final Listenable _changes = Listenable.merge(<Listenable>[
    AppTabController.changes,
    LiveChannelController.instance,
  ]);

  @override
  String describe() {
    if (AppTabController.branchIndex == 0) {
      final String? name = ChannelInfoProvider.instance
          .nameAt(LiveChannelController.instance.index);
      if (name != null) return name;
    }
    return AppTabController.pageName;
  }

  @override
  SceneSnapshot snapshot() {
    switch (AppTabController.branchIndex) {
      case 0:
        final int index = LiveChannelController.instance.index;
        return SceneSnapshot(
          kind: SceneKind.live,
          route: 'home',
          title: ChannelInfoProvider.instance.nameAt(index) ?? '主页',
          channelName: ChannelInfoProvider.instance.nameAt(index),
          extra: <String, Object?>{'channelIndex': index},
        );
      case 1:
        return const SceneSnapshot(
          kind: SceneKind.clock,
          route: 'time',
          title: '时间页',
        );
      case 2:
        return const SceneSnapshot(
          kind: SceneKind.screensaver,
          route: 'screensaver',
          title: '屏保',
        );
      default:
        return const SceneSnapshot(
          kind: SceneKind.settings,
          route: 'profile',
          title: '设置',
        );
    }
  }

  @override
  Listenable get changes => _changes;
}
